//! Native resources whose lifetime follows a Roc box, including Roc-side frees.
//!
//! A handle is a Roc `Box(U64)` whose payload is a raw pointer to a Rust value.
//! Compiled Roc may perform the final decref itself and free the box without
//! calling a hosted function, so the only reliable place to destroy the Rust
//! value is the allocator. The host therefore allocates handle boxes from its
//! own *typed heaps* rather than from the general allocator: every handle kind
//! owns a fixed address range of box-sized slots, and `roc_dealloc` recognises
//! a handle by address alone. A free outside the ranges costs one comparison.
//! A free inside them runs that kind's destructor and recycles the slot.
//!
//! Because the kind is a property of the address, `resource_ref` can check that
//! a handle really is a live handle of the requested type before dereferencing
//! it, and the number of live handles of a kind is its number of occupied slots
//! (reported at exit when `BASIC_CLI_LIVE_HANDLES` is set).
//!
//! # Adding a handle kind
//!
//! 1. Add one line to the `resource_kinds!` list below: `Name => RustType,`.
//!    That declares `Kind::Name`, gives it an address range, a destructor and a
//!    live-handle counter, and implements `Resource` for `RustType`. Each kind
//!    needs its own Rust type; wrap a shared type in a newtype if necessary.
//! 2. Add the matching alias to `platform/Resource.roc`:
//!    `Name : Handle([NameKind])`, then regenerate the glue.
//!
//! Hosted functions then use the three calls every kind shares:
//! `box_resource(value, host)?` to create a handle, `resource_ref::<T>(handle)`
//! to borrow the value behind one, and `release(handle, host)` to drop the
//! reference a hosted function was passed.
//!
//! # Failed checks
//!
//! Roc's type system already rejects a handle of the wrong kind, and reference
//! counting keeps a handle alive while Roc can still name it. A handle that
//! fails `resource_ref`'s check, a free of a slot that is not occupied, or a
//! reallocation of a slot therefore means the host or the compiler corrupted
//! memory, not that the application made a mistake. There is no error an
//! application could act on, so these cases panic with a message naming the
//! kind and address. Hosted functions are `extern "C"`, so the panic aborts the
//! process (after the panic hook has restored the terminal).
//!
//! # Threads
//!
//! Roc runs only on the thread that calls `roc_main`, and resource values are
//! not required to be `Send`, so handles are created, used and destroyed on
//! that thread; debug builds assert it once `bind_host_thread` has been called.
//! The slot bookkeeping is nevertheless behind a mutex, uncontended in a
//! running program, so that the parallel `cargo test` harness, where every test
//! thread plays the host, stays sound. Frees of ordinary memory never take it.
use crate::roc_platform_abi::*;
use std::ffi::c_void;
use std::io;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};
use std::thread::ThreadId;

/// A Rust type owned by a Roc handle. Implemented only by `resource_kinds!`,
/// which keeps the mapping between kinds and types one-to-one: the destructor
/// run for a slot is chosen by its kind alone.
pub trait Resource: Sized + 'static {
    const KIND: Kind;
}

