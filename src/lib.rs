//! Roc platform host implementation for Roc's direct-symbol host ABI.

#![allow(improper_ctypes_definitions)]

use core::mem::ManuallyDrop;
#[cfg(unix)]
use std::ffi::CStr;
use std::ffi::{c_char, c_void, OsStr as StdOsStr, OsString};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};

use crossterm::terminal::{disable_raw_mode, enable_raw_mode};

mod cmd;
mod http;
mod roc_platform_abi;
mod sqlite;
mod tcp;

use crate::roc_platform_abi::*;

// RustGlue assigns numbered names (TryTypeN, IOErrTypeN, ...) to anonymous Roc
// records and result types, and the numbers shift whenever a module is added.
// To stay robust against that renumbering we alias against the *semantic* names
// the generator also emits (e.g. `HostCmdExecExitCodeResult`), which are keyed by
// module + function name and therefore stable. Where our preferred local name is
// identical to a generated semantic name (for example `HostDirListResult`), we
// omit a local alias and rely on the `use crate::roc_platform_abi::*;` glob above.

type DirUnitResult = HostDirCreateResult;
type DirUnitResultPayload = HostDirCreateResultPayload;
type DirUnitResultTag = HostDirCreateResultTag;

type FileBytesResult = HostFileReadBytesResult;
type FileBytesResultPayload = HostFileReadBytesResultPayload;
type FileBytesResultTag = HostFileReadBytesResultTag;
type FileReaderOpenResult = HostFileOpenReaderResult;
type FileReaderOpenResultPayload = HostFileOpenReaderResultPayload;
type FileReaderOpenResultTag = HostFileOpenReaderResultTag;
type FileReaderLineResult = HostFileReadLineResult;
type FileReaderLineResultPayload = HostFileReadLineResultPayload;
type FileReaderLineResultTag = HostFileReadLineResultTag;
type FileStrResult = HostFileReadUtf8Result;
type FileStrResultPayload = HostFileReadUtf8ResultPayload;
type FileStrResultTag = HostFileReadUtf8ResultTag;
type FileSizeResult = HostFileSizeInBytesResult;
type FileSizeResultPayload = HostFileSizeInBytesResultPayload;
type FileSizeResultTag = HostFileSizeInBytesResultTag;
type FileBoolResult = HostFileIsExecutableResult;
type FileBoolResultPayload = HostFileIsExecutableResultPayload;
type FileBoolResultTag = HostFileIsExecutableResultTag;
type FileTimeResult = HostFileTimeAccessedResult;
type FileTimeResultPayload = HostFileTimeAccessedResultPayload;
type FileTimeResultTag = HostFileTimeAccessedResultTag;

type RandomU64Result = HostRandomSeedU64Result;
type RandomU64ResultPayload = HostRandomSeedU64ResultPayload;
type RandomU64ResultTag = HostRandomSeedU64ResultTag;
type RandomU32Result = HostRandomSeedU32Result;
type RandomU32ResultPayload = HostRandomSeedU32ResultPayload;
type RandomU32ResultTag = HostRandomSeedU32ResultTag;

type StderrUnitResult = HostStderrLineResult;
type StderrUnitResultPayload = HostStderrLineResultPayload;
type StderrUnitResultTag = HostStderrLineResultTag;
type StderrBytesResult = HostStderrWriteBytesResult;
type StderrBytesResultPayload = HostStderrWriteBytesResultPayload;
type StderrBytesResultTag = HostStderrWriteBytesResultTag;

type StdinLineReadErr = EndOfFileOrStdinErr;
type StdinLineReadErrPayload = EndOfFileOrStdinErrPayload;
type StdinLineReadErrTag = EndOfFileOrStdinErrTag;
type StdinBytesReadErr = EndOfFileOrStdinErr;
type StdinBytesReadErrPayload = EndOfFileOrStdinErrPayload;
type StdinBytesReadErrTag = EndOfFileOrStdinErrTag;

type StdoutUnitResult = HostStdoutLineResult;
type StdoutUnitResultPayload = HostStdoutLineResultPayload;
type StdoutUnitResultTag = HostStdoutLineResultTag;
type StdoutBytesResult = HostStdoutWriteBytesResult;
type StdoutBytesResultPayload = HostStdoutWriteBytesResultPayload;
type StdoutBytesResultTag = HostStdoutWriteBytesResultTag;

pub(crate) type NativeOsStr = UnixBytesOrUtf8OrWindowsU16s;
type NativeOsStrPayload = UnixBytesOrUtf8OrWindowsU16sPayload;
type NativeOsStrTag = UnixBytesOrUtf8OrWindowsU16sTag;

pub(crate) fn roc_u8_list_from_slice(slice: &[u8], roc_host: &RocHost) -> RocListWith<u8, false> {
    unsafe { RocListWith::<u8, false>::from_slice(slice, roc_host) }
}

#[cfg(windows)]
pub(crate) fn roc_u16_list_from_slice(
    slice: &[u16],
    roc_host: &RocHost,
) -> RocListWith<u16, false> {
    unsafe { RocListWith::<u16, false>::from_slice(slice, roc_host) }
}

extern "C" {
    fn roc_main(args: RocList<OsStr>) -> i32;
}

static DEBUG_OR_EXPECT_CALLED: AtomicBool = AtomicBool::new(false);
static mut ROC_HOST: *mut RocHost = core::ptr::null_mut();

fn set_roc_host(roc_host: *mut RocHost) {
    unsafe {
        ROC_HOST = roc_host;
    }
}

fn roc_host_ptr() -> *mut RocHost {
    unsafe {
        if ROC_HOST.is_null() {
            eprintln!("roc host error: RocHost not initialized");
            std::process::exit(1);
        }
        ROC_HOST
    }
}

pub(crate) fn roc_host() -> &'static RocHost {
    unsafe { &*roc_host_ptr() }
}

macro_rules! define_common_io_err {
    ($from_io:ident, $other:ident, $ty:ident, $tag:ident, $payload:ident) => {
        fn $other(message: &str, roc_host: &RocHost) -> $ty {
            $ty {
                payload: $payload {
                    other: ManuallyDrop::new(RocStr::from_str(message, roc_host)),
                },
                tag: $tag::Other,
            }
        }

        fn $from_io(error: &io::Error, roc_host: &RocHost) -> $ty {
            match error.kind() {
                io::ErrorKind::AlreadyExists => $ty {
                    payload: $payload { already_exists: [] },
                    tag: $tag::AlreadyExists,
                },
                io::ErrorKind::BrokenPipe => $ty {
                    payload: $payload { broken_pipe: [] },
                    tag: $tag::BrokenPipe,
                },
                io::ErrorKind::Interrupted => $ty {
                    payload: $payload { interrupted: [] },
                    tag: $tag::Interrupted,
                },
                io::ErrorKind::IsADirectory => $ty {
                    payload: $payload { is_adirectory: [] },
                    tag: $tag::IsADirectory,
                },
                io::ErrorKind::NotFound => $ty {
                    payload: $payload { not_found: [] },
                    tag: $tag::NotFound,
                },
                io::ErrorKind::NotADirectory => $ty {
                    payload: $payload { not_adirectory: [] },
                    tag: $tag::NotADirectory,
                },
                io::ErrorKind::OutOfMemory => $ty {
                    payload: $payload { out_of_memory: [] },
                    tag: $tag::OutOfMemory,
                },
                io::ErrorKind::PermissionDenied => $ty {
                    payload: $payload {
                        permission_denied: [],
                    },
                    tag: $tag::PermissionDenied,
                },
                io::ErrorKind::Unsupported => $ty {
                    payload: $payload { unsupported: [] },
                    tag: $tag::Unsupported,
                },
                _ => $other(&error.to_string(), roc_host),
            }
        }
    };
}

