//! Roc platform host implementation for basic-cli using the new RocOps-based ABI.

use std::ffi::{c_char, c_void};
use std::fs;
use std::io::{self, BufRead, Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};

use crossterm::terminal::{disable_raw_mode, enable_raw_mode};
use roc_std_new::{
    HostedFn, HostedFunctions, RocAlloc, RocCrashed, RocDbg, RocDealloc, RocExpectFailed, RocList,
    RocOps, RocRealloc, RocStr, RocTry,
};

/// Wrapper for single-variant tag unions like [PathErr(IOErr)].
///
/// Example: `[PathErr(IOErr)]` in Roc = `RocSingleTagWrapper<IOErr>` in Rust
///
/// Even though there's only one variant, Roc still includes a discriminant byte.
/// Layout: payload (T) followed by discriminant (u8) + padding to alignment.
#[repr(C)]
pub struct RocSingleTagWrapper<T> {
    pub payload: T,
    pub discriminant: u8, // Always 0 for single-variant tag unions
}

impl<T> RocSingleTagWrapper<T> {
    pub fn new(payload: T) -> Self {
        Self {
            payload,
            discriminant: 0, // Single variant always has discriminant 0
        }
    }
}

/// Global flag to track if dbg or expect_failed was called.
/// If set, program exits with non-zero code to prevent accidental commits.
static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);

// External symbol provided by the compiled Roc application
extern "C" {
    fn roc__main_for_host(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void);
}

/// Roc allocation function with size-tracking metadata.
///
/// We store the allocation size before the user data so we can properly
/// deallocate later (since RocDealloc doesn't provide the size).
extern "C" fn roc_alloc_fn(roc_alloc: *mut RocAlloc, _env: *mut c_void) {
    unsafe {
        let args = &mut *roc_alloc;

        // Sanity check - if length is absurdly large, something is wrong
        if args.length > 1024 * 1024 * 1024 {
            eprintln!("\x1b[31mHost error:\x1b[0m allocation failed - length too large");
            eprintln!("  alignment={}, length={}", args.alignment, args.length);
            std::process::exit(1);
        }

        // Ensure alignment is at least 1 and a power of 2
        let alignment = args.alignment.max(1);
        let min_alignment = alignment.max(std::mem::align_of::<usize>());

        // Ensure min_alignment is a power of 2
        let min_alignment = min_alignment.next_power_of_two();

        // Calculate additional bytes needed to store the size
        let size_storage_bytes = min_alignment;
        let total_size = args.length.saturating_add(size_storage_bytes);

        // Ensure total_size is at least 1
        let total_size = total_size.max(1);

        // Use libc malloc directly for more reliable allocation
        let base_ptr = libc::malloc(total_size) as *mut u8;

        if base_ptr.is_null() {
            eprintln!("\x1b[31mHost error:\x1b[0m allocation failed, out of memory");
            eprintln!(
                "  requested: alignment={}, length={}",
                args.alignment, args.length
            );
            eprintln!(
                "  computed: min_alignment={}, size_storage_bytes={}, total_size={}",
                min_alignment, size_storage_bytes, total_size
            );
            std::process::exit(1);
        }

        // Store the total size right before the user data
        let size_ptr =
            base_ptr.add(size_storage_bytes - std::mem::size_of::<usize>()) as *mut usize;
        *size_ptr = total_size;

        // Also store the alignment for deallocation
        // We use the first usize slot for alignment, second for total_size
        if size_storage_bytes >= 2 * std::mem::size_of::<usize>() {
            let align_ptr = base_ptr as *mut usize;
            *align_ptr = min_alignment;
        }

        // Return pointer to the user data (after the size metadata)
        args.answer = base_ptr.add(size_storage_bytes) as *mut c_void;
    }
}

/// Roc deallocation function with size-tracking metadata.
extern "C" fn roc_dealloc_fn(roc_dealloc: *mut RocDealloc, _env: *mut c_void) {
    unsafe {
        let args = &*roc_dealloc;

        // Use the same alignment calculation as alloc
        let alignment = args.alignment.max(1);
        let min_alignment = alignment
            .max(std::mem::align_of::<usize>())
            .next_power_of_two();
        let size_storage_bytes = min_alignment;

        // Calculate the base pointer (start of actual allocation)
        let base_ptr = (args.ptr as *mut u8).sub(size_storage_bytes);

        // Free the memory using libc
        libc::free(base_ptr as *mut c_void);
    }
}