macro_rules! resource_kinds {
    ($($(#[$attr:meta])* $name:ident => $ty:ty,)+) => {
        /// A handle kind. The names match the aliases in `platform/Resource.roc`.
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub enum Kind {
            $($(#[$attr])* $name,)+
        }

        impl Kind {
            pub const ALL: &'static [Kind] = &[$($(#[$attr])* Kind::$name,)+];

            pub fn name(self) -> &'static str {
                match self {
                    $($(#[$attr])* Kind::$name => stringify!($name),)+
                }
            }
        }

        /// Indexed by `Kind as usize`.
        const DESTRUCTORS: &[unsafe fn(u64)] = &[$($(#[$attr])* drop_payload::<$ty>,)+];

        $($(#[$attr])* impl Resource for $ty {
            const KIND: Kind = Kind::$name;
        })+
    };
}

resource_kinds! {
    Child => crate::process_service::Child,
    FileReader => std::io::BufReader<std::fs::File>,
    FileWriter => crate::file_writer::FileWriter,
    HttpResponse => crate::http::StreamingBody,
    SqliteDb => crate::sqlite::SqliteDb,
    SqliteRows => crate::sqlite::SqliteRows,
    TcpConnection => crate::tcp::Connection,
    TcpListener => crate::listener::Listener,
    UnixSocketConnection => crate::unix_socket::Connection,
    UnixSocketListener => crate::unix_socket::Listener,
    #[cfg(test)]
    TestA => tests::Probe<0>,
    #[cfg(test)]
    TestB => tests::Probe<1>,
    #[cfg(test)]
    TestC => tests::Probe<2>,
    #[cfg(test)]
    TestD => tests::Probe<3>,
    #[cfg(test)]
    TestNested => tests::Nested,
}

const KIND_COUNT: usize = Kind::ALL.len();

/// Slots per kind in the process-wide heap: 16 MiB of address space each on a
/// 64-bit target. Only the slots a program has used are backed by memory.
const SLOTS_PER_KIND: usize = 1 << 20;

// The layout the glue's `allocate_box` gives a `Box(U64)`, which is also what
// compiled Roc assumes: the payload follows a header that ends with the
// refcount, and the allocation starts where the header does.
const PAYLOAD_ALIGN: usize = align_of::<u64>();
pub(crate) const HEADER_BYTES: usize = if size_of::<usize>() > PAYLOAD_ALIGN {
    size_of::<usize>()
} else {
    PAYLOAD_ALIGN
};
const SLOT_BYTES: usize = HEADER_BYTES + size_of::<u64>();

/// Memory is committed in steps of this size, a multiple of every supported
/// page size and of the Windows allocation granularity.
const COMMIT_BYTES: usize = 64 * 1024;

const fn round_up_to_commit(bytes: usize) -> usize {
    bytes.div_ceil(COMMIT_BYTES) * COMMIT_BYTES
}

#[cfg(unix)]
mod os {
    use std::io;

    /// Claim address space without backing it by memory.
    pub fn reserve(bytes: usize) -> io::Result<*mut u8> {
        let address = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                bytes,
                libc::PROT_NONE,
                libc::MAP_PRIVATE | libc::MAP_ANON,
                -1,
                0,
            )
        };
        if address == libc::MAP_FAILED {
            Err(io::Error::last_os_error())
        } else {
            Ok(address.cast())
        }
    }

    /// Make part of a reservation readable and writable; new pages read as zero.
    pub fn commit(address: *mut u8, bytes: usize) -> io::Result<()> {
        if unsafe { libc::mprotect(address.cast(), bytes, libc::PROT_READ | libc::PROT_WRITE) } == 0
        {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }

    pub fn release(address: *mut u8, bytes: usize) {
        unsafe { libc::munmap(address.cast(), bytes) };
    }
}

#[cfg(windows)]
mod os {
    use std::io;
    use windows_sys::Win32::System::Memory::{
        VirtualAlloc, VirtualFree, MEM_COMMIT, MEM_RELEASE, MEM_RESERVE, PAGE_NOACCESS,
        PAGE_READWRITE,
    };

    /// Claim address space without backing it by memory.
    pub fn reserve(bytes: usize) -> io::Result<*mut u8> {
        let address = unsafe { VirtualAlloc(std::ptr::null(), bytes, MEM_RESERVE, PAGE_NOACCESS) };
        if address.is_null() {
            Err(io::Error::last_os_error())
        } else {
            Ok(address.cast())
        }
    }

    /// Make part of a reservation readable and writable; new pages read as zero.
    pub fn commit(address: *mut u8, bytes: usize) -> io::Result<()> {
        if unsafe { VirtualAlloc(address.cast(), bytes, MEM_COMMIT, PAGE_READWRITE) }.is_null() {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    pub fn release(address: *mut u8, _bytes: usize) {
        unsafe { VirtualFree(address.cast(), 0, MEM_RELEASE) };
    }
}

/// Bookkeeping for one kind's range of slots.
struct KindSlots {
    /// Bytes at the start of the range that are backed by memory.
    committed_bytes: usize,
    /// Slots below this index have been handed out at least once.
    used: usize,
    /// Freed slots below `used`, reused before a fresh slot is taken.
    free: Vec<u32>,
    /// One bit per slot below `used`, set while the slot holds a live box.
    occupied: Vec<u64>,
    live: usize,
}

impl KindSlots {
    const fn new() -> Self {
        Self {
            committed_bytes: 0,
            used: 0,
            free: Vec::new(),
            occupied: Vec::new(),
            live: 0,
        }
    }

    fn is_occupied(&self, slot: usize) -> bool {
        self.occupied
            .get(slot / 64)
            .is_some_and(|word| word & (1 << (slot % 64)) != 0)
    }

    fn set_occupied(&mut self, slot: usize, occupied: bool) {
        if self.occupied.len() <= slot / 64 {
            self.occupied.resize(slot / 64 + 1, 0);
        }
        let word = &mut self.occupied[slot / 64];
        if occupied {
            *word |= 1 << (slot % 64);
        } else {
            *word &= !(1 << (slot % 64));
        }
    }
}

/// Where an address falls inside a heap.
struct Location {
    kind: usize,
    slot: usize,
    /// Zero when the address is the start of the slot.
    offset_in_slot: usize,
}

/// One contiguous reservation holding a range of `slots_per_kind` slots for
/// every kind, so recognising any handle is a single range comparison.
struct Heap {
    /// Address of the reservation, or zero until the first handle is created.
    base: AtomicUsize,
    slots_per_kind: usize,
    /// Bytes of address space given to each kind.
    kind_bytes: usize,
    total_bytes: usize,
    slots: Mutex<[KindSlots; KIND_COUNT]>,
}

impl Heap {
    const fn new(slots_per_kind: usize) -> Self {
        assert!(slots_per_kind > 0 && slots_per_kind <= u32::MAX as usize);
        let kind_bytes = round_up_to_commit(slots_per_kind * SLOT_BYTES);
        Self {
            base: AtomicUsize::new(0),
            slots_per_kind,
            kind_bytes,
            total_bytes: kind_bytes * KIND_COUNT,
            slots: Mutex::new([const { KindSlots::new() }; KIND_COUNT]),
        }
    }

    fn lock(&self) -> MutexGuard<'_, [KindSlots; KIND_COUNT]> {
        // The bookkeeping is never left half-updated across a panic.
        self.slots.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The range check every deallocation pays for.
    #[inline]
    fn locate(&self, address: usize) -> Option<Location> {
        let base = self.base.load(Ordering::Acquire);
        let offset = address.wrapping_sub(base);
        if base == 0 || offset >= self.total_bytes {
            return None;
        }
        let in_kind = offset % self.kind_bytes;
        Some(Location {
            kind: offset / self.kind_bytes,
            slot: in_kind / SLOT_BYTES,
            offset_in_slot: in_kind % SLOT_BYTES,
        })
    }

    fn slot_address(&self, base: usize, kind: usize, slot: usize) -> *mut u8 {
        (base + kind * self.kind_bytes + slot * SLOT_BYTES) as *mut u8
    }

    /// Take a slot for `kind` and return its address. The slot is zeroed.
    fn take_slot(&self, kind: Kind) -> io::Result<*mut u8> {
        let mut slots = self.lock();
        let mut base = self.base.load(Ordering::Acquire);
        if base == 0 {
            base = os::reserve(self.total_bytes)? as usize;
            self.base.store(base, Ordering::Release);
        }
        let kind_slots = &mut slots[kind as usize];
        let slot = match kind_slots.free.pop() {
            Some(slot) => slot as usize,
            None => {
                if kind_slots.used == self.slots_per_kind {
                    return Err(io::Error::new(
                        io::ErrorKind::OutOfMemory,
                        format!(
                            "too many open {} handles (limit {})",
                            kind.name(),
                            self.slots_per_kind
                        ),
                    ));
                }
                let needed = (kind_slots.used + 1) * SLOT_BYTES;
                if needed > kind_slots.committed_bytes {
                    let start = self.slot_address(base, kind as usize, 0);
                    os::commit(
                        unsafe { start.add(kind_slots.committed_bytes) },
                        COMMIT_BYTES,
                    )?;
                    kind_slots.committed_bytes += COMMIT_BYTES;
                }
                kind_slots.used += 1;
                kind_slots.used - 1
            }
        };
        kind_slots.set_occupied(slot, true);
        kind_slots.live += 1;
        Ok(self.slot_address(base, kind as usize, slot))
    }

    /// Free the slot starting at `address`, returning its kind and the payload
    /// it held, or `None` if the address is outside this heap.
    fn free_slot(&self, address: usize) -> Option<(usize, u64)> {
        let location = self.locate(address)?;
        let payload = {
            let mut slots = self.lock();
            let kind_slots = &mut slots[location.kind];
            if location.offset_in_slot == 0 && kind_slots.is_occupied(location.slot) {
                let payload = unsafe {
                    let payload_ptr = (address as *mut u8).add(HEADER_BYTES).cast::<u64>();
                    let payload = payload_ptr.read();
                    // A stale copy of the handle now sees a null payload and a
                    // refcount that Roc treats as static data.
                    (address as *mut u8).write_bytes(0, SLOT_BYTES);
                    payload
                };
                kind_slots.set_occupied(location.slot, false);
                kind_slots.live -= 1;
                kind_slots.free.push(location.slot as u32);
                Some(payload)
            } else {
                None
            }
        };
        match payload {
            Some(payload) => Some((location.kind, payload)),
            None => panic!(
                "basic-cli host bug: freed {:#x}, which is not a live {} handle allocation",
                address,
                Kind::ALL[location.kind].name()
            ),
        }
    }

    /// Check that `handle` is the payload pointer of a live box of `kind`.
    fn check_handle(&self, handle: usize, kind: Kind) -> Result<(), &'static str> {
        let Some(location) = self.locate(handle.wrapping_sub(HEADER_BYTES)) else {
            return Err("it was not allocated as a resource handle");
        };
        if location.kind != kind as usize {
            return Err("it is a handle of another kind");
        }
        if location.offset_in_slot != 0 {
            return Err("it does not point at a handle's payload");
        }
        if !self.lock()[location.kind].is_occupied(location.slot) {
            return Err("it has already been freed");
        }
        Ok(())
    }

    fn live(&self, kind: Kind) -> usize {
        self.lock()[kind as usize].live
    }
}

impl Drop for Heap {
    fn drop(&mut self) {
        let base = *self.base.get_mut();
        if base != 0 {
            os::release(base as *mut u8, self.total_bytes);
        }
    }
}

static HEAP: Heap = Heap::new(SLOTS_PER_KIND);

static HOST_THREAD: OnceLock<ThreadId> = OnceLock::new();

/// Record the calling thread as the one Roc runs on. Debug builds then assert
/// that handles are only created, borrowed and destroyed on it.
pub fn bind_host_thread() {
    let _ = HOST_THREAD.set(std::thread::current().id());
}

#[inline]
fn debug_assert_host_thread() {
    #[cfg(debug_assertions)]
    if let Some(host_thread) = HOST_THREAD.get() {
        assert_eq!(
            std::thread::current().id(),
            *host_thread,
            "basic-cli host bug: resource handle used off the host thread"
        );
    }
}

unsafe fn drop_payload<T>(payload: u64) {
    let raw = payload as *mut T;
    if !raw.is_null() {
        drop(unsafe { Box::from_raw(raw) });
    }
}

/// Move `value` into a new handle holding one reference. The value is dropped
/// when the last reference is released, by a hosted function or by Roc.
///
/// Fails, dropping `value`, if the kind's address range is full or the
/// operating system refuses the memory.
pub fn box_resource<T: Resource>(value: T, _host: &RocHost) -> io::Result<*mut u64> {
    debug_assert_host_thread();
    let slot = HEAP.take_slot(T::KIND)?;
    unsafe {
        let payload = slot.add(HEADER_BYTES).cast::<u64>();
        payload.cast::<isize>().sub(1).write(1);
        payload.write(Box::into_raw(Box::new(value)) as u64);
        Ok(payload)
    }
}

/// Borrow the value behind a handle after checking that `handle` is a live
/// handle whose kind is `T`'s. A failed check panics; see the module docs.
///
/// # Safety
///
/// The caller must hold a reference to the handle for as long as the borrow
/// lives, and must not create overlapping borrows of the same handle.
pub unsafe fn resource_ref<'a, T: Resource>(handle: *mut u64) -> &'a mut T {
    debug_assert_host_thread();
    if let Err(reason) = HEAP.check_handle(handle as usize, T::KIND) {
        panic!(
            "basic-cli host bug: {handle:p} is not a live {} handle: {reason}",
            T::KIND.name()
        );
    }
    unsafe { &mut *(handle.read() as *mut T) }
}

/// Drop one reference to a handle, destroying its value if it was the last.
pub fn release(handle: *mut u64, host: &RocHost) {
    unsafe { decref_box_with(handle.cast(), PAYLOAD_ALIGN, false, None, host) };
}

/// `roc_dealloc`: destroy the resource and recycle the slot when `ptr` is a
/// handle allocation, and free ordinary memory otherwise.
pub extern "C" fn dealloc(host: *mut RocHost, ptr: *mut c_void, alignment: usize) {
    if !destroy_if_resource(ptr) {
        DefaultAllocators::roc_dealloc(host, ptr, alignment);
    }
}

/// Returns false, having done nothing, unless `ptr` is a handle allocation.
fn destroy_if_resource(ptr: *mut c_void) -> bool {
    // The slot is free before the destructor runs: a native destructor can
    // release other handles, or open new ones.
    match HEAP.free_slot(ptr as usize) {
        Some((kind, payload)) => {
            debug_assert_host_thread();
            unsafe { DESTRUCTORS[kind](payload) };
            true
        }
        None => false,
    }
}

/// `roc_realloc`: handle boxes have a fixed size, so Roc never resizes one.
pub extern "C" fn realloc(
    host: *mut RocHost,
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> NonNull<c_void> {
    assert_not_resource(ptr);
    DefaultAllocators::roc_realloc(host, ptr, new_length, alignment)
}

fn assert_not_resource(ptr: *mut c_void) {
    if let Some(location) = HEAP.locate(ptr as usize) {
        panic!(
            "basic-cli host bug: reallocated {ptr:p}, which is a {} handle allocation",
            Kind::ALL[location.kind].name()
        );
    }
}

pub fn make_host() -> RocHost {
    let mut host = make_roc_host(std::ptr::null_mut());
    host.roc_dealloc = dealloc;
    host.roc_realloc = realloc;
    host
}

/// The number of live handles of each kind, in declaration order.
pub fn live_handles() -> impl Iterator<Item = (Kind, usize)> {
    Kind::ALL.iter().map(|kind| (*kind, HEAP.live(*kind)))
}

/// The environment variable that makes the host report live handles at exit.
pub const LIVE_HANDLES_ENV: &str = "BASIC_CLI_LIVE_HANDLES";

/// Write the live-handle report: a `live handles: N` total followed by one
/// `live handles[Kind]: N` line per kind.
pub fn write_live_handles(out: &mut impl io::Write) -> io::Result<()> {
    let counts: Vec<(Kind, usize)> = live_handles().collect();
    let total: usize = counts.iter().map(|(_, live)| live).sum();
    let mut report = format!("live handles: {total}\n");
    for (kind, live) in counts {
        report.push_str(&format!("live handles[{}]: {live}\n", kind.name()));
    }
    out.write_all(report.as_bytes())
}

/// Report live handles on stderr when `BASIC_CLI_LIVE_HANDLES` is set to a
/// non-empty value. Called after `main!` returns, when every handle the
/// application opened should have been released; tests assert on the total.
pub fn report_live_handles_if_requested() {
    if std::env::var_os(LIVE_HANDLES_ENV).is_some_and(|value| !value.is_empty()) {
        // A closed stderr must not turn a successful run into a failure.
        let _ = write_live_handles(&mut io::stderr().lock());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::rc::Rc;

    /// Counts drops. Each `N` is its own kind, so tests that assert on a
    /// kind's counters or slots do not disturb one another when run in parallel.
    pub struct Probe<const N: usize>(Rc<Cell<usize>>);
    impl<const N: usize> Drop for Probe<N> {
        fn drop(&mut self) {
            self.0.set(self.0.get() + 1);
        }
    }

    /// Releases another handle from its destructor.
    pub struct Nested {
        handle: *mut u64,
        host: RocHost,
    }
    impl Drop for Nested {
        fn drop(&mut self) {
            release(self.handle, &self.host);
        }
    }

    fn probe<const N: usize>(host: &RocHost) -> (*mut u64, Rc<Cell<usize>>)
    where
        Probe<N>: Resource,
    {
        let count = Rc::new(Cell::new(0));
        (
            box_resource(Probe::<N>(count.clone()), host).unwrap(),
            count,
        )
    }

    fn allocation_base(handle: *mut u64) -> *mut c_void {
        unsafe { handle.cast::<u8>().sub(HEADER_BYTES).cast() }
    }

    fn panic_message(f: impl FnOnce() + std::panic::UnwindSafe) -> String {
        let payload = std::panic::catch_unwind(f).expect_err("expected a panic");
        payload
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| payload.downcast_ref::<&str>().map(|s| (*s).to_owned()))
            .unwrap()
    }

    #[test]
    fn slot_layout_matches_the_glue_box_layout() {
        // `box_resource` writes the header itself; the glue must agree on where
        // the refcount lives and which address it hands back to `roc_dealloc`.
        let host = make_host();
        let (handle, count) = probe::<0>(&host);
        unsafe { incref_box(handle.cast(), 2) };
        assert_eq!(unsafe { handle.cast::<isize>().sub(1).read() }, 3);
        release(handle, &host);
        release(handle, &host);
        assert_eq!(count.get(), 0);
        release(handle, &host);
        assert_eq!(count.get(), 1);

        let ordinary =
            unsafe { allocate_box(size_of::<u64>(), align_of::<u64>(), false, &host) } as *mut u64;
        assert_eq!(
            unsafe { ordinary.cast::<isize>().sub(1).read() },
            1,
            "refcount position"
        );
        unsafe { ordinary.write(7) };
        // Not a resource: freeing it takes the ordinary path.
        assert!(HEAP.locate(allocation_base(ordinary) as usize).is_none());
        release(ordinary, &host);
    }

    #[test]
    fn final_host_release_destroys_exactly_once() {
        let host = make_host();
        let (handle, count) = probe::<0>(&host);
        unsafe { incref_box(handle.cast(), 1) };
        release(handle, &host);
        assert_eq!(count.get(), 0);
        release(handle, &host);
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn roc_style_final_free_destroys_payload() {
        let mut host = make_host();
        let (handle, count) = probe::<0>(&host);
        // Compiled Roc frees the allocation directly after decrementing to zero.
        dealloc(&mut host, allocation_base(handle), align_of::<u64>());
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn destructor_can_release_another_resource() {
        let host = make_host();
        let (inner, count) = probe::<0>(&host);
        let outer = box_resource(
            Nested {
                handle: inner,
                host: make_host(),
            },
            &host,
        )
        .unwrap();
        release(outer, &host);
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn accessor_returns_the_boxed_value() {
        let host = make_host();
        let (handle, count) = probe::<0>(&host);
        let value = unsafe { resource_ref::<Probe<0>>(handle) };
        assert!(Rc::ptr_eq(&value.0, &count));
        release(handle, &host);
    }

    #[test]
    fn accessor_rejects_a_handle_of_another_kind() {
        let host = make_host();
        let (handle, count) = probe::<0>(&host);
        let address = handle as usize;
        let message = panic_message(move || {
            unsafe { resource_ref::<Probe<1>>(address as *mut u64) };
        });
        assert!(message.contains("is not a live TestB handle"), "{message}");
        assert!(message.contains("another kind"), "{message}");
        release(handle, &host);
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn accessor_rejects_a_freed_handle() {
        // Kind C is used only here, so nothing reoccupies the slot in between.
        let host = make_host();
        let (handle, count) = probe::<2>(&host);
        release(handle, &host);
        assert_eq!(count.get(), 1);
        assert_eq!(
            HEAP.check_handle(handle as usize, Kind::TestC),
            Err("it has already been freed")
        );
        let address = handle as usize;
        let message = panic_message(move || {
            unsafe { resource_ref::<Probe<2>>(address as *mut u64) };
        });
        assert!(message.contains("already been freed"), "{message}");
        // The stale handle reads as a null payload with a static refcount.
        assert_eq!(unsafe { handle.read() }, 0);
        assert_eq!(unsafe { handle.cast::<isize>().sub(1).read() }, 0);
    }

    #[test]
    fn accessor_rejects_pointers_that_are_not_handles() {
        let host = make_host();
        let (handle, _count) = probe::<0>(&host);
        let mut outside = 0u64;
        assert_eq!(
            HEAP.check_handle(&raw mut outside as usize, Kind::TestA),
            Err("it was not allocated as a resource handle")
        );
        assert_eq!(
            HEAP.check_handle(handle as usize + 4, Kind::TestA),
            Err("it does not point at a handle's payload")
        );
        assert_eq!(HEAP.check_handle(handle as usize, Kind::TestA), Ok(()));
        release(handle, &host);
    }

    #[test]
    fn double_free_and_realloc_of_a_slot_are_rejected() {
        // Kind D is used only here.
        let host = make_host();
        let (handle, count) = probe::<3>(&host);
        let base = allocation_base(handle) as usize;
        let message = panic_message(move || {
            assert_not_resource(base as *mut c_void);
        });
        assert!(message.contains("TestD handle allocation"), "{message}");
        release(handle, &host);
        let message = panic_message(move || {
            destroy_if_resource(base as *mut c_void);
        });
        assert!(message.contains("not a live TestD handle"), "{message}");
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn counters_and_slot_reuse() {
        // Kind B is used only here.
        let host = make_host();
        assert_eq!(HEAP.live(Kind::TestB), 0);
        let (first, _) = probe::<1>(&host);
        let (second, _) = probe::<1>(&host);
        assert_ne!(first, second);
        assert_eq!(second as usize - first as usize, SLOT_BYTES);
        assert_eq!(HEAP.live(Kind::TestB), 2);
        assert!(live_handles().any(|(kind, live)| kind == Kind::TestB && live == 2));

        // An extra reference keeps the handle counted until its last release.
        unsafe { incref_box(first.cast(), 1) };
        release(first, &host);
        assert_eq!(HEAP.live(Kind::TestB), 2);
        release(first, &host);
        assert_eq!(HEAP.live(Kind::TestB), 1);

        let (reused, _) = probe::<1>(&host);
        assert_eq!(reused, first, "a freed slot is reused first");
        assert_eq!(unsafe { reused.cast::<isize>().sub(1).read() }, 1);
        assert_eq!(HEAP.live(Kind::TestB), 2);
        release(second, &host);
        release(reused, &host);
        assert_eq!(HEAP.live(Kind::TestB), 0);

        let mut report = Vec::new();
        write_live_handles(&mut report).unwrap();
        let report = String::from_utf8(report).unwrap();
        assert!(report.starts_with("live handles: "), "{report}");
        assert!(report.contains("\nlive handles[TestB]: 0\n"), "{report}");
        assert!(report.contains("\nlive handles[FileReader]: "), "{report}");
    }

    #[test]
    fn kinds_have_disjoint_ranges() {
        let host = make_host();
        let (a, count) = probe::<0>(&host);
        unsafe { incref_box(a.cast(), 1) };
        let nested = box_resource(
            Nested {
                handle: a,
                host: make_host(),
            },
            &host,
        )
        .unwrap();
        let a_location = HEAP.locate(allocation_base(a) as usize).unwrap();
        let nested_location = HEAP.locate(allocation_base(nested) as usize).unwrap();
        assert_eq!(a_location.kind, Kind::TestA as usize);
        assert_eq!(nested_location.kind, Kind::TestNested as usize);
        assert_eq!(a_location.offset_in_slot, 0);
        assert_eq!(HEAP.kind_bytes, SLOTS_PER_KIND * SLOT_BYTES);
        release(nested, &host);
        assert_eq!(count.get(), 0);
        release(a, &host);
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn full_range_fails_then_recovers_when_a_slot_is_freed() {
        let heap = Heap::new(3);
        let slots: Vec<*mut u8> = (0..3)
            .map(|_| heap.take_slot(Kind::TestA).unwrap())
            .collect();
        let error = heap.take_slot(Kind::TestA).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(error.to_string(), "too many open TestA handles (limit 3)");
        assert_eq!(heap.live(Kind::TestA), 3);
        // One kind being full does not affect another.
        let other = heap.take_slot(Kind::TestB).unwrap();
        assert_eq!(
            heap.free_slot(other as usize).unwrap().0,
            Kind::TestB as usize
        );

        unsafe { slots[1].add(HEADER_BYTES).cast::<u64>().write(41) };
        assert_eq!(
            heap.free_slot(slots[1] as usize),
            Some((Kind::TestA as usize, 41))
        );
        assert_eq!(heap.live(Kind::TestA), 2);
        assert_eq!(heap.take_slot(Kind::TestA).unwrap(), slots[1]);
        assert!(heap.take_slot(Kind::TestA).is_err());
        // Addresses outside this heap, including the process-wide one, are not its slots.
        assert!(heap.free_slot(&raw const heap as usize).is_none());
    }

    #[test]
    fn slots_are_committed_on_demand_across_commit_steps() {
        let per_step = COMMIT_BYTES / SLOT_BYTES;
        let heap = Heap::new(per_step * 2 + 1);
        assert_eq!(heap.kind_bytes, COMMIT_BYTES * 3);
        let mut previous = std::ptr::null_mut::<u8>();
        for index in 0..per_step * 2 + 1 {
            let slot = heap.take_slot(Kind::TestA).unwrap();
            if index > 0 {
                assert_eq!(slot as usize - previous as usize, SLOT_BYTES);
            }
            // Fresh slots are zeroed, writable memory.
            unsafe {
                assert!(std::slice::from_raw_parts(slot, SLOT_BYTES)
                    .iter()
                    .all(|byte| *byte == 0));
                slot.write_bytes(0xff, SLOT_BYTES);
            }
            previous = slot;
        }
        assert_eq!(heap.live(Kind::TestA), per_step * 2 + 1);
        assert!(heap.take_slot(Kind::TestA).is_err());
    }
}