define_common_io_err!(
    dir_io_err_from_io,
    dir_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    env_io_err_from_io,
    env_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    file_io_err_from_io,
    file_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    path_io_err_from_io,
    path_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    random_io_err_from_io,
    random_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    stderr_io_err_from_io,
    stderr_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    stdin_io_err_from_io,
    stdin_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);
define_common_io_err!(
    stdout_io_err_from_io,
    stdout_io_err_other,
    IOErr,
    IOErrTag,
    IOErrPayload
);

fn try_dir_unit_ok() -> DirUnitResult {
    DirUnitResult {
        payload: DirUnitResultPayload { ok: [] },
        tag: DirUnitResultTag::Ok,
    }
}

fn try_dir_unit_err(error: IOErr) -> DirUnitResult {
    DirUnitResult {
        payload: DirUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: DirUnitResultTag::Err,
    }
}

fn try_dir_list_ok(value: RocList<UnixBytesOrUtf8OrWindowsU16s>) -> HostDirListResult {
    HostDirListResult {
        payload: HostDirListResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostDirListResultTag::Ok,
    }
}

fn try_dir_list_err(error: IOErr) -> HostDirListResult {
    HostDirListResult {
        payload: HostDirListResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostDirListResultTag::Err,
    }
}

fn try_env_var_ok(value: NativeOsStr) -> HostEnvVarResult {
    HostEnvVarResult {
        payload: HostEnvVarResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostEnvVarResultTag::Ok,
    }
}

fn try_env_var_err(error: EnvErrOrVarNotFound) -> HostEnvVarResult {
    HostEnvVarResult {
        payload: HostEnvVarResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostEnvVarResultTag::Err,
    }
}

fn env_var_not_found(name: NativeOsStr) -> EnvErrOrVarNotFound {
    EnvErrOrVarNotFound {
        payload: EnvErrOrVarNotFoundPayload {
            var_not_found: ManuallyDrop::new(name),
        },
        tag: EnvErrOrVarNotFoundTag::VarNotFound,
    }
}

fn env_var_env_err(error: IOErr) -> EnvErrOrVarNotFound {
    EnvErrOrVarNotFound {
        payload: EnvErrOrVarNotFoundPayload {
            env_err: ManuallyDrop::new(error),
        },
        tag: EnvErrOrVarNotFoundTag::EnvErr,
    }
}

fn try_env_cwd_ok(value: UnixBytesOrUtf8OrWindowsU16s) -> HostEnvCwdResult {
    HostEnvCwdResult {
        payload: HostEnvCwdResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostEnvCwdResultTag::Ok,
    }
}

fn try_env_cwd_err() -> HostEnvCwdResult {
    HostEnvCwdResult {
        payload: HostEnvCwdResultPayload { err: [] },
        tag: HostEnvCwdResultTag::Err,
    }
}

fn try_env_exe_path_ok(value: UnixBytesOrUtf8OrWindowsU16s) -> HostEnvExePathResult {
    HostEnvExePathResult {
        payload: HostEnvExePathResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostEnvExePathResultTag::Ok,
    }
}

fn try_env_exe_path_err() -> HostEnvExePathResult {
    HostEnvExePathResult {
        payload: HostEnvExePathResultPayload { err: [] },
        tag: HostEnvExePathResultTag::Err,
    }
}

fn try_env_set_cwd_ok() -> HostEnvSetCwdResult {
    HostEnvSetCwdResult {
        payload: HostEnvSetCwdResultPayload { ok: [] },
        tag: HostEnvSetCwdResultTag::Ok,
    }
}

fn try_env_set_cwd_err(error: IOErr) -> HostEnvSetCwdResult {
    HostEnvSetCwdResult {
        payload: HostEnvSetCwdResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostEnvSetCwdResultTag::Err,
    }
}

#[cfg(not(target_pointer_width = "32"))]
fn env_arch(roc_host: &RocHost) -> AARCH64OrARMOrOTHEROrX64OrX86 {
    let (payload, tag) = match std::env::consts::ARCH {
        "aarch64" => (
            AARCH64OrARMOrOTHEROrX64OrX86Payload { aarch64: [] },
            AARCH64OrARMOrOTHEROrX64OrX86Tag::AARCH64,
        ),
        "arm" => (
            AARCH64OrARMOrOTHEROrX64OrX86Payload { arm: [] },
            AARCH64OrARMOrOTHEROrX64OrX86Tag::ARM,
        ),
        "x86_64" => (
            AARCH64OrARMOrOTHEROrX64OrX86Payload { x64: [] },
            AARCH64OrARMOrOTHEROrX64OrX86Tag::X64,
        ),
        "x86" => (
            AARCH64OrARMOrOTHEROrX64OrX86Payload { x86: [] },
            AARCH64OrARMOrOTHEROrX64OrX86Tag::X86,
        ),
        other => (
            AARCH64OrARMOrOTHEROrX64OrX86Payload {
                other: ManuallyDrop::new(RocStr::from_str(other, roc_host)),
            },
            AARCH64OrARMOrOTHEROrX64OrX86Tag::OTHER,
        ),
    };
    AARCH64OrARMOrOTHEROrX64OrX86 { payload, tag }
}

#[cfg(not(target_pointer_width = "32"))]
fn env_os(roc_host: &RocHost) -> LINUXOrMACOSOrOTHEROrWINDOWS {
    let (payload, tag) = match std::env::consts::OS {
        "linux" => (
            LINUXOrMACOSOrOTHEROrWINDOWSPayload { linux: [] },
            LINUXOrMACOSOrOTHEROrWINDOWSTag::LINUX,
        ),
        "macos" => (
            LINUXOrMACOSOrOTHEROrWINDOWSPayload { macos: [] },
            LINUXOrMACOSOrOTHEROrWINDOWSTag::MACOS,
        ),
        "windows" => (
            LINUXOrMACOSOrOTHEROrWINDOWSPayload { windows: [] },
            LINUXOrMACOSOrOTHEROrWINDOWSTag::WINDOWS,
        ),
        other => (
            LINUXOrMACOSOrOTHEROrWINDOWSPayload {
                other: ManuallyDrop::new(RocStr::from_str(other, roc_host)),
            },
            LINUXOrMACOSOrOTHEROrWINDOWSTag::OTHER,
        ),
    };
    LINUXOrMACOSOrOTHEROrWINDOWS { payload, tag }
}

#[cfg(target_pointer_width = "32")]
fn env_arch(roc_host: &RocHost) -> AARCH64OrARMOrOTHEROrX64OrX86 {
    let (tag, other) = match std::env::consts::ARCH {
        "aarch64" => (AARCH64OrARMOrOTHEROrX64OrX86Tag::AARCH64, None),
        "arm" => (AARCH64OrARMOrOTHEROrX64OrX86Tag::ARM, None),
        "x86_64" => (AARCH64OrARMOrOTHEROrX64OrX86Tag::X64, None),
        "x86" => (AARCH64OrARMOrOTHEROrX64OrX86Tag::X86, None),
        value => (AARCH64OrARMOrOTHEROrX64OrX86Tag::OTHER, Some(value)),
    };
    let mut result = AARCH64OrARMOrOTHEROrX64OrX86 {
        _payload_alignment: [],
        payload: [0; 12],
        tag,
    };
    if let Some(value) = other {
        unsafe {
            core::ptr::write(
                result.payload.as_mut_ptr().cast::<RocStr>(),
                RocStr::from_str(value, roc_host),
            );
        }
    }
    result
}