/// Roc reallocation function with size-tracking metadata.
extern "C" fn roc_realloc_fn(roc_realloc: *mut RocRealloc, _env: *mut c_void) {
    unsafe {
        let args = &mut *roc_realloc;

        // Use the same alignment calculation as alloc
        let alignment = args.alignment.max(1);
        let min_alignment = alignment
            .max(std::mem::align_of::<usize>())
            .next_power_of_two();
        let size_storage_bytes = min_alignment;

        // Get old allocation info
        let old_base_ptr = (args.answer as *mut u8).sub(size_storage_bytes);

        // Calculate new total size
        let new_total_size = args.new_length.saturating_add(size_storage_bytes).max(1);

        // Use libc realloc
        let new_base_ptr = libc::realloc(old_base_ptr as *mut c_void, new_total_size) as *mut u8;

        if new_base_ptr.is_null() {
            eprintln!("\x1b[31mHost error:\x1b[0m reallocation failed, out of memory");
            std::process::exit(1);
        }

        // Store the new total size in metadata
        let new_size_ptr =
            new_base_ptr.add(size_storage_bytes - std::mem::size_of::<usize>()) as *mut usize;
        *new_size_ptr = new_total_size;

        // Return pointer to the user data
        args.answer = new_base_ptr.add(size_storage_bytes) as *mut c_void;
    }
}

/// Roc debug function - called when Roc code uses `dbg`.
extern "C" fn roc_dbg_fn(roc_dbg: *const RocDbg, _env: *mut c_void) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    unsafe {
        let args = &*roc_dbg;
        let message = std::slice::from_raw_parts(args.utf8_bytes, args.len);
        let message = std::str::from_utf8_unchecked(message);
        eprintln!("\x1b[33mdbg:\x1b[0m {}", message);
    }
}

/// Roc expect failed function - called when an `expect` statement fails.
extern "C" fn roc_expect_failed_fn(roc_expect: *const RocExpectFailed, _env: *mut c_void) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    unsafe {
        let args = &*roc_expect;
        let message = std::slice::from_raw_parts(args.utf8_bytes, args.len);
        let message = std::str::from_utf8_unchecked(message).trim();
        eprintln!("\x1b[33mexpect failed:\x1b[0m {}", message);
    }
}

/// Roc crashed function - called when the Roc program crashes.
extern "C" fn roc_crashed_fn(roc_crashed: *const RocCrashed, _env: *mut c_void) {
    unsafe {
        let args = &*roc_crashed;
        let message = std::slice::from_raw_parts(args.utf8_bytes, args.len);
        let message = std::str::from_utf8_unchecked(message);
        eprintln!("\n\x1b[31mRoc crashed:\x1b[0m {}", message);
        std::process::exit(1);
    }
}

// ============================================================================
// Cmd Module Types and Functions
// ============================================================================

/// Output record: { stderr_utf8_lossy : Str, stdout_utf8 : Str }
/// Memory layout: Both RocLists are 24 bytes, alphabetical: stderr_utf8_lossy, stdout_utf8
// #[repr(C)]
// pub struct OutputFromHostSuccess {
//     pub stderr_utf8_lossy: RocList<u8>, // offset 0 (24 bytes)
//     pub stdout_utf8: RocList<u8>,       // offset 24 (24 bytes)
// }

// /// Output record: { exit_code : I32, stderr_utf8_lossy : List(U8), stdout_utf8_lossy : List(U8) }
// /// Memory layout: RocList (24 bytes) > I32 (4 bytes), so: stderr_utf8_lossy, stdout_utf8_lossy, exit_code
// #[repr(C)]
// pub struct OutputFromHostFailure {
//     pub stderr_utf8_lossy: RocList<u8>, // offset 0 (24 bytes)
//     pub stdout_utf8_lossy: RocList<u8>, // offset 24 (24 bytes)
//     pub exit_code: i32,            // offset 48 (4 bytes + padding)
// }

// /// Error type for command_exec_output!: [CmdErr(IOErr), NonZeroExit({ exit_code, stderr, stdout })]
// /// Alphabetically: CmdErr=0, NonZeroExit=1
// #[repr(C)]
// pub union CmdOutputErrPayload {
//     cmd_err: core::mem::ManuallyDrop<roc_io_error::IOErr>,
//     non_zero_exit: core::mem::ManuallyDrop<NonZeroExitPayload>,
// }

// #[repr(C)]
// pub struct CmdOutputErr {
//     payload: CmdOutputErrPayload,
//     discriminant: u8, // CmdErr=0, NonZeroExit=1
// }

// impl CmdOutputErr {
//     pub fn cmd_err(io_err: roc_io_error::IOErr) -> Self {
//         Self {
//             payload: CmdOutputErrPayload {
//                 cmd_err: core::mem::ManuallyDrop::new(io_err),
//             },
//             discriminant: 0,
//         }
//     }

//     pub fn non_zero_exit(
//         stderr_utf8_lossy: RocStr,
//         stdout_utf8_lossy: RocStr,
//         exit_code: i32,
//     ) -> Self {
//         Self {
//             payload: CmdOutputErrPayload {
//                 non_zero_exit: core::mem::ManuallyDrop::new(NonZeroExitPayload {
//                     stderr_utf8_lossy,
//                     stdout_utf8_lossy,
//                     exit_code,
//                 }),
//             },
//             discriminant: 1,
//         }
//     }
// }

