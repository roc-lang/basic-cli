//! Native resources whose lifetime follows the Roc box, including Roc-side frees.
//!
//! Glue payload callbacks alone cannot implement this: compiled Roc may perform
//! the final decref without calling a hosted function. Register the allocation
//! base and finalize from both allocator entrypoints instead.
use crate::roc_platform_abi::*;
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::c_void;

struct Finalizer {
    payload: *mut u64,
    drop: unsafe fn(*mut u64),
}

thread_local! {
    // Roc and its existing SQLite resources are confined to the host thread.
    // Background services own Rust data and receive cancellation on destruction.
    static RESOURCES: RefCell<HashMap<usize, Finalizer>> = RefCell::new(HashMap::new());
}

pub fn box_resource<T>(value: T, host: &RocHost) -> *mut u64 {
    let payload = unsafe { allocate_box(size_of::<u64>(), align_of::<u64>(), false, host) } as *mut u64;
    unsafe { payload.write(Box::into_raw(Box::new(value)) as u64) };
    let base = unsafe { payload.cast::<u8>().sub(size_of::<usize>().max(align_of::<u64>())) };
    RESOURCES.with(|resources| {
        let old = resources.borrow_mut().insert(base as usize, Finalizer { payload, drop: drop_resource::<T> });
        assert!(old.is_none(), "resource allocation registered twice");
    });
    payload
}

unsafe fn drop_resource<T>(payload: *mut u64) {
    let raw = unsafe { payload.read() } as *mut T;
    if !raw.is_null() {
        unsafe { payload.write(0); drop(Box::from_raw(raw)); }
    }
}

/// The caller must pass a live handle allocated for T and serialize access.
pub unsafe fn resource_ref<'a, T>(handle: *mut u64) -> &'a mut T {
    unsafe { &mut *(*handle as *mut T) }
}

pub fn release(handle: *mut u64, host: &RocHost) {
    unsafe { decref_box_with(handle.cast(), align_of::<u64>(), false, None, host) };
}

pub extern "C" fn dealloc(host: *mut RocHost, ptr: *mut c_void, alignment: usize) {
    // Remove before dropping: a native destructor can release other resources.
    let finalizer = RESOURCES.with(|resources| resources.borrow_mut().remove(&(ptr as usize)));
    if let Some(finalizer) = finalizer {
        unsafe { (finalizer.drop)(finalizer.payload) };
    }
    DefaultAllocators::roc_dealloc(host, ptr, alignment);
}

pub fn make_host() -> RocHost {
    let mut host = make_roc_host(std::ptr::null_mut());
    host.roc_dealloc = dealloc;
    host
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::rc::Rc;
    use std::cell::Cell;

    struct CountDrop(Rc<Cell<usize>>);
    impl Drop for CountDrop {
        fn drop(&mut self) { self.0.set(self.0.get() + 1); }
    }

    #[test]
    fn final_host_release_destroys_exactly_once() {
        let host = make_host();
        let count = Rc::new(Cell::new(0));
        let handle = box_resource(CountDrop(count.clone()), &host);
        unsafe { incref_box(handle.cast(), 1) };
        release(handle, &host);
        assert_eq!(count.get(), 0);
        release(handle, &host);
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn roc_style_final_free_destroys_payload() {
        let mut host = make_host();
        let count = Rc::new(Cell::new(0));
        let handle = box_resource(CountDrop(count.clone()), &host);
        // Compiled Roc frees the allocation directly after decrementing to zero.
        let base = unsafe { handle.cast::<u8>().sub(size_of::<usize>().max(align_of::<u64>())) };
        dealloc(&mut host, base.cast(), align_of::<u64>());
        assert_eq!(count.get(), 1);
    }

    #[test]
    fn destructor_can_release_another_registered_resource() {
        struct Nested { handle: *mut u64, host: RocHost }
        impl Drop for Nested {
            fn drop(&mut self) { release(self.handle, &self.host); }
        }
        let host = make_host();
        let count = Rc::new(Cell::new(0));
        let inner = box_resource(CountDrop(count.clone()), &host);
        let outer = box_resource(Nested { handle: inner, host: make_host() }, &host);
        release(outer, &host);
        assert_eq!(count.get(), 1);
    }
}