#[cfg(target_pointer_width = "32")]
fn env_os(roc_host: &RocHost) -> LINUXOrMACOSOrOTHEROrWINDOWS {
    let (tag, other) = match std::env::consts::OS {
        "linux" => (LINUXOrMACOSOrOTHEROrWINDOWSTag::LINUX, None),
        "macos" => (LINUXOrMACOSOrOTHEROrWINDOWSTag::MACOS, None),
        "windows" => (LINUXOrMACOSOrOTHEROrWINDOWSTag::WINDOWS, None),
        value => (LINUXOrMACOSOrOTHEROrWINDOWSTag::OTHER, Some(value)),
    };
    let mut result = LINUXOrMACOSOrOTHEROrWINDOWS {
        _payload_alignment: [],
        payload: [0; 12],
        tag,
    };
    if let Some(value) = other {
        unsafe {
            core::ptr::write(
                result.payload.as_mut_ptr().cast::<RocStr>(),
                RocStr::from_str(value, roc_host),
            );
        }
    }
    result
}

fn try_file_bytes_ok(value: RocListWith<u8, false>) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileBytesResultTag::Ok,
    }
}

fn try_file_bytes_err(error: IOErr) -> FileBytesResult {
    FileBytesResult {
        payload: FileBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileBytesResultTag::Err,
    }
}

fn try_file_reader_ok(handle: *mut u64) -> FileReaderOpenResult {
    FileReaderOpenResult {
        payload: FileReaderOpenResultPayload {
            ok: ManuallyDrop::new(handle),
        },
        tag: FileReaderOpenResultTag::Ok,
    }
}

fn try_file_reader_err(error: IOErr) -> FileReaderOpenResult {
    FileReaderOpenResult {
        payload: FileReaderOpenResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileReaderOpenResultTag::Err,
    }
}

fn try_file_reader_line_ok(value: RocListWith<u8, false>) -> FileReaderLineResult {
    FileReaderLineResult {
        payload: FileReaderLineResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileReaderLineResultTag::Ok,
    }
}

fn try_file_reader_line_err(error: IOErr) -> FileReaderLineResult {
    FileReaderLineResult {
        payload: FileReaderLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileReaderLineResultTag::Err,
    }
}

fn try_file_write_bytes_ok() -> HostFileWriteBytesResult {
    HostFileWriteBytesResult {
        payload: HostFileWriteBytesResultPayload { ok: [] },
        tag: HostFileWriteBytesResultTag::Ok,
    }
}

fn try_file_write_bytes_err(error: IOErr) -> HostFileWriteBytesResult {
    HostFileWriteBytesResult {
        payload: HostFileWriteBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostFileWriteBytesResultTag::Err,
    }
}

fn try_file_str_ok(value: RocStr) -> FileStrResult {
    FileStrResult {
        payload: FileStrResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileStrResultTag::Ok,
    }
}

fn try_file_str_err(error: IOErr) -> FileStrResult {
    FileStrResult {
        payload: FileStrResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileStrResultTag::Err,
    }
}

fn try_file_write_utf8_ok() -> HostFileWriteUtf8Result {
    HostFileWriteUtf8Result {
        payload: HostFileWriteUtf8ResultPayload { ok: [] },
        tag: HostFileWriteUtf8ResultTag::Ok,
    }
}

fn try_file_write_utf8_err(error: IOErr) -> HostFileWriteUtf8Result {
    HostFileWriteUtf8Result {
        payload: HostFileWriteUtf8ResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostFileWriteUtf8ResultTag::Err,
    }
}

fn try_file_delete_ok() -> HostFileDeleteResult {
    HostFileDeleteResult {
        payload: HostFileDeleteResultPayload { ok: [] },
        tag: HostFileDeleteResultTag::Ok,
    }
}

fn try_file_delete_err(error: IOErr) -> HostFileDeleteResult {
    HostFileDeleteResult {
        payload: HostFileDeleteResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostFileDeleteResultTag::Err,
    }
}

fn try_file_size_ok(value: u64) -> FileSizeResult {
    FileSizeResult {
        payload: FileSizeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileSizeResultTag::Ok,
    }
}

fn try_file_size_err(error: IOErr) -> FileSizeResult {
    FileSizeResult {
        payload: FileSizeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileSizeResultTag::Err,
    }
}

fn try_file_bool_ok(value: bool) -> FileBoolResult {
    FileBoolResult {
        payload: FileBoolResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileBoolResultTag::Ok,
    }
}

fn try_file_bool_err(error: IOErr) -> FileBoolResult {
    FileBoolResult {
        payload: FileBoolResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileBoolResultTag::Err,
    }
}

fn try_file_time_ok(value: u128) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: FileTimeResultTag::Ok,
    }
}

fn try_file_time_err(error: IOErr) -> FileTimeResult {
    FileTimeResult {
        payload: FileTimeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: FileTimeResultTag::Err,
    }
}

fn try_utc_now_ok(nanos: u128) -> HostUtcNowResult {
    HostUtcNowResult {
        payload: HostUtcNowResultPayload {
            ok: ManuallyDrop::new(nanos),
        },
        tag: HostUtcNowResultTag::Ok,
    }
}

fn try_utc_now_err() -> HostUtcNowResult {
    HostUtcNowResult {
        payload: HostUtcNowResultPayload { err: [] },
        tag: HostUtcNowResultTag::Err,
    }
}

fn try_locale_get_ok(value: RocStr) -> HostLocaleGetResult {
    HostLocaleGetResult {
        payload: HostLocaleGetResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostLocaleGetResultTag::Ok,
    }
}

fn try_path_type_ok(value: PathType) -> HostPathTypeResult {
    HostPathTypeResult {
        payload: HostPathTypeResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostPathTypeResultTag::Ok,
    }
}

fn try_path_type_err(error: IOErr) -> HostPathTypeResult {
    HostPathTypeResult {
        payload: HostPathTypeResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostPathTypeResultTag::Err,
    }
}

type PathType = HostPathTypeOk;

fn path_type_from_metadata(metadata: &fs::Metadata) -> PathType {
    let file_type = metadata.file_type();

    if file_type.is_symlink() {
        return PathType::SymLink;
    }

    // A Windows reparse point that Rust does not identify as a symbolic link
    // is not necessarily a regular file or directory (for example, a junction).
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;

        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        if metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
            return PathType::Other;
        }
    }

    if file_type.is_dir() {
        PathType::Dir
    } else if file_type.is_file() {
        PathType::File
    } else {
        PathType::Other
    }
}

fn try_random_u64_ok(value: u64) -> RandomU64Result {
    RandomU64Result {
        payload: RandomU64ResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: RandomU64ResultTag::Ok,
    }
}

fn try_random_u64_err(error: IOErr) -> RandomU64Result {
    RandomU64Result {
        payload: RandomU64ResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: RandomU64ResultTag::Err,
    }
}

fn try_random_u32_ok(value: u32) -> RandomU32Result {
    RandomU32Result {
        payload: RandomU32ResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: RandomU32ResultTag::Ok,
    }
}

fn try_random_u32_err(error: IOErr) -> RandomU32Result {
    RandomU32Result {
        payload: RandomU32ResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: RandomU32ResultTag::Err,
    }
}

fn try_stderr_unit_ok() -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload { ok: [] },
        tag: StderrUnitResultTag::Ok,
    }
}

fn try_stderr_unit_err(error: IOErr) -> StderrUnitResult {
    StderrUnitResult {
        payload: StderrUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrUnitResultTag::Err,
    }
}

fn try_stderr_bytes_ok() -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload { ok: [] },
        tag: StderrBytesResultTag::Ok,
    }
}