/// Type alias for Try({ stderr, stdout }, [CmdErr(IOErr), NonZeroExit(...)]) - using official RocTry
//type TryCmdOutputResult = RocTry<CmdOutputSuccess, CmdOutputErr>;

// ============================================================================
// Hosted Functions (sorted alphabetically by fully-qualified name)
// ============================================================================

/// Hosted function: Cmd.exec_exit_code! (index 0)
/// Takes Command, returns Try(I32, IOErr)
extern "C" fn hosted_cmd_host_exec_exit_code(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let cmd = unsafe { &*(args_ptr as *const roc_command::Command) };

    let exec_try = match roc_command::command_exec_exit_code(cmd, roc_ops) {
        Ok(code) => RocTry::ok(code),
        Err(io_err) => RocTry::err(io_err),
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut RocTry<i32, roc_io_error::IOErr>, exec_try);
    }
}

/// Hosted function: Cmd.exec_output! (index 1)
/// Takes Command, returns Try({ stderr_utf8_lossy, stdout_utf8 }, [CmdErr(IOErr), NonZeroExit(...)])
// extern "C" fn hosted_cmd_exec_output(
//     ops: *const RocOps,
//     ret_ptr: *mut c_void,
//     args_ptr: *mut c_void,
// ) {
//     let roc_ops = unsafe { &*ops };
//     let cmd = unsafe { &*(args_ptr as *const roc_command::Command) };

//     let result = roc_command::command_exec_output(cmd, roc_ops);

//     unsafe {
//         std::ptr::write(ret_ptr as *mut TryCmdOutputResult, result);
//     }
// }

/// Hosted function: Dir.create! (index 2)
/// Takes Str, returns Try({}, [DirErr(IOErr)])
extern "C" fn hosted_dir_create(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        fs::create_dir((*path).as_str())
    };
    let try_result: TryUnitDirErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitDirErr, try_result);
    }
}

/// Hosted function: Dir.create_all! (index 1)
/// Takes Str, returns Try({}, [DirErr(IOErr)])
extern "C" fn hosted_dir_create_all(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        fs::create_dir_all((*path).as_str())
    };
    let try_result: TryUnitDirErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitDirErr, try_result);
    }
}

/// Hosted function: Dir.delete_all! (index 2)
/// Takes Str, returns Try({}, [DirErr(IOErr)])
extern "C" fn hosted_dir_delete_all(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        fs::remove_dir_all((*path).as_str())
    };
    let try_result: TryUnitDirErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitDirErr, try_result);
    }
}

/// Hosted function: Dir.delete_empty! (index 3)
/// Takes Str, returns Try({}, [DirErr(IOErr)])
extern "C" fn hosted_dir_delete_empty(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        fs::remove_dir((*path).as_str())
    };
    let try_result: TryUnitDirErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitDirErr, try_result);
    }
}

/// Hosted function: Dir.list! (index 4)
/// Takes Str, returns Try(List(Str), [DirErr(IOErr)])
extern "C" fn hosted_dir_list(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let path = unsafe {
        let args = args_ptr as *const RocStr;
        (*args).as_str().to_string()
    };

    let result = fs::read_dir(&path);
    let try_result: TryListStrDirErr = match result {
        Ok(rd) => {
            let entries: Vec<String> = rd
                .filter_map(|entry| entry.ok().map(|e| e.path().to_string_lossy().into_owned()))
                .collect();
            let mut list = RocList::with_capacity(entries.len(), roc_ops);
            for entry in entries {
                let roc_str = RocStr::from_str(&entry, roc_ops);
                list.push(roc_str, roc_ops);
            }
            RocTry::ok(list)
        }
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut TryListStrDirErr, try_result);
    }
}

/// Zero-payload single-variant tag union.
/// Used for [CwdUnavailable], [ExePathUnavailable], etc.
/// Layout is just a u8 discriminant (always 0).
#[repr(C)]
pub struct ZeroPayloadTag {
    pub discriminant: u8,
}

impl ZeroPayloadTag {
    pub fn new() -> Self {
        Self { discriminant: 0 }
    }
}

/// Type alias for [VarNotFound(Str)] = RocSingleTagWrapper<RocStr>
type VarNotFoundErr = RocSingleTagWrapper<RocStr>;
type TryStrVarNotFound = RocTry<RocStr, VarNotFoundErr>;
type TryStrCwdUnavailable = RocTry<RocStr, ZeroPayloadTag>;
type TryStrExePathUnavailable = RocTry<RocStr, ZeroPayloadTag>;

/// Hosted function: Env.cwd!
/// Takes {}, returns Try(Str, [CwdUnavailable])
extern "C" fn hosted_env_cwd(ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let try_result: TryStrCwdUnavailable = match std::env::current_dir() {
        Ok(path) => {
            let roc_str = RocStr::from_str(&path.to_string_lossy(), roc_ops);
            RocTry::ok(roc_str)
        }
        Err(_) => RocTry::err(ZeroPayloadTag::new()),
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrCwdUnavailable, try_result);
    }
}

