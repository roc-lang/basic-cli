use core::mem::ManuallyDrop;
use std::io;

use crate::roc_platform_abi::*;
use crate::{os_string_from_native, roc_host, roc_u8_list_from_slice, NativeOsStr};

type CmdExitResult = HostCmdExecExitCodeResult;
type CmdExitResultPayload = HostCmdExecExitCodeResultPayload;
type CmdExitResultTag = HostCmdExecExitCodeResultTag;
type CmdOutputResult = HostCmdExecOutputResult;
type CmdOutputResultPayload = HostCmdExecOutputResultPayload;
type CmdOutputResultTag = HostCmdExecOutputResultTag;
type CmdOutputError = FailedToGetExitCodeOrNonZeroExitCode;
type CmdOutputErrorPayload = FailedToGetExitCodeOrNonZeroExitCodePayload;
type CmdOutputErrorTag = FailedToGetExitCodeOrNonZeroExitCodeTag;
type CmdOutputFailure = HostCmdExecOutputErrNonZeroExitCode;
type CmdOutputSuccess = HostCmdExecOutputOk;
type Cmd = HostCmdExecExitCodeArgs;

fn cmd_io_err_other(message: &str, roc_host: &RocHost) -> HostIOErr {
    HostIOErr {
        payload: HostIOErrPayload {
            other: ManuallyDrop::new(RocStr::from_str(message, roc_host)),
        },
        tag: HostIOErrTag::Other,
    }
}

fn cmd_io_err_from_io(error: &io::Error, roc_host: &RocHost) -> HostIOErr {
    match error.kind() {
        io::ErrorKind::AlreadyExists => HostIOErr {
            payload: HostIOErrPayload { already_exists: [] },
            tag: HostIOErrTag::AlreadyExists,
        },
        io::ErrorKind::BrokenPipe => HostIOErr {
            payload: HostIOErrPayload { broken_pipe: [] },
            tag: HostIOErrTag::BrokenPipe,
        },
        io::ErrorKind::Interrupted => HostIOErr {
            payload: HostIOErrPayload { interrupted: [] },
            tag: HostIOErrTag::Interrupted,
        },
        io::ErrorKind::IsADirectory => HostIOErr {
            payload: HostIOErrPayload { is_adirectory: [] },
            tag: HostIOErrTag::IsADirectory,
        },
        io::ErrorKind::NotFound => HostIOErr {
            payload: HostIOErrPayload { not_found: [] },
            tag: HostIOErrTag::NotFound,
        },
        io::ErrorKind::NotADirectory => HostIOErr {
            payload: HostIOErrPayload { not_adirectory: [] },
            tag: HostIOErrTag::NotADirectory,
        },
        io::ErrorKind::OutOfMemory => HostIOErr {
            payload: HostIOErrPayload { out_of_memory: [] },
            tag: HostIOErrTag::OutOfMemory,
        },
        io::ErrorKind::PermissionDenied => HostIOErr {
            payload: HostIOErrPayload {
                permission_denied: [],
            },
            tag: HostIOErrTag::PermissionDenied,
        },
        io::ErrorKind::Unsupported => HostIOErr {
            payload: HostIOErrPayload { unsupported: [] },
            tag: HostIOErrTag::Unsupported,
        },
        _ => cmd_io_err_other(&error.to_string(), roc_host),
    }
}

fn cmd_output_io_err_other(message: &str, roc_host: &RocHost) -> IOErr {
    IOErr {
        payload: IOErrPayload {
            other: ManuallyDrop::new(RocStr::from_str(message, roc_host)),
        },
        tag: IOErrTag::Other,
    }
}