fn try_stderr_bytes_err(error: IOErr) -> StderrBytesResult {
    StderrBytesResult {
        payload: StderrBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StderrBytesResultTag::Err,
    }
}

fn stdin_line_eof_or_err_eof() -> StdinLineReadErr {
    StdinLineReadErr {
        payload: StdinLineReadErrPayload { end_of_file: [] },
        tag: StdinLineReadErrTag::EndOfFile,
    }
}

fn stdin_line_eof_or_err_io(error: IOErr) -> StdinLineReadErr {
    StdinLineReadErr {
        payload: StdinLineReadErrPayload {
            stdin_err: ManuallyDrop::new(error),
        },
        tag: StdinLineReadErrTag::StdinErr,
    }
}

fn stdin_bytes_eof_or_err_eof() -> StdinBytesReadErr {
    StdinBytesReadErr {
        payload: StdinBytesReadErrPayload { end_of_file: [] },
        tag: StdinBytesReadErrTag::EndOfFile,
    }
}

fn stdin_bytes_eof_or_err_io(error: IOErr) -> StdinBytesReadErr {
    StdinBytesReadErr {
        payload: StdinBytesReadErrPayload {
            stdin_err: ManuallyDrop::new(error),
        },
        tag: StdinBytesReadErrTag::StdinErr,
    }
}

fn try_stdin_line_ok(value: RocStr) -> HostStdinLineResult {
    HostStdinLineResult {
        payload: HostStdinLineResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostStdinLineResultTag::Ok,
    }
}

fn try_stdin_line_err(error: StdinLineReadErr) -> HostStdinLineResult {
    HostStdinLineResult {
        payload: HostStdinLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostStdinLineResultTag::Err,
    }
}

fn try_stdin_bytes_ok(value: RocListWith<u8, false>) -> HostStdinBytesResult {
    HostStdinBytesResult {
        payload: HostStdinBytesResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostStdinBytesResultTag::Ok,
    }
}

fn try_stdin_bytes_err(error: StdinBytesReadErr) -> HostStdinBytesResult {
    HostStdinBytesResult {
        payload: HostStdinBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostStdinBytesResultTag::Err,
    }
}

fn try_stdin_read_to_end_ok(value: RocListWith<u8, false>) -> HostStdinReadToEndResult {
    HostStdinReadToEndResult {
        payload: HostStdinReadToEndResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: HostStdinReadToEndResultTag::Ok,
    }
}

fn try_stdin_read_to_end_err(error: IOErr) -> HostStdinReadToEndResult {
    HostStdinReadToEndResult {
        payload: HostStdinReadToEndResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostStdinReadToEndResultTag::Err,
    }
}

fn try_stdout_unit_ok() -> StdoutUnitResult {
    StdoutUnitResult {
        payload: StdoutUnitResultPayload { ok: [] },
        tag: StdoutUnitResultTag::Ok,
    }
}

fn try_stdout_unit_err(error: IOErr) -> StdoutUnitResult {
    StdoutUnitResult {
        payload: StdoutUnitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StdoutUnitResultTag::Err,
    }
}

fn try_stdout_bytes_ok() -> StdoutBytesResult {
    StdoutBytesResult {
        payload: StdoutBytesResultPayload { ok: [] },
        tag: StdoutBytesResultTag::Ok,
    }
}

fn try_stdout_bytes_err(error: IOErr) -> StdoutBytesResult {
    StdoutBytesResult {
        payload: StdoutBytesResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: StdoutBytesResultTag::Err,
    }
}

fn unsupported_native_variant(expected: &str, got: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::Unsupported,
        format!("expected {expected} native value on this platform, got {got}"),
    )
}

fn path_from_native(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
) -> io::Result<std::path::PathBuf> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        match path.tag {
            UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes => unsafe {
                let bytes = ManuallyDrop::into_inner(path.payload.unix_bytes);
                let path_buf =
                    std::path::PathBuf::from(std::ffi::OsStr::from_bytes(bytes.as_slice()));
                bytes.decref(roc_host);
                Ok(path_buf)
            },
            UnixBytesOrUtf8OrWindowsU16sTag::Utf8 => unsafe {
                let text = ManuallyDrop::into_inner(path.payload.utf8);
                let path_buf =
                    std::path::PathBuf::from(std::ffi::OsStr::from_bytes(text.as_str().as_bytes()));
                text.decref(roc_host);
                Ok(path_buf)
            },
            UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s => unsafe {
                let u16s = ManuallyDrop::into_inner(path.payload.windows_u16s);
                u16s.decref(roc_host);
                Err(unsupported_native_variant("UnixBytes", "WindowsU16s"))
            },
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStringExt;

        match path.tag {
            UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes => unsafe {
                let bytes = ManuallyDrop::into_inner(path.payload.unix_bytes);
                bytes.decref(roc_host);
                Err(unsupported_native_variant("WindowsU16s", "UnixBytes"))
            },
            UnixBytesOrUtf8OrWindowsU16sTag::Utf8 => unsafe {
                let text = ManuallyDrop::into_inner(path.payload.utf8);
                let path_buf = std::path::PathBuf::from(OsString::from(text.as_str()));
                text.decref(roc_host);
                Ok(path_buf)
            },
            UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s => unsafe {
                let u16s = ManuallyDrop::into_inner(path.payload.windows_u16s);
                let path_buf = std::path::PathBuf::from(OsString::from_wide(u16s.as_slice()));
                u16s.decref(roc_host);
                Ok(path_buf)
            },
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        decref_unix_bytes_or_utf8or_windows_u16s(path, roc_host);
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "native paths are not implemented on this platform",
        ))
    }
}

pub(crate) fn os_string_from_native(
    os_str: NativeOsStr,
    roc_host: &RocHost,
) -> io::Result<OsString> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;

        match os_str.tag {
            NativeOsStrTag::UnixBytes => unsafe {
                let bytes = ManuallyDrop::into_inner(os_str.payload.unix_bytes);
                let value = OsString::from_vec(bytes.as_slice().to_vec());
                bytes.decref(roc_host);
                Ok(value)
            },
            NativeOsStrTag::Utf8 => unsafe {
                let text = ManuallyDrop::into_inner(os_str.payload.utf8);
                let value = OsString::from_vec(text.as_str().as_bytes().to_vec());
                text.decref(roc_host);
                Ok(value)
            },
            NativeOsStrTag::WindowsU16s => unsafe {
                let u16s = ManuallyDrop::into_inner(os_str.payload.windows_u16s);
                u16s.decref(roc_host);
                Err(unsupported_native_variant("UnixBytes", "WindowsU16s"))
            },
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStringExt;

        match os_str.tag {
            NativeOsStrTag::UnixBytes => unsafe {
                let bytes = ManuallyDrop::into_inner(os_str.payload.unix_bytes);
                bytes.decref(roc_host);
                Err(unsupported_native_variant("WindowsU16s", "UnixBytes"))
            },
            NativeOsStrTag::Utf8 => unsafe {
                let text = ManuallyDrop::into_inner(os_str.payload.utf8);
                let value = OsString::from(text.as_str());
                text.decref(roc_host);
                Ok(value)
            },
            NativeOsStrTag::WindowsU16s => unsafe {
                let u16s = ManuallyDrop::into_inner(os_str.payload.windows_u16s);
                let value = OsString::from_wide(u16s.as_slice());
                u16s.decref(roc_host);
                Ok(value)
            },
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        decref_unix_bytes_or_utf8or_windows_u16s_type6(os_str, roc_host);
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "native OS strings are not implemented on this platform",
        ))
    }
}