/// Hosted function: Env.exe_path!
/// Takes {}, returns Try(Str, [ExePathUnavailable])
extern "C" fn hosted_env_exe_path(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let try_result: TryStrExePathUnavailable = match std::env::current_exe() {
        Ok(path) => {
            let roc_str = RocStr::from_str(&path.to_string_lossy(), roc_ops);
            RocTry::ok(roc_str)
        }
        Err(_) => RocTry::err(ZeroPayloadTag::new()),
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrExePathUnavailable, try_result);
    }
}

/// Hosted function: Env.var!
/// Takes Str, returns Try(Str, [VarNotFound(Str)])
extern "C" fn hosted_env_var(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let name = unsafe {
        let args = args_ptr as *const RocStr;
        (*args).as_str().to_string()
    };
    let try_result: TryStrVarNotFound = match std::env::var(&name) {
        Ok(value) => {
            let roc_str = RocStr::from_str(&value, roc_ops);
            RocTry::ok(roc_str)
        }
        Err(_) => {
            let roc_name = RocStr::from_str(&name, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(roc_name))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrVarNotFound, try_result);
    }
}

/// Hosted function: File.delete! (index 8)
/// Takes Str (path), returns Try({}, [FileErr(IOErr)])
extern "C" fn hosted_file_delete(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let path = unsafe {
        let args = args_ptr as *const RocStr;
        (*args).as_str()
    };
    let result = fs::remove_file(path);
    let try_result: TryUnitFileErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitFileErr, try_result);
    }
}

/// Hosted function: File.read_bytes! (index 9)
/// Takes Str (path), returns Try(List(U8), [FileErr(IOErr)])
extern "C" fn hosted_file_read_bytes(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let path = unsafe {
        let args = args_ptr as *const RocStr;
        (*args).as_str()
    };
    let result = fs::read(path);
    let try_result: TryBytesFileErr = match result {
        Ok(bytes) => {
            let mut list = RocList::with_capacity(bytes.len(), roc_ops);
            for byte in bytes {
                list.push(byte, roc_ops);
            }
            RocTry::ok(list)
        }
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryBytesFileErr, try_result);
    }
}

/// Hosted function: File.read_utf8! (index 10)
/// Takes Str (path), returns Try(Str, [FileErr(IOErr)])
extern "C" fn hosted_file_read_utf8(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let path = unsafe {
        let args = args_ptr as *const RocStr;
        (*args).as_str()
    };
    let result = fs::read_to_string(path);
    let try_result: TryStrFileErr = match result {
        Ok(content) => {
            let roc_str = RocStr::from_str(&content, roc_ops);
            RocTry::ok(roc_str)
        }
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrFileErr, try_result);
    }
}

/// Hosted function: File.write_bytes! (index 11)
/// Takes (Str, List(U8)), returns Try({}, [FileErr(IOErr)])
extern "C" fn hosted_file_write_bytes(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        // Args are (Str, List(U8)) - a tuple/record
        let args = args_ptr as *const (RocStr, RocList<u8>);
        let (path, bytes) = &*args;
        fs::write(path.as_str(), bytes.as_slice())
    };
    let try_result: TryUnitFileErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitFileErr, try_result);
    }
}

/// Hosted function: File.write_utf8! (index 12)
/// Takes (Str, Str), returns Try({}, [FileErr(IOErr)])
extern "C" fn hosted_file_write_utf8(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        // Args are (Str, Str) - a tuple
        let args = args_ptr as *const (RocStr, RocStr);
        let (path, content) = &*args;
        fs::write(path.as_str(), content.as_str())
    };
    let try_result: TryUnitFileErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitFileErr, try_result);
    }
}

/// Type alias for the Path error type: [PathErr(IOErr)] in Roc
type PathErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try(Bool, [PathErr(IOErr)]) - used by Path.is_file!, etc.
type TryBoolPathErr = RocTry<bool, PathErr>;

/// Type alias for the File error type: [FileErr(IOErr)] in Roc
type FileErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try({}, [FileErr(IOErr)]) - used by File.write_*, File.delete!
type TryUnitFileErr = RocTry<(), FileErr>;

/// Type alias for Try(Str, [FileErr(IOErr)]) - used by File.read_utf8!
type TryStrFileErr = RocTry<RocStr, FileErr>;

/// Type alias for Try(List(U8), [FileErr(IOErr)]) - used by File.read_bytes!
type TryBytesFileErr = RocTry<RocList<u8>, FileErr>;

/// Type alias for the Dir error type: [DirErr(IOErr)] in Roc
type DirErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try({}, [DirErr(IOErr)]) - used by Dir.create!, etc.
type TryUnitDirErr = RocTry<(), DirErr>;

/// Type alias for Try(List(Str), [DirErr(IOErr)]) - used by Dir.list!
type TryListStrDirErr = RocTry<RocList<RocStr>, DirErr>;