fn cmd_output_io_err_from_io(error: &io::Error, roc_host: &RocHost) -> IOErr {
    match error.kind() {
        io::ErrorKind::AlreadyExists => IOErr {
            payload: IOErrPayload { already_exists: [] },
            tag: IOErrTag::AlreadyExists,
        },
        io::ErrorKind::BrokenPipe => IOErr {
            payload: IOErrPayload { broken_pipe: [] },
            tag: IOErrTag::BrokenPipe,
        },
        io::ErrorKind::Interrupted => IOErr {
            payload: IOErrPayload { interrupted: [] },
            tag: IOErrTag::Interrupted,
        },
        io::ErrorKind::IsADirectory => IOErr {
            payload: IOErrPayload { is_adirectory: [] },
            tag: IOErrTag::IsADirectory,
        },
        io::ErrorKind::NotFound => IOErr {
            payload: IOErrPayload { not_found: [] },
            tag: IOErrTag::NotFound,
        },
        io::ErrorKind::NotADirectory => IOErr {
            payload: IOErrPayload { not_adirectory: [] },
            tag: IOErrTag::NotADirectory,
        },
        io::ErrorKind::OutOfMemory => IOErr {
            payload: IOErrPayload { out_of_memory: [] },
            tag: IOErrTag::OutOfMemory,
        },
        io::ErrorKind::PermissionDenied => IOErr {
            payload: IOErrPayload {
                permission_denied: [],
            },
            tag: IOErrTag::PermissionDenied,
        },
        io::ErrorKind::Unsupported => IOErr {
            payload: IOErrPayload { unsupported: [] },
            tag: IOErrTag::Unsupported,
        },
        _ => cmd_output_io_err_other(&error.to_string(), roc_host),
    }
}

fn take_arg_list(
    list: &RocList<NativeOsStr>,
    roc_host: &RocHost,
) -> io::Result<Vec<std::ffi::OsString>> {
    let mut values = Vec::with_capacity(list.len());
    let mut first_error = None;

    for item in list.as_slice() {
        // The list owns its elements even when this outer reference is shared
        // or sliced. Give the consuming converter a separate element reference.
        unsafe { item.incref(1) };
        match os_string_from_native(*item, roc_host) {
            Ok(value) => values.push(value),
            Err(error) => {
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
        }
    }

    unsafe { decref_list_of_unix_bytes_or_utf8or_windows_u16s(*list, roc_host) };

    match first_error {
        Some(error) => Err(error),
        None => Ok(values),
    }
}

fn cmd_to_std(cmd: &Cmd, roc_host: &RocHost) -> io::Result<std::process::Command> {
    let program = os_string_from_native(cmd.program, roc_host);
    let args = take_arg_list(&cmd.args, roc_host);
    let envs = take_arg_list(&cmd.envs, roc_host);
    let cwd = take_arg_list(&cmd.cwd, roc_host);

    let mut std_cmd = std::process::Command::new(program?);

    for arg in args? {
        std_cmd.arg(arg);
    }

    if cmd.clear_envs {
        std_cmd.env_clear();
    }

    if let Some(cwd) = cwd?.first() {
        std_cmd.current_dir(cwd);
    }

    let envs = envs?;
    for chunk in envs.chunks(2) {
        if let [key, value] = chunk {
            std_cmd.env(key, value);
        }
    }

    Ok(std_cmd)
}

fn try_cmd_exit_ok(value: i32) -> CmdExitResult {
    CmdExitResult {
        payload: CmdExitResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdExitResultTag::Ok,
    }
}

fn try_cmd_exit_err(error: HostIOErr) -> CmdExitResult {
    CmdExitResult {
        payload: CmdExitResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdExitResultTag::Err,
    }
}

fn try_cmd_output_ok(value: CmdOutputSuccess) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            ok: ManuallyDrop::new(value),
        },
        tag: CmdOutputResultTag::Ok,
    }
}

fn try_cmd_output_err(error: CmdOutputError) -> CmdOutputResult {
    CmdOutputResult {
        payload: CmdOutputResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: CmdOutputResultTag::Err,
    }
}

fn cmd_output_nonzero_error(value: CmdOutputFailure) -> CmdOutputError {
    CmdOutputError {
        payload: CmdOutputErrorPayload {
            non_zero_exit_code: ManuallyDrop::new(value),
        },
        tag: CmdOutputErrorTag::NonZeroExitCode,
    }
}