fn native_os_str_from_os_str(value: &StdOsStr, roc_host: &RocHost) -> NativeOsStr {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        NativeOsStr {
            payload: NativeOsStrPayload {
                unix_bytes: ManuallyDrop::new(roc_u8_list_from_slice(value.as_bytes(), roc_host)),
            },
            tag: NativeOsStrTag::UnixBytes,
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let units: Vec<u16> = value.encode_wide().collect();
        NativeOsStr {
            payload: NativeOsStrPayload {
                windows_u16s: ManuallyDrop::new(roc_u16_list_from_slice(&units, roc_host)),
            },
            tag: NativeOsStrTag::WindowsU16s,
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        let _ = value;
        NativeOsStr {
            payload: NativeOsStrPayload {
                utf8: ManuallyDrop::new(RocStr::empty()),
            },
            tag: NativeOsStrTag::Utf8,
        }
    }
}

fn validate_env_key(key: &StdOsStr) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        let bytes = key.as_bytes();
        if bytes.is_empty() || bytes.contains(&0) || bytes.contains(&b'=') {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "environment variable names cannot be empty or contain nul bytes or '='",
            ));
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let units: Vec<u16> = key.encode_wide().collect();
        if units.is_empty() || units.contains(&0) || units.contains(&(b'=' as u16)) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "environment variable names cannot be empty or contain nul code units or '='",
            ));
        }
    }

    Ok(())
}