/// Write a Try(Bool, [PathErr(IOErr)]) result to ret_ptr using RocTry
unsafe fn write_try_bool_result(
    ret_ptr: *mut c_void,
    result: std::io::Result<bool>,
    roc_ops: &RocOps,
) {
    let try_result: TryBoolPathErr = match result {
        Ok(value) => RocTry::ok(value),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };

    std::ptr::write(ret_ptr as *mut TryBoolPathErr, try_result);
}

#[cfg(target_os = "macos")]
fn locale_from_env() -> Option<String> {
    for key in ["LC_ALL", "LC_CTYPE", "LANG"] {
        if let Ok(value) = std::env::var(key) {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                continue;
            }
            let locale = trimmed
                .split('.')
                .next()
                .unwrap_or(trimmed)
                .split('@')
                .next()
                .unwrap_or(trimmed)
                .trim();
            if !locale.is_empty() {
                return Some(locale.to_string());
            }
        }
    }

    None
}

/// Hosted function: Locale.all!
/// Takes {}, returns List(Str)
#[cfg(target_os = "macos")]
extern "C" fn hosted_locale_all(ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let locales = locale_from_env().unwrap_or_else(|| "en-US".to_string());
    let mut list = RocList::with_capacity(1, roc_ops);
    list.push(RocStr::from_str(&locales, roc_ops), roc_ops);
    unsafe {
        *(ret_ptr as *mut RocList<RocStr>) = list;
    }
}

/// Hosted function: Locale.all!
/// Takes {}, returns List(Str)
#[cfg(not(target_os = "macos"))]
extern "C" fn hosted_locale_all(ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let locales = sys_locale::get_locales().collect::<Vec<_>>();
    let mut list = RocList::with_capacity(locales.len(), roc_ops);
    for locale in locales {
        let roc_str = RocStr::from_str(&locale, roc_ops);
        list.push(roc_str, roc_ops);
    }
    unsafe {
        *(ret_ptr as *mut RocList<RocStr>) = list;
    }
}

type TryStrNotAvailable = RocTry<RocStr, ZeroPayloadTag>;

/// Hosted function: Locale.get!
/// Takes {}, returns Try(Str, [NotAvailable])
#[cfg(target_os = "macos")]
extern "C" fn hosted_locale_get(ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let try_result: TryStrNotAvailable = match locale_from_env() {
        Some(locale) => RocTry::ok(RocStr::from_str(&locale, roc_ops)),
        None => RocTry::err(ZeroPayloadTag::new()),
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrNotAvailable, try_result);
    }
}

/// Hosted function: Locale.get!
/// Takes {}, returns Try(Str, [NotAvailable])
#[cfg(not(target_os = "macos"))]
extern "C" fn hosted_locale_get(ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let try_result: TryStrNotAvailable = match sys_locale::get_locale() {
        Some(locale) => RocTry::ok(RocStr::from_str(&locale, roc_ops)),
        None => RocTry::err(ZeroPayloadTag::new()),
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrNotAvailable, try_result);
    }
}

/// Hosted function: Path.is_dir! (index 13)
/// Takes Str, returns Try(Bool, [PathErr(IOErr)])
extern "C" fn hosted_path_is_dir(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        let path_str = (*path).as_str();
        std::path::Path::new(path_str)
            .symlink_metadata()
            .map(|m| m.is_dir())
    };

    unsafe {
        write_try_bool_result(ret_ptr, result, roc_ops);
    }
}

/// Hosted function: Path.is_file! (index 14)
/// Takes Str, returns Try(Bool, [PathErr(IOErr)])
extern "C" fn hosted_path_is_file(ops: *const RocOps, ret_ptr: *mut c_void, args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        let path_str = (*path).as_str();
        std::path::Path::new(path_str)
            .symlink_metadata()
            .map(|m| m.is_file())
    };

    unsafe {
        write_try_bool_result(ret_ptr, result, roc_ops);
    }
}

/// Hosted function: Path.is_sym_link! (index 15)
/// Takes Str, returns Try(Bool, [PathErr(IOErr)])
extern "C" fn hosted_path_is_sym_link(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let path = args_ptr as *const RocStr;
        let path_str = (*path).as_str();
        std::path::Path::new(path_str)
            .symlink_metadata()
            .map(|m| m.is_symlink())
    };

    unsafe {
        write_try_bool_result(ret_ptr, result, roc_ops);
    }
}

// ============================================================================
// Random Module Types and Functions
// ============================================================================

/// Type alias for the Random error type: [RandomErr(IOErr)] in Roc
type RandomErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try(U32, [RandomErr(IOErr)]) - using official RocTry
type TryU32RandomErr = RocTry<u32, RandomErr>;

/// Type alias for Try(U64, [RandomErr(IOErr)]) - using official RocTry
type TryU64RandomErr = RocTry<u64, RandomErr>;