fn cmd_output_failed_to_get_exit_code(error: IOErr) -> CmdOutputError {
    CmdOutputError {
        payload: CmdOutputErrorPayload {
            failed_to_get_exit_code: ManuallyDrop::new(error),
        },
        tag: CmdOutputErrorTag::FailedToGetExitCode,
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_exit_code(cmd: Cmd) -> CmdExitResult {
    let roc_host = roc_host();
    let std_cmd = match cmd_to_std(&cmd, roc_host) {
        Ok(cmd) => cmd,
        Err(error) => {
            unsafe { cmd.stdin_bytes.decref(roc_host) };
            return try_cmd_exit_err(cmd_io_err_from_io(&error, roc_host));
        }
    };

    let config = command_config(std_cmd, &cmd, false);
    match crate::process_service::Child::spawn(config).and_then(|child| child.wait()) {
        Ok(status) => match if status.failure == 0 && status.signal == 0 {
            Some(status.exit_code)
        } else {
            None
        } {
            Some(code) => try_cmd_exit_ok(code),
            None => try_cmd_exit_err(cmd_io_err_other(
                incomplete_reason(status.failure),
                roc_host,
            )),
        },
        Err(error) => try_cmd_exit_err(cmd_io_err_from_io(&error, roc_host)),
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_host_exec_output(cmd: Cmd) -> CmdOutputResult {
    let roc_host = roc_host();
    let std_cmd = match cmd_to_std(&cmd, roc_host) {
        Ok(cmd) => cmd,
        Err(error) => {
            unsafe { cmd.stdin_bytes.decref(roc_host) };
            return try_cmd_output_err(cmd_output_failed_to_get_exit_code(
                cmd_output_io_err_from_io(&error, roc_host),
            ));
        }
    };

    let config = command_config(std_cmd, &cmd, true);
    match crate::process_service::Child::spawn(config).and_then(|child| child.wait()) {
        Ok(output) => {
            let stdout_bytes = roc_u8_list_from_slice(&output.stdout, roc_host);
            let stderr_bytes = roc_u8_list_from_slice(&output.stderr, roc_host);

            match if output.failure == 0 && output.signal == 0 {
                Some(output.exit_code)
            } else {
                None
            } {
                Some(0) => try_cmd_output_ok(CmdOutputSuccess {
                    stderr_bytes,
                    stdout_bytes,
                }),
                Some(exit_code) => try_cmd_output_err(cmd_output_nonzero_error(CmdOutputFailure {
                    stderr_bytes,
                    stdout_bytes,
                    exit_code,
                })),
                None => {
                    unsafe {
                        stdout_bytes.decref(roc_host);
                        stderr_bytes.decref(roc_host);
                    }
                    try_cmd_output_err(cmd_output_failed_to_get_exit_code(cmd_output_io_err_other(
                        incomplete_reason(output.failure),
                        roc_host,
                    )))
                }
            }
        }
        Err(error) => try_cmd_output_err(cmd_output_failed_to_get_exit_code(
            cmd_output_io_err_from_io(&error, roc_host),
        )),
    }
}

fn incomplete_reason(failure: u8) -> &'static str {
    match failure {
        1 => "Process execution timed out",
        2 => "Process output limit exceeded",
        _ => "Process was killed by signal",
    }
}

fn command_config(
    command: std::process::Command,
    cmd: &Cmd,
    capture_default: bool,
) -> crate::process_service::Config {
    let input = cmd.stdin_bytes.as_slice().to_vec();
    unsafe {
        cmd.stdin_bytes.decref(roc_host());
    }
    crate::process_service::Config {
        command,
        stdin_mode: if capture_default && cmd.stdin_mode == 0 {
            2
        } else {
            cmd.stdin_mode
        },
        stdout_mode: if capture_default && cmd.stdout_mode == 0 {
            3
        } else {
            cmd.stdout_mode
        },
        stderr_mode: if capture_default && cmd.stderr_mode == 0 {
            3
        } else {
            cmd.stderr_mode
        },
        input,
        timeout_ms: cmd.timeout_ms,
        output_limit: cmd.output_limit as usize,
        pending_limit: cmd.pending_limit as usize,
        manage_tree: cmd.manage_tree,
        merge_stderr: cmd.merge_stderr,
    }
}

macro_rules! normalize_command {
    ($cmd:expr) => {{
        let cmd = $cmd;
        Cmd {
            args: cmd.args,
            envs: cmd.envs,
            program: cmd.program,
            cwd: cmd.cwd,
            clear_envs: cmd.clear_envs,
            stdin_mode: cmd.stdin_mode,
            stdout_mode: cmd.stdout_mode,
            stderr_mode: cmd.stderr_mode,
            stdin_bytes: cmd.stdin_bytes,
            timeout_ms: cmd.timeout_ms,
            output_limit: cmd.output_limit,
            pending_limit: cmd.pending_limit,
            manage_tree: cmd.manage_tree,
            merge_stderr: cmd.merge_stderr,
        }
    }};
}
fn managed_spawn(cmd: Cmd, capture_default: bool) -> io::Result<crate::process_service::Child> {
    let command = match cmd_to_std(&cmd, roc_host()) {
        Ok(command) => command,
        Err(err) => {
            unsafe { cmd.stdin_bytes.decref(roc_host()) };
            return Err(err);
        }
    };
    crate::process_service::Child::spawn(command_config(command, &cmd, capture_default))
}
fn run_output(output: crate::process_service::Output) -> HostCmdRunOk {
    HostCmdRunOk {
        exit_code: output.exit_code,
        signal: output.signal,
        failure: output.failure,
        stdout_bytes: roc_u8_list_from_slice(&output.stdout, roc_host()),
        stderr_bytes: roc_u8_list_from_slice(&output.stderr, roc_host()),
    }
}
fn run_result(result: io::Result<crate::process_service::Output>) -> HostCmdRunResult {
    match result {
        Ok(output) => HostCmdRunResult {
            tag: HostCmdRunResultTag::Ok,
            payload: HostCmdRunResultPayload {
                ok: ManuallyDrop::new(run_output(output)),
            },
        },
        Err(err) => HostCmdRunResult {
            tag: HostCmdRunResultTag::Err,
            payload: HostCmdRunResultPayload {
                err: ManuallyDrop::new(cmd_output_io_err_from_io(&err, roc_host())),
            },
        },
    }
}
fn unit_result(result: io::Result<()>) -> HostChildCloseResult {
    match result {
        Ok(()) => HostChildCloseResult {
            tag: HostChildCloseResultTag::Ok,
            payload: HostChildCloseResultPayload { ok: [] },
        },
        Err(err) => HostChildCloseResult {
            tag: HostChildCloseResultTag::Err,
            payload: HostChildCloseResultPayload {
                err: ManuallyDrop::new(cmd_output_io_err_from_io(&err, roc_host())),
            },
        },
    }
}
fn with_child<T>(handle: *mut u64, f: impl FnOnce(&crate::process_service::Child) -> T) -> T {
    let result =
        f(unsafe { crate::resources::resource_ref::<crate::process_service::Child>(handle) });
    crate::resources::release(handle, roc_host());
    result
}
#[no_mangle]
pub extern "C" fn hosted_cmd_spawn(cmd: HostCmdSpawnArgs) -> HostCmdSpawnResult {
    match managed_spawn(normalize_command!(cmd), false) {
        Ok(child) => HostCmdSpawnResult {
            tag: HostCmdSpawnResultTag::Ok,
            payload: HostCmdSpawnResultPayload {
                ok: ManuallyDrop::new(crate::resources::box_resource(child, roc_host())),
            },
        },
        Err(err) => HostCmdSpawnResult {
            tag: HostCmdSpawnResultTag::Err,
            payload: HostCmdSpawnResultPayload {
                err: ManuallyDrop::new(cmd_output_io_err_from_io(&err, roc_host())),
            },
        },
    }
}
#[no_mangle]
pub extern "C" fn hosted_cmd_run(cmd: HostCmdRunArgs) -> HostCmdRunResult {
    run_result(managed_spawn(normalize_command!(cmd), true).and_then(|child| child.wait()))
}
#[no_mangle]
pub extern "C" fn hosted_child_pid(handle: *mut u64) -> HostChildPidResult {
    match with_child(handle, |child| child.pid()) {
        Ok(pid) => HostChildPidResult {
            tag: HostChildPidResultTag::Ok,
            payload: HostChildPidResultPayload {
                ok: ManuallyDrop::new(pid),
            },
        },
        Err(err) => HostChildPidResult {
            tag: HostChildPidResultTag::Err,
            payload: HostChildPidResultPayload {
                err: ManuallyDrop::new(cmd_output_io_err_from_io(&err, roc_host())),
            },
        },
    }
}
#[no_mangle]
pub extern "C" fn hosted_child_wait(handle: *mut u64) -> HostChildWaitResult {
    run_result(with_child(handle, |child| child.wait()))
}
#[no_mangle]
pub extern "C" fn hosted_child_try_wait(handle: *mut u64) -> HostChildTryWaitResult {
    match with_child(handle, |child| child.try_wait()) {
        Ok(output) => {
            let values: Vec<_> = output.into_iter().map(run_output).collect();
            let list = unsafe { RocList::from_slice(&values, roc_host()) };
            HostChildTryWaitResult {
                tag: HostChildTryWaitResultTag::Ok,
                payload: HostChildTryWaitResultPayload {
                    ok: ManuallyDrop::new(list),
                },
            }
        }
        Err(err) => HostChildTryWaitResult {
            tag: HostChildTryWaitResultTag::Err,
            payload: HostChildTryWaitResultPayload {
                err: ManuallyDrop::new(cmd_output_io_err_from_io(&err, roc_host())),
            },
        },
    }
}
#[no_mangle]
pub extern "C" fn hosted_child_kill(handle: *mut u64) -> HostChildKillResult {
    unit_result(with_child(handle, |child| child.kill()))
}
#[no_mangle]
pub extern "C" fn hosted_child_close(handle: *mut u64) -> HostChildCloseResult {
    unit_result(with_child(handle, |child| child.close()))
}
#[no_mangle]
pub extern "C" fn hosted_child_close_stdin(handle: *mut u64) -> HostChildCloseStdinResult {
    unit_result(with_child(handle, |child| child.close_stdin()))
}
#[no_mangle]
pub extern "C" fn hosted_child_write(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
    timeout_ms: u64,
) -> HostChildWriteResult {
    let input = bytes.as_slice().to_vec();
    unsafe { bytes.decref(roc_host()) };
    unit_result(with_child(handle, |child| child.write(input, timeout_ms)))
}
#[no_mangle]
pub extern "C" fn hosted_child_read(
    handle: *mut u64,
    max_bytes: u64,
    timeout_ms: u64,
) -> HostChildReadResult {
    match with_child(handle, |child| child.read(max_bytes as usize, timeout_ms)) {
        Ok(event) => HostChildReadResult {
            tag: HostChildReadResultTag::Ok,
            payload: HostChildReadResultPayload {
                ok: ManuallyDrop::new(HostChildReadOk {
                    stream: event.stream,
                    bytes: roc_u8_list_from_slice(&event.bytes, roc_host()),
                }),
            },
        },
        Err(err) => HostChildReadResult {
            tag: HostChildReadResultTag::Err,
            payload: HostChildReadResultPayload {
                err: ManuallyDrop::new(cmd_output_io_err_from_io(&err, roc_host())),
            },
        },
    }
}

#[cfg(test)]
mod ownership_tests {
    use super::*;
    use std::{cell::RefCell, ffi::c_void};

    thread_local! {
        // Defer actual frees so an ownership regression fails an assertion rather
        // than relying on reading freed memory to expose the bug.
        static FREES: RefCell<Vec<(*mut c_void, usize)>> = const { RefCell::new(Vec::new()) };
    }
    extern "C" fn defer_free(_: *mut RocHost, ptr: *mut c_void, alignment: usize) {
        FREES.with(|frees| frees.borrow_mut().push((ptr, alignment)));
    }
    fn host() -> RocHost {
        assert_eq!(free_count(), 0);
        let mut host = make_roc_host(std::ptr::null_mut());
        host.roc_dealloc = defer_free;
        host
    }
    fn free_count() -> usize {
        FREES.with(|frees| frees.borrow().len())
    }
    fn finish(mut host: RocHost, expected: usize) {
        let frees = FREES.with(|frees| std::mem::take(&mut *frees.borrow_mut()));
        assert_eq!(frees.len(), expected);
        for (ptr, alignment) in frees {
            DefaultAllocators::roc_dealloc(&mut host, ptr, alignment);
        }
    }
    fn utf8(value: &str, host: &RocHost) -> NativeOsStr {
        NativeOsStr {
            tag: UnixBytesOrUtf8OrWindowsU16sTag::Utf8,
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                utf8: ManuallyDrop::new(RocStr::from_str(value, host)),
            },
        }
    }

    #[test]
    fn consuming_shared_argument_list_preserves_nested_strings() {
        let host = host();
        let first = "first argument long enough to need a heap allocation";
        let second = "second argument also needing its own heap allocation";
        let list =
            unsafe { RocList::from_slice(&[utf8(first, &host), utf8(second, &host)], &host) };
        unsafe {
            list.incref(1);
        }
        assert_eq!(take_arg_list(&list, &host).unwrap(), [first, second]);
        assert_eq!(free_count(), 0, "shared list elements must remain alive");
        assert_eq!(take_arg_list(&list, &host).unwrap(), [first, second]);
        finish(host, 3);
    }

    #[test]
    fn final_argument_slice_releases_the_entire_backing_allocation() {
        let host = host();
        let words = [
            "hidden prefix is heap allocated too",
            "visible middle argument needs the heap",
            "hidden suffix also needs heap storage",
        ];
        let values: Vec<_> = words.iter().map(|value| utf8(value, &host)).collect();
        let list = unsafe { RocList::from_slice(&values, &host) };
        let slice = RocList {
            elements: unsafe { list.elements.add(1) },
            length: 1,
            capacity_or_alloc_ptr: list.elements as usize | 1,
        };
        assert_eq!(take_arg_list(&slice, &host).unwrap(), [words[1]]);
        finish(host, 4);
    }

    #[test]
    fn shared_native_argument_slice_preserves_caller_storage() {
        let host = host();
        #[cfg(unix)]
        let native = NativeOsStr {
            tag: UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes,
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                unix_bytes: ManuallyDrop::new(unsafe {
                    RocListWith::<u8, false>::from_slice(&[255, 42, 128], &host)
                }),
            },
        };
        #[cfg(windows)]
        let native = NativeOsStr {
            tag: UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s,
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                windows_u16s: ManuallyDrop::new(unsafe {
                    RocListWith::<u16, false>::from_slice(&[0xd800, 42, 0xdc00], &host)
                }),
            },
        };
        let list = unsafe {
            RocList::from_slice(
                &[
                    utf8("hidden string kept by the shared backing list", &host),
                    native,
                ],
                &host,
            )
        };
        unsafe {
            list.incref(1);
        }
        let slice = RocList {
            elements: unsafe { list.elements.add(1) },
            length: 1,
            capacity_or_alloc_ptr: list.elements as usize | 1,
        };
        let selected = take_arg_list(&slice, &host).unwrap();
        assert_eq!(
            free_count(),
            0,
            "a shared slice cannot release any child allocation"
        );
        let all = take_arg_list(&list, &host).unwrap();
        assert_eq!(selected[0], all[1]);
        finish(host, 3);
    }
}