fn native_path_from_path(
    path: &std::path::Path,
    roc_host: &RocHost,
) -> UnixBytesOrUtf8OrWindowsU16s {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;

        UnixBytesOrUtf8OrWindowsU16s {
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                unix_bytes: ManuallyDrop::new(roc_u8_list_from_slice(
                    path.as_os_str().as_bytes(),
                    roc_host,
                )),
            },
            tag: UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes,
        }
    }

    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;

        let units: Vec<u16> = path.as_os_str().encode_wide().collect();
        UnixBytesOrUtf8OrWindowsU16s {
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                windows_u16s: ManuallyDrop::new(roc_u16_list_from_slice(&units, roc_host)),
            },
            tag: UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s,
        }
    }

    #[cfg(not(any(unix, windows)))]
    {
        UnixBytesOrUtf8OrWindowsU16s {
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                unix_bytes: ManuallyDrop::new(RocListWith::<u8, false>::empty()),
            },
            tag: UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes,
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_create(path: UnixBytesOrUtf8OrWindowsU16s) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    };
    match fs::create_dir(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_create_all(path: UnixBytesOrUtf8OrWindowsU16s) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    };
    match fs::create_dir_all(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_delete_all(path: UnixBytesOrUtf8OrWindowsU16s) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    };
    match fs::remove_dir_all(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_delete_empty(path: UnixBytesOrUtf8OrWindowsU16s) -> DirUnitResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    };
    match fs::remove_dir(path) {
        Ok(()) => try_dir_unit_ok(),
        Err(error) => try_dir_unit_err(dir_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_dir_list(path: UnixBytesOrUtf8OrWindowsU16s) -> HostDirListResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_dir_list_err(dir_io_err_from_io(&error, roc_host)),
    };
    match fs::read_dir(&path) {
        Ok(read_dir) => {
            let entries: Vec<std::path::PathBuf> = read_dir
                .filter_map(|entry| entry.ok().map(|entry| entry.path()))
                .collect();
            let list = unsafe {
                RocList::<UnixBytesOrUtf8OrWindowsU16s>::allocate(entries.len(), roc_host)
            };
            for (index, entry) in entries.iter().enumerate() {
                unsafe {
                    list.elements
                        .add(index)
                        .write(native_path_from_path(entry.as_path(), roc_host));
                }
            }
            try_dir_list_ok(list)
        }
        Err(error) => try_dir_list_err(dir_io_err_from_io(
            &normalize_dir_list_err(&path, error),
            roc_host,
        )),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_cwd() -> HostEnvCwdResult {
    let roc_host = roc_host();
    match std::env::current_dir() {
        Ok(path) => try_env_cwd_ok(native_path_from_path(path.as_path(), roc_host)),
        Err(_) => try_env_cwd_err(),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_exe_path() -> HostEnvExePathResult {
    let roc_host = roc_host();
    match std::env::current_exe() {
        Ok(path) => try_env_exe_path_ok(native_path_from_path(path.as_path(), roc_host)),
        Err(_) => try_env_exe_path_err(),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_temp_dir() -> UnixBytesOrUtf8OrWindowsU16s {
    let roc_host = roc_host();
    native_path_from_path(std::env::temp_dir().as_path(), roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_env_var(name: NativeOsStr) -> HostEnvVarResult {
    let roc_host = roc_host();
    let key = match os_string_from_native(name, roc_host) {
        Ok(key) => key,
        Err(error) => {
            return try_env_var_err(env_var_env_err(env_io_err_from_io(&error, roc_host)));
        }
    };

    if let Err(error) = validate_env_key(key.as_os_str()) {
        return try_env_var_err(env_var_env_err(env_io_err_from_io(&error, roc_host)));
    }

    match std::env::var_os(&key) {
        Some(value) => try_env_var_ok(native_os_str_from_os_str(value.as_os_str(), roc_host)),
        None => try_env_var_err(env_var_not_found(native_os_str_from_os_str(
            key.as_os_str(),
            roc_host,
        ))),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_platform() -> HostEnvPlatform {
    let roc_host = roc_host();
    HostEnvPlatform {
        arch: env_arch(roc_host),
        os: env_os(roc_host),
    }
}

#[no_mangle]
pub extern "C" fn hosted_env_dict() -> RocList<HostEnvDict> {
    let roc_host = roc_host();
    let vars: Vec<(OsString, OsString)> = std::env::vars_os().collect();
    let list = unsafe { RocList::<HostEnvDict>::allocate(vars.len(), roc_host) };

    for (index, (name, value)) in vars.iter().enumerate() {
        unsafe {
            list.elements.add(index).write(HostEnvDict {
                _0: native_os_str_from_os_str(name.as_os_str(), roc_host),
                _1: native_os_str_from_os_str(value.as_os_str(), roc_host),
            });
        }
    }

    list
}

#[no_mangle]
pub extern "C" fn hosted_env_set_cwd(path: UnixBytesOrUtf8OrWindowsU16s) -> HostEnvSetCwdResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_env_set_cwd_err(env_io_err_from_io(&error, roc_host)),
    };

    match std::env::set_current_dir(path) {
        Ok(()) => try_env_set_cwd_ok(),
        Err(error) => try_env_set_cwd_err(env_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_delete(path: UnixBytesOrUtf8OrWindowsU16s) -> HostFileDeleteResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    };
    match fs::remove_file(path) {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_hard_link(
    original: UnixBytesOrUtf8OrWindowsU16s,
    link: UnixBytesOrUtf8OrWindowsU16s,
) -> HostFileHardLinkResult {
    let roc_host = roc_host();
    let original_path = match path_from_native(original, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    };
    let link_path = match path_from_native(link, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    };

    match fs::hard_link(original_path, link_path) {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_rename(
    from: UnixBytesOrUtf8OrWindowsU16s,
    to: UnixBytesOrUtf8OrWindowsU16s,
) -> HostFileRenameResult {
    let roc_host = roc_host();
    let from_path = match path_from_native(from, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    };
    let to_path = match path_from_native(to, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    };

    match fs::rename(from_path, to_path) {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_bytes(path: UnixBytesOrUtf8OrWindowsU16s) -> FileBytesResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_bytes_err(file_io_err_from_io(&error, roc_host)),
    };
    match fs::read(&path) {
        Ok(bytes) => try_file_bytes_ok(roc_u8_list_from_slice(&bytes, roc_host)),
        Err(error) => try_file_bytes_err(file_io_err_from_io(
            &normalize_file_kind_err(&path, error),
            roc_host,
        )),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_utf8(path: UnixBytesOrUtf8OrWindowsU16s) -> FileStrResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_str_err(file_io_err_from_io(&error, roc_host)),
    };
    match fs::read_to_string(&path) {
        Ok(content) => try_file_str_ok(RocStr::from_str(&content, roc_host)),
        Err(error) => try_file_str_err(file_io_err_from_io(
            &normalize_file_kind_err(&path, error),
            roc_host,
        )),
    }
}

// ============================================================================
// Buffered file readers
//
// The `Host.FileReader` backing `File.Reader` is represented by the generated
// glue as `*mut u64`: a boxed u64 holding a raw `*mut BufReader<fs::File>`. The box is refcounted
// with `allocate_box`/`decref_box_with`; closing the file happens in
// `drop_file_reader` when the last reference is released.
// ----------------------------------------------------------------------------

const FILE_READER_BOX_ALIGN: usize = core::mem::align_of::<u64>();

fn box_file_reader(reader: BufReader<fs::File>, roc_host: &RocHost) -> *mut u64 {
    let raw: *mut BufReader<fs::File> = Box::into_raw(Box::new(reader));
    let boxed = unsafe {
        allocate_box(
            core::mem::size_of::<u64>(),
            FILE_READER_BOX_ALIGN,
            false,
            roc_host,
        )
    };
    unsafe {
        *(boxed as *mut u64) = raw as u64;
    }
    boxed as *mut u64
}

unsafe fn file_reader_ref<'a>(handle: *mut u64) -> &'a mut BufReader<fs::File> {
    &mut *(*handle as *mut BufReader<fs::File>)
}

extern "C" fn drop_file_reader(data_ptr: *mut c_void, _roc_host: *mut RocHost) {
    unsafe {
        let raw = *(data_ptr as *mut u64) as *mut BufReader<fs::File>;
        if !raw.is_null() {
            drop(Box::from_raw(raw));
        }
    }
}

fn release_file_reader(handle: *mut u64, roc_host: &RocHost) {
    unsafe {
        decref_box_with(
            handle as RocBox,
            FILE_READER_BOX_ALIGN,
            false,
            Some(drop_file_reader),
            roc_host,
        )
    };
}

#[no_mangle]
pub extern "C" fn hosted_file_open_reader(
    path: UnixBytesOrUtf8OrWindowsU16s,
    capacity: u64,
) -> FileReaderOpenResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_file_reader_err(file_io_err_from_io(&error, roc_host)),
    };
    match fs::File::open(&path) {
        Ok(file) => {
            let reader = if capacity == 0 {
                BufReader::new(file)
            } else {
                BufReader::with_capacity(capacity as usize, file)
            };
            try_file_reader_ok(box_file_reader(reader, roc_host))
        }
        Err(error) => try_file_reader_err(file_io_err_from_io(
            &normalize_file_kind_err(&path, error),
            roc_host,
        )),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_read_line(handle: *mut u64) -> FileReaderLineResult {
    let roc_host = roc_host();
    let result = {
        let reader = unsafe { file_reader_ref(handle) };
        let mut buffer = Vec::new();
        match reader.read_until(b'\n', &mut buffer) {
            Ok(_) => try_file_reader_line_ok(roc_u8_list_from_slice(&buffer, roc_host)),
            Err(error) => try_file_reader_line_err(file_io_err_from_io(&error, roc_host)),
        }
    };
    release_file_reader(handle, roc_host);
    result
}

fn file_metadata(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
) -> io::Result<fs::Metadata> {
    fs::metadata(path_from_native(path, roc_host)?)
}

// Windows reports ERROR_ACCESS_DENIED when a directory is opened for
// file-style reads/writes, where Unix reports EISDIR; remap so the typed
// IOErr is portable. If the metadata probe races a concurrent delete, the
// original error passes through unchanged.
#[cfg(windows)]
fn normalize_file_kind_err(path: &std::path::Path, error: io::Error) -> io::Error {
    if error.kind() == io::ErrorKind::PermissionDenied {
        if let Ok(metadata) = fs::metadata(path) {
            if metadata.is_dir() {
                return io::ErrorKind::IsADirectory.into();
            }
        }
    }
    error
}

#[cfg(not(windows))]
fn normalize_file_kind_err(_path: &std::path::Path, error: io::Error) -> io::Error {
    error
}

// Windows lists a directory via FindFirstFileW(path\*), whose error codes for
// non-directory paths don't always decode to NotADirectory like Unix's ENOTDIR.
#[cfg(windows)]
fn normalize_dir_list_err(path: &std::path::Path, error: io::Error) -> io::Error {
    if error.kind() != io::ErrorKind::NotADirectory {
        if let Ok(metadata) = fs::metadata(path) {
            if !metadata.is_dir() {
                return io::ErrorKind::NotADirectory.into();
            }
        }
    }
    error
}

#[cfg(not(windows))]
fn normalize_dir_list_err(_path: &std::path::Path, error: io::Error) -> io::Error {
    error
}

#[no_mangle]
pub extern "C" fn hosted_file_size_in_bytes(path: UnixBytesOrUtf8OrWindowsU16s) -> FileSizeResult {
    let roc_host = roc_host();
    match file_metadata(path, roc_host) {
        Ok(metadata) => try_file_size_ok(metadata.len()),
        Err(error) => try_file_size_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[cfg(not(any(unix, windows)))]
fn unsupported_file_permission_error() -> io::Error {
    io::Error::new(
        io::ErrorKind::Unsupported,
        "file permission checks are not implemented on this platform",
    )
}

#[cfg(unix)]
fn file_permission_bit(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
    bit: u32,
) -> io::Result<bool> {
    use std::os::unix::fs::PermissionsExt;

    let metadata = file_metadata(path, roc_host)?;
    Ok(metadata.permissions().mode() & bit != 0)
}

fn file_is_executable(path: UnixBytesOrUtf8OrWindowsU16s, roc_host: &RocHost) -> io::Result<bool> {
    #[cfg(unix)]
    {
        file_permission_bit(path, roc_host, 0o111)
    }

    #[cfg(windows)]
    {
        // Windows has no executable permission bit; approximate with the
        // conventional executable extensions the shell would run.
        let path = path_from_native(path, roc_host)?;
        fs::metadata(&path)?;
        Ok(path
            .extension()
            .and_then(StdOsStr::to_str)
            .is_some_and(|extension| {
                ["exe", "bat", "cmd", "com"]
                    .iter()
                    .any(|candidate| extension.eq_ignore_ascii_case(candidate))
            }))
    }

    #[cfg(not(any(unix, windows)))]
    {
        let _ = path_from_native(path, roc_host);
        Err(unsupported_file_permission_error())
    }
}

fn file_is_readable(path: UnixBytesOrUtf8OrWindowsU16s, roc_host: &RocHost) -> io::Result<bool> {
    #[cfg(unix)]
    {
        file_permission_bit(path, roc_host, 0o400)
    }

    #[cfg(windows)]
    {
        // Windows has no read permission bit outside ACLs; anything statable
        // is considered readable.
        file_metadata(path, roc_host)?;
        Ok(true)
    }

    #[cfg(not(any(unix, windows)))]
    {
        let _ = path_from_native(path, roc_host);
        Err(unsupported_file_permission_error())
    }
}

fn file_is_writable(path: UnixBytesOrUtf8OrWindowsU16s, roc_host: &RocHost) -> io::Result<bool> {
    #[cfg(unix)]
    {
        file_permission_bit(path, roc_host, 0o200)
    }

    #[cfg(windows)]
    {
        Ok(!file_metadata(path, roc_host)?.permissions().readonly())
    }

    #[cfg(not(any(unix, windows)))]
    {
        let _ = path_from_native(path, roc_host);
        Err(unsupported_file_permission_error())
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_executable(path: UnixBytesOrUtf8OrWindowsU16s) -> FileBoolResult {
    let roc_host = roc_host();
    match file_is_executable(path, roc_host) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_readable(path: UnixBytesOrUtf8OrWindowsU16s) -> FileBoolResult {
    let roc_host = roc_host();
    match file_is_readable(path, roc_host) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_is_writable(path: UnixBytesOrUtf8OrWindowsU16s) -> FileBoolResult {
    let roc_host = roc_host();
    match file_is_writable(path, roc_host) {
        Ok(value) => try_file_bool_ok(value),
        Err(error) => try_file_bool_err(file_io_err_from_io(&error, roc_host)),
    }
}

fn nanos_since_epoch(time: std::time::SystemTime) -> io::Result<u128> {
    time.duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .map_err(|error| io::Error::new(io::ErrorKind::Other, error.to_string()))
}

fn file_time(
    path: UnixBytesOrUtf8OrWindowsU16s,
    roc_host: &RocHost,
    read_time: fn(&fs::Metadata) -> io::Result<std::time::SystemTime>,
) -> io::Result<u128> {
    let metadata = file_metadata(path, roc_host)?;
    read_time(&metadata).and_then(nanos_since_epoch)
}

#[no_mangle]
pub extern "C" fn hosted_file_time_accessed(path: UnixBytesOrUtf8OrWindowsU16s) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::accessed) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_created(path: UnixBytesOrUtf8OrWindowsU16s) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::created) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_time_modified(path: UnixBytesOrUtf8OrWindowsU16s) -> FileTimeResult {
    let roc_host = roc_host();
    match file_time(path, roc_host, fs::Metadata::modified) {
        Ok(value) => try_file_time_ok(value),
        Err(error) => try_file_time_err(file_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_write_bytes(
    path: UnixBytesOrUtf8OrWindowsU16s,
    bytes: RocListWith<u8, false>,
) -> HostFileWriteBytesResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => {
            unsafe { bytes.decref(roc_host) };
            return try_file_write_bytes_err(file_io_err_from_io(&error, roc_host));
        }
    };
    let result = fs::write(&path, bytes.as_slice());
    unsafe { bytes.decref(roc_host) };

    match result {
        Ok(()) => try_file_write_bytes_ok(),
        Err(error) => try_file_write_bytes_err(file_io_err_from_io(
            &normalize_file_kind_err(&path, error),
            roc_host,
        )),
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_write_utf8(
    path: UnixBytesOrUtf8OrWindowsU16s,
    content: RocStr,
) -> HostFileWriteUtf8Result {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => {
            unsafe { content.decref(roc_host) };
            return try_file_write_utf8_err(file_io_err_from_io(&error, roc_host));
        }
    };
    let content_string = content.as_str().to_owned();
    unsafe { content.decref(roc_host) };

    match fs::write(&path, content_string) {
        Ok(()) => try_file_write_utf8_ok(),
        Err(error) => try_file_write_utf8_err(file_io_err_from_io(
            &normalize_file_kind_err(&path, error),
            roc_host,
        )),
    }
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

#[cfg(target_os = "macos")]
fn locale_get_string() -> String {
    locale_from_env().unwrap_or_else(|| "en-US".to_string())
}

#[cfg(not(target_os = "macos"))]
fn locale_get_string() -> String {
    sys_locale::get_locale().unwrap_or_else(|| "en-US".to_string())
}

#[cfg(target_os = "macos")]
fn locale_all_strings() -> Vec<String> {
    vec![locale_get_string()]
}

#[cfg(not(target_os = "macos"))]
fn locale_all_strings() -> Vec<String> {
    let locales = sys_locale::get_locales().collect::<Vec<_>>();
    if locales.is_empty() {
        vec![locale_get_string()]
    } else {
        locales
    }
}

#[no_mangle]
pub extern "C" fn hosted_locale_all() -> RocList<RocStr> {
    let roc_host = roc_host();
    let locales = locale_all_strings();
    let list = unsafe { RocList::<RocStr>::allocate(locales.len(), roc_host) };

    for (index, locale) in locales.iter().enumerate() {
        unsafe {
            list.elements
                .add(index)
                .write(RocStr::from_str(locale, roc_host));
        }
    }

    list
}

#[no_mangle]
pub extern "C" fn hosted_locale_get() -> HostLocaleGetResult {
    let roc_host = roc_host();
    try_locale_get_ok(RocStr::from_str(&locale_get_string(), roc_host))
}

#[no_mangle]
pub extern "C" fn hosted_path_type(path: UnixBytesOrUtf8OrWindowsU16s) -> HostPathTypeResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return try_path_type_err(path_io_err_from_io(&error, roc_host)),
    };

    match path.symlink_metadata() {
        Ok(metadata) => try_path_type_ok(path_type_from_metadata(&metadata)),
        Err(error) => try_path_type_err(path_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_random_seed_u32() -> RandomU32Result {
    let roc_host = roc_host();
    let mut bytes = [0u8; 4];
    match getrandom::getrandom(&mut bytes) {
        Ok(()) => try_random_u32_ok(u32::from_ne_bytes(bytes)),
        Err(error) => {
            let io_error = io::Error::new(io::ErrorKind::Other, error.to_string());
            try_random_u32_err(random_io_err_from_io(&io_error, roc_host))
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_random_seed_u64() -> RandomU64Result {
    let roc_host = roc_host();
    let mut bytes = [0u8; 8];
    match getrandom::getrandom(&mut bytes) {
        Ok(()) => try_random_u64_ok(u64::from_ne_bytes(bytes)),
        Err(error) => {
            let io_error = io::Error::new(io::ErrorKind::Other, error.to_string());
            try_random_u64_err(random_io_err_from_io(&io_error, roc_host))
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_sleep_millis(millis: u64) {
    std::thread::sleep(std::time::Duration::from_millis(millis));
}

#[no_mangle]
pub extern "C" fn hosted_stderr_line(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        writeln!(stderr, "{}", message.as_str())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write(message: RocStr) -> StderrUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        write!(stderr, "{}", message.as_str()).and_then(|()| stderr.flush())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stderr_unit_ok(),
        Err(error) => try_stderr_unit_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stderr_write_bytes(bytes: RocListWith<u8, false>) -> StderrBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stderr = io::stderr().lock();
        stderr
            .write_all(bytes.as_slice())
            .and_then(|()| stderr.flush())
    };
    unsafe { bytes.decref(roc_host) };

    match result {
        Ok(()) => try_stderr_bytes_ok(),
        Err(error) => try_stderr_bytes_err(stderr_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdin_line() -> HostStdinLineResult {
    let roc_host = roc_host();
    let mut line = String::new();
    match io::stdin().lock().read_line(&mut line) {
        Ok(0) => try_stdin_line_err(stdin_line_eof_or_err_eof()),
        Ok(_) => {
            let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
            try_stdin_line_ok(RocStr::from_str(trimmed, roc_host))
        }
        Err(error) => try_stdin_line_err(stdin_line_eof_or_err_io(stdin_io_err_from_io(
            &error, roc_host,
        ))),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdin_bytes() -> HostStdinBytesResult {
    let roc_host = roc_host();
    let mut buffer = [0u8; 16_384];
    match io::stdin().lock().read(&mut buffer) {
        Ok(0) => try_stdin_bytes_err(stdin_bytes_eof_or_err_eof()),
        Ok(bytes_read) => {
            try_stdin_bytes_ok(roc_u8_list_from_slice(&buffer[..bytes_read], roc_host))
        }
        Err(error) => try_stdin_bytes_err(stdin_bytes_eof_or_err_io(stdin_io_err_from_io(
            &error, roc_host,
        ))),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdin_read_to_end() -> HostStdinReadToEndResult {
    let roc_host = roc_host();
    let mut buffer = Vec::new();
    match io::stdin().lock().read_to_end(&mut buffer) {
        Ok(_) => try_stdin_read_to_end_ok(roc_u8_list_from_slice(&buffer, roc_host)),
        Err(error) => try_stdin_read_to_end_err(stdin_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_line(message: RocStr) -> StdoutUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        writeln!(stdout, "{}", message.as_str())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(stdout_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write(message: RocStr) -> StdoutUnitResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        write!(stdout, "{}", message.as_str()).and_then(|()| stdout.flush())
    };
    unsafe { message.decref(roc_host) };

    match result {
        Ok(()) => try_stdout_unit_ok(),
        Err(error) => try_stdout_unit_err(stdout_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_stdout_write_bytes(bytes: RocListWith<u8, false>) -> StdoutBytesResult {
    let roc_host = roc_host();
    let result = {
        let mut stdout = io::stdout().lock();
        stdout
            .write_all(bytes.as_slice())
            .and_then(|()| stdout.flush())
    };
    unsafe { bytes.decref(roc_host) };

    match result {
        Ok(()) => try_stdout_bytes_ok(),
        Err(error) => try_stdout_bytes_err(stdout_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_tty_disable_raw_mode() {
    let _ = disable_raw_mode();
}

#[no_mangle]
pub extern "C" fn hosted_tty_enable_raw_mode() {
    let _ = enable_raw_mode();
}

// TODO(https://github.com/roc-lang/roc/issues/10163): revert to a bare u128
// return once the compiler emits the clang/Rust u128 return convention on
// x86_64-windows; bare u128 returns are currently misread there.
#[no_mangle]
pub extern "C" fn hosted_utc_now() -> HostUtcNowResult {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(duration) => try_utc_now_ok(duration.as_nanos()),
        Err(_) => try_utc_now_err(),
    }
}

#[no_mangle]
pub extern "C" fn roc_alloc(length: usize, alignment: usize) -> *mut c_void {
    DefaultAllocators::roc_alloc(roc_host_ptr(), length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dealloc(ptr: *mut c_void, alignment: usize) {
    DefaultAllocators::roc_dealloc(roc_host_ptr(), ptr, alignment);
}

#[no_mangle]
pub extern "C" fn roc_realloc(
    ptr: *mut c_void,
    new_length: usize,
    alignment: usize,
) -> *mut c_void {
    DefaultAllocators::roc_realloc(roc_host_ptr(), ptr, new_length, alignment)
}

#[no_mangle]
pub extern "C" fn roc_dbg(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_dbg(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_expect_failed(bytes: *const u8, len: usize) {
    DEBUG_OR_EXPECT_CALLED.store(true, Ordering::Release);
    DefaultHandlers::roc_expect_failed(roc_host_ptr(), bytes, len);
}

#[no_mangle]
pub extern "C" fn roc_crashed(bytes: *const u8, len: usize) {
    DefaultHandlers::roc_crashed(roc_host_ptr(), bytes, len);
}

#[cfg(unix)]
fn build_args_list(argc: i32, argv: *const *const c_char, roc_host: &RocHost) -> RocList<OsStr> {
    if argc <= 0 || argv.is_null() {
        return RocList::empty();
    }

    let list = unsafe { RocList::<OsStr>::allocate(argc as usize, roc_host) };
    for index in 0..argc as isize {
        unsafe {
            let arg_ptr = *argv.offset(index);
            if arg_ptr.is_null() {
                break;
            }
            let arg = CStr::from_ptr(arg_ptr).to_bytes();
            list.elements.offset(index).write(OsStr {
                payload: OsStrPayload {
                    unix_bytes: ManuallyDrop::new(roc_u8_list_from_slice(arg, roc_host)),
                },
                tag: OsStrTag::UnixBytes,
            });
        }
    }
    list
}

#[cfg(windows)]
fn build_args_list(_argc: i32, _argv: *const *const c_char, roc_host: &RocHost) -> RocList<OsStr> {
    use std::os::windows::ffi::OsStrExt;

    let args = std::env::args_os().collect::<Vec<_>>();
    let list = unsafe { RocList::<OsStr>::allocate(args.len(), roc_host) };
    for (index, arg) in args.iter().enumerate() {
        let units = arg.encode_wide().collect::<Vec<_>>();
        unsafe {
            list.elements.add(index).write(OsStr {
                payload: OsStrPayload {
                    windows_u16s: ManuallyDrop::new(roc_u16_list_from_slice(&units, roc_host)),
                },
                tag: OsStrTag::WindowsU16s,
            });
        }
    }
    list
}

#[cfg(not(any(unix, windows)))]
fn build_args_list(_argc: i32, _argv: *const *const c_char, _roc_host: &RocHost) -> RocList<OsStr> {
    RocList::empty()
}

#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *const *const c_char) -> i32 {
    rust_main(argc, argv)
}

pub fn rust_main(argc: i32, argv: *const *const c_char) -> i32 {
    let mut roc_host = make_roc_host(core::ptr::null_mut());
    set_roc_host(&mut roc_host);

    let args_list = build_args_list(argc, argv, &roc_host);
    let mut exit_code = unsafe { roc_main(args_list) };

    if DEBUG_OR_EXPECT_CALLED.load(Ordering::Acquire) && exit_code == 0 {
        exit_code = 1;
    }

    set_roc_host(core::ptr::null_mut());
    exit_code
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT_TEST_DIR: AtomicUsize = AtomicUsize::new(0);

    struct TestDir(PathBuf);

    impl TestDir {
        fn new() -> Self {
            let sequence = NEXT_TEST_DIR.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "basic-cli-path-type-{}-{sequence}",
                std::process::id()
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }

        fn join(&self, path: impl AsRef<Path>) -> PathBuf {
            self.0.join(path)
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }

    fn classify(path: &Path) -> PathType {
        path_type_from_metadata(&path.symlink_metadata().unwrap())
    }

    #[test]
    fn classifies_regular_files_and_directories() {
        let directory = TestDir::new();
        let file = directory.join("file");
        fs::write(&file, b"contents").unwrap();

        assert_eq!(classify(&directory.0), PathType::Dir);
        assert_eq!(classify(&file), PathType::File);
    }

    #[cfg(unix)]
    #[test]
    fn classifies_symbolic_links() {
        use std::os::unix::fs::symlink;

        let directory = TestDir::new();
        let target = directory.join("target");
        let link = directory.join("link");
        fs::write(&target, b"contents").unwrap();
        symlink(&target, &link).unwrap();

        assert_eq!(classify(&link), PathType::SymLink);
    }

    #[cfg(unix)]
    #[test]
    fn classifies_fifo_as_other() {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;

        let directory = TestDir::new();
        let fifo = directory.join("fifo");
        let fifo_c_string = CString::new(fifo.as_os_str().as_bytes()).unwrap();
        let result = unsafe { libc::mkfifo(fifo_c_string.as_ptr(), 0o600) };
        assert_eq!(result, 0, "mkfifo failed: {}", io::Error::last_os_error());

        assert_eq!(classify(&fifo), PathType::Other);
    }

    #[cfg(unix)]
    #[test]
    fn classifies_unix_domain_socket_as_other() {
        use std::os::unix::net::UnixListener;

        let directory = TestDir::new();
        let socket = directory.join("socket");
        let _listener = UnixListener::bind(&socket).unwrap();

        assert_eq!(classify(&socket), PathType::Other);
    }
}