/// Hosted function: Random.seed_u32!
/// Takes {}, returns Try(U32, [RandomErr(IOErr)])
extern "C" fn hosted_random_seed_u32(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = roc_random::random_u32(roc_ops);

    let try_result: TryU32RandomErr = match result {
        Ok(value) => RocTry::ok(value),
        Err(io_err) => RocTry::err(RocSingleTagWrapper::new(io_err)),
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut TryU32RandomErr, try_result);
    }
}

/// Hosted function: Random.seed_u64!
/// Takes {}, returns Try(U64, [RandomErr(IOErr)])
extern "C" fn hosted_random_seed_u64(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = roc_random::random_u64(roc_ops);

    let try_result: TryU64RandomErr = match result {
        Ok(value) => RocTry::ok(value),
        Err(io_err) => RocTry::err(RocSingleTagWrapper::new(io_err)),
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut TryU64RandomErr, try_result);
    }
}

/// Hosted function: Sleep.millis!
/// Takes U64, returns {}
extern "C" fn hosted_sleep_millis(
    _ops: *const RocOps,
    _ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let millis = unsafe { *(args_ptr as *const u64) };
    std::thread::sleep(std::time::Duration::from_millis(millis));
}

/// Type alias for the Stdout error type: [StdoutErr(IOErr)] in Roc
type StdoutErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try({}, [StdoutErr(IOErr)])
type TryUnitStdoutErr = RocTry<(), StdoutErr>;

/// Type alias for the Stderr error type: [StderrErr(IOErr)] in Roc
type StderrErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try({}, [StderrErr(IOErr)])
type TryUnitStderrErr = RocTry<(), StderrErr>;

/// Hosted function: Stderr.line!
/// Takes Str, returns Try({}, [StderrErr(IOErr)])
extern "C" fn hosted_stderr_line(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let args = args_ptr as *const RocStr;
        let message = (*args).as_str();
        writeln!(io::stderr(), "{}", message)
    };
    let try_result: TryUnitStderrErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitStderrErr, try_result);
    }
}

/// Hosted function: Stderr.write!
/// Takes Str, returns Try({}, [StderrErr(IOErr)])
extern "C" fn hosted_stderr_write(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let args = args_ptr as *const RocStr;
        let message = (*args).as_str();
        write!(io::stderr(), "{}", message).and_then(|()| io::stderr().flush())
    };
    let try_result: TryUnitStderrErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitStderrErr, try_result);
    }
}

/// Hosted function: Stderr.write_bytes!
/// Takes List(U8), returns Try({}, [StderrErr(IOErr)])
extern "C" fn hosted_stderr_write_bytes(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let args = args_ptr as *const RocList<u8>;
        let bytes = (*args).as_slice();
        io::stderr().write_all(bytes).and_then(|()| io::stderr().flush())
    };
    let try_result: TryUnitStderrErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitStderrErr, try_result);
    }
}

/// Error type for Stdin.line!: [EndOfFile, StdinErr(IOErr)]
/// Alphabetically: EndOfFile=0, StdinErr=1
/// EndOfFile has no payload, StdinErr has IOErr payload.
/// The union must be sized for the largest variant (StdinErr with IOErr).
#[repr(C)]
pub union StdinLineErrPayload {
    end_of_file: (),
    stdin_err: core::mem::ManuallyDrop<roc_io_error::IOErr>,
}

#[repr(C)]
pub struct StdinLineErr {
    payload: StdinLineErrPayload,
    discriminant: u8, // EndOfFile=0, StdinErr=1
}

impl StdinLineErr {
    pub fn end_of_file() -> Self {
        Self {
            payload: StdinLineErrPayload { end_of_file: () },
            discriminant: 0,
        }
    }

    pub fn stdin_err(io_err: roc_io_error::IOErr) -> Self {
        Self {
            payload: StdinLineErrPayload {
                stdin_err: core::mem::ManuallyDrop::new(io_err),
            },
            discriminant: 1,
        }
    }
}

/// Type alias for Try(Str, [EndOfFile, StdinErr(IOErr)])
type TryStrStdinLineErr = RocTry<RocStr, StdinLineErr>;

/// Hosted function: Stdin.line!
/// Takes {}, returns Try(Str, [EndOfFile, StdinErr(IOErr)])
extern "C" fn hosted_stdin_line(ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    let roc_ops = unsafe { &*ops };
    let mut line = String::new();
    let result = io::stdin().lock().read_line(&mut line);

    let try_result: TryStrStdinLineErr = match result {
        Ok(0) => {
            // EOF - no data read
            RocTry::err(StdinLineErr::end_of_file())
        }
        Ok(_) => {
            // Success - trim trailing newline
            let roc_str = RocStr::from_str(line.trim_end_matches('\n'), roc_ops);
            RocTry::ok(roc_str)
        }
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(StdinLineErr::stdin_err(io_err))
        }
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut TryStrStdinLineErr, try_result);
    }
}

/// Type alias for [StdinErr(IOErr)] - single variant tag union
type StdinErr = RocSingleTagWrapper<roc_io_error::IOErr>;

/// Type alias for Try(List(U8), [EndOfFile, StdinErr(IOErr)]) - same error type as line!
type TryBytesStdinLineErr = RocTry<RocList<u8>, StdinLineErr>;

/// Type alias for Try(List(U8), [StdinErr(IOErr)])
type TryBytesStdinErr = RocTry<RocList<u8>, StdinErr>;

/// Hosted function: Stdin.bytes!
/// Takes {}, returns Try(List(U8), [EndOfFile, StdinErr(IOErr)])
extern "C" fn hosted_stdin_bytes(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let mut buf = vec![0u8; 16384]; // 16 KiB buffer
    let result = io::stdin().lock().read(&mut buf);

    let try_result: TryBytesStdinLineErr = match result {
        Ok(0) => {
            // EOF
            RocTry::err(StdinLineErr::end_of_file())
        }
        Ok(n) => {
            buf.truncate(n);
            let mut list = RocList::with_capacity(n, roc_ops);
            for byte in &buf[..n] {
                list.push(*byte, roc_ops);
            }
            RocTry::ok(list)
        }
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(StdinLineErr::stdin_err(io_err))
        }
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut TryBytesStdinLineErr, try_result);
    }
}

/// Hosted function: Stdin.read_to_end!
/// Takes {}, returns Try(List(U8), [StdinErr(IOErr)])
extern "C" fn hosted_stdin_read_to_end(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let mut buf = Vec::new();
    let result = io::stdin().lock().read_to_end(&mut buf);

    let try_result: TryBytesStdinErr = match result {
        Ok(_) => {
            let mut list = RocList::with_capacity(buf.len(), roc_ops);
            for byte in &buf {
                list.push(*byte, roc_ops);
            }
            RocTry::ok(list)
        }
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };

    unsafe {
        std::ptr::write(ret_ptr as *mut TryBytesStdinErr, try_result);
    }
}

/// Hosted function: Stdout.line!
/// Takes Str, returns Try({}, [StdoutErr(IOErr)])
extern "C" fn hosted_stdout_line(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let args = args_ptr as *const RocStr;
        let message = (*args).as_str();
        writeln!(io::stdout(), "{}", message)
    };
    let try_result: TryUnitStdoutErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitStdoutErr, try_result);
    }
}

/// Hosted function: Stdout.write!
/// Takes Str, returns Try({}, [StdoutErr(IOErr)])
extern "C" fn hosted_stdout_write(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let args = args_ptr as *const RocStr;
        let message = (*args).as_str();
        write!(io::stdout(), "{}", message).and_then(|()| io::stdout().flush())
    };
    let try_result: TryUnitStdoutErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitStdoutErr, try_result);
    }
}

/// Hosted function: Stdout.write_bytes!
/// Takes List(U8), returns Try({}, [StdoutErr(IOErr)])
extern "C" fn hosted_stdout_write_bytes(
    ops: *const RocOps,
    ret_ptr: *mut c_void,
    args_ptr: *mut c_void,
) {
    let roc_ops = unsafe { &*ops };
    let result = unsafe {
        let args = args_ptr as *const RocList<u8>;
        let bytes = (*args).as_slice();
        io::stdout().write_all(bytes).and_then(|()| io::stdout().flush())
    };
    let try_result: TryUnitStdoutErr = match result {
        Ok(()) => RocTry::ok(()),
        Err(e) => {
            let io_err = roc_io_error::IOErr::from_io_error(&e, roc_ops);
            RocTry::err(RocSingleTagWrapper::new(io_err))
        }
    };
    unsafe {
        std::ptr::write(ret_ptr as *mut TryUnitStdoutErr, try_result);
    }
}

/// Hosted function: Tty.disable_raw_mode!
/// Takes {}, returns {}
extern "C" fn hosted_tty_disable_raw_mode(
    _ops: *const RocOps,
    _ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let _ = disable_raw_mode();
}

/// Hosted function: Tty.enable_raw_mode!
/// Takes {}, returns {}
extern "C" fn hosted_tty_enable_raw_mode(
    _ops: *const RocOps,
    _ret_ptr: *mut c_void,
    _args_ptr: *mut c_void,
) {
    let _ = enable_raw_mode();
}

/// Hosted function: Utc.now!
/// Takes {}, returns U128 (nanoseconds since Unix epoch)
extern "C" fn hosted_utc_now(_ops: *const RocOps, ret_ptr: *mut c_void, _args_ptr: *mut c_void) {
    use std::time::{SystemTime, UNIX_EPOCH};

    let since_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time went backwards");
    let nanos: u128 = since_epoch.as_nanos();

    unsafe {
        *(ret_ptr as *mut u128) = nanos;
    }
}

/// Array of hosted function pointers, sorted alphabetically by fully-qualified name.
/// IMPORTANT: Order must match the order Roc expects based on alphabetical sorting.
static HOSTED_FNS: [HostedFn; 34] = [
    hosted_cmd_host_exec_exit_code,    // 0:  Cmd.exec_exit_code!
    //hosted_cmd_exec_output,       // 1:  Cmd.exec_output!
    hosted_dir_create,            // 2:  Dir.create!
    hosted_dir_create_all,        // 3:  Dir.create_all!
    hosted_dir_delete_all,        // 4:  Dir.delete_all!
    hosted_dir_delete_empty,      // 5:  Dir.delete_empty!
    hosted_dir_list,              // 6:  Dir.list!
    hosted_env_cwd,               // 7:  Env.cwd!
    hosted_env_exe_path,          // 8:  Env.exe_path!
    hosted_env_var,               // 9:  Env.var!
    hosted_file_delete,           // 10: File.delete!
    hosted_file_read_bytes,       // 11: File.read_bytes!
    hosted_file_read_utf8,        // 12: File.read_utf8!
    hosted_file_write_bytes,      // 13: File.write_bytes!
    hosted_file_write_utf8,       // 14: File.write_utf8!
    hosted_locale_all,            // 15: Locale.all!
    hosted_locale_get,            // 16: Locale.get!
    hosted_path_is_dir,           // 17: Path.is_dir!
    hosted_path_is_file,          // 18: Path.is_file!
    hosted_path_is_sym_link,      // 19: Path.is_sym_link!
    hosted_random_seed_u32,       // 20: Random.seed_u32!
    hosted_random_seed_u64,       // 21: Random.seed_u64!
    hosted_sleep_millis,          // 22: Sleep.millis!
    hosted_stderr_line,           // 23: Stderr.line!
    hosted_stderr_write,          // 24: Stderr.write!
    hosted_stderr_write_bytes,    // 25: Stderr.write_bytes!
    hosted_stdin_bytes,           // 26: Stdin.bytes!
    hosted_stdin_line,            // 27: Stdin.line!
    hosted_stdin_read_to_end,     // 28: Stdin.read_to_end!
    hosted_stdout_line,           // 29: Stdout.line!
    hosted_stdout_write,          // 30: Stdout.write!
    hosted_stdout_write_bytes,    // 31: Stdout.write_bytes!
    hosted_tty_disable_raw_mode,  // 32: Tty.disable_raw_mode!
    hosted_tty_enable_raw_mode,   // 33: Tty.enable_raw_mode!
    hosted_utc_now,               // 34: Utc.now!
];

/// Build a RocList<RocStr> from command-line arguments.
///
/// Uses argc/argv directly instead of std::env::args() because when built
/// as a static library, the Rust runtime isn't properly initialized.
fn build_args_list(argc: i32, argv: *const *const c_char, roc_ops: &RocOps) -> RocList<RocStr> {
    if argc <= 0 || argv.is_null() {
        return RocList::empty();
    }

    let mut list = RocList::with_capacity(argc as usize, roc_ops);

    for i in 0..argc as isize {
        unsafe {
            let arg_ptr = *argv.offset(i);
            if arg_ptr.is_null() {
                break;
            }
            let c_str = std::ffi::CStr::from_ptr(arg_ptr);
            let arg = c_str.to_string_lossy();
            let roc_str = RocStr::from_str(&arg, roc_ops);
            list.push(roc_str, roc_ops);
        }
    }
    list
}

/// C-compatible main entry point for the Roc program.
/// This is exported so the linker can find it.
#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *const *const c_char) -> i32 {
    rust_main(argc, argv)
}

/// Main entry point for the Roc program.
pub fn rust_main(argc: i32, argv: *const *const c_char) -> i32 {
    // Create the RocOps struct with all callbacks
    // We Box it to ensure stable memory address
    let roc_ops = Box::new(RocOps {
        env: std::ptr::null_mut(),
        roc_alloc: roc_alloc_fn,
        roc_dealloc: roc_dealloc_fn,
        roc_realloc: roc_realloc_fn,
        roc_dbg: roc_dbg_fn,
        roc_expect_failed: roc_expect_failed_fn,
        roc_crashed: roc_crashed_fn,
        hosted_fns: HostedFunctions {
            count: HOSTED_FNS.len() as u32,
            fns: HOSTED_FNS.as_ptr(),
        },
    });

    // Build List(Str) from command-line arguments (using argc/argv directly)
    let args_list = build_args_list(argc, argv, &roc_ops);

    // Call the Roc main function
    let mut exit_code: i32 = -99;
    unsafe {
        roc__main_for_host(
            &*roc_ops,
            &mut exit_code as *mut i32 as *mut c_void,
            &args_list as *const RocList<RocStr> as *mut c_void,
        );
    }

    // If dbg or expect_failed was called, ensure non-zero exit code
    if DEBUG_OR_EXPECT_CALLED.load(Ordering::Acquire) && exit_code == 0 {
        return 1;
    }

    exit_code
}
