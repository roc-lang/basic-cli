//! The hosted `Cmd` and `Child` functions: conversions between the generated
//! Roc ABI types and the Rust-owned process service.
use core::mem::ManuallyDrop;
use std::io;
use std::time::Duration;

use crate::process_service::{
    Child, ChildError, Config, Error, Event, Output, OutputMode, Partial, Status, StderrMode,
    StdinMode, Stream,
};
use crate::roc_platform_abi::*;
use crate::{
    cmd_io_err_from_io, os_string_from_native, path_from_native, roc_host, roc_u8_list_from_slice,
    NativeOsStr,
};

// `cmd_run!` and `cmd_spawn!` take the same record, which the generator emits
// once per function.
type Cmd = HostCmdRunArgs;
type CmdErr = HostCmdRunErrCmdErr;
type CmdErrPayload = HostCmdRunErrCmdErrPayload;
type CmdErrTag = HostCmdRunErrCmdErrTag;
type CmdOutput = HostCmdRunOk;
type CmdPartialOutput = HostCmdRunErrCmdErrTimedOut;
type ChildErr = HostChildWaitErr;
type ChildErrPayload = HostChildWaitErrPayload;
type ChildErrTag = HostChildWaitErrTag;
type ChildUnitResult = HostChildKillResult;
type ChildUnitResultPayload = HostChildKillResultPayload;
type ChildUnitResultTag = HostChildKillResultTag;

// Generated aliases for the error-only [Failed(IOErr), Interrupted] result
// of Host.cmd_exec!, kept independent of the generator's numbered type name.
type ExecFailure = FailedOrInterrupted;
type ExecFailureTag = FailedOrInterruptedTag;
type ExecFailurePayload = FailedOrInterruptedPayload;

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

/// Consume every refcounted field of a hosted command, whether or not all of
/// them convert, and build the service configuration.
fn command_config(cmd: Cmd, roc_host: &RocHost) -> io::Result<Config> {
    let program = os_string_from_native(cmd.program, roc_host);
    let args = take_arg_list(&cmd.args, roc_host);
    let envs = take_arg_list(&cmd.envs, roc_host);
    let cwd = match cmd.cwd.tag {
        DirOrInheritTag::Dir => {
            let dir = ManuallyDrop::into_inner(unsafe { cmd.cwd.payload.dir });
            path_from_native(dir, roc_host).map(Some)
        }
        DirOrInheritTag::Inherit => Ok(None),
    };
    let stdin = match cmd.stdin.tag {
        BytesOrInheritOrNullOrPipeTag::Bytes => {
            let bytes = ManuallyDrop::into_inner(unsafe { cmd.stdin.payload.bytes });
            let input = bytes.as_slice().to_vec();
            unsafe { bytes.decref(roc_host) };
            StdinMode::Bytes(input)
        }
        BytesOrInheritOrNullOrPipeTag::Inherit => StdinMode::Inherit,
        BytesOrInheritOrNullOrPipeTag::Null => StdinMode::Null,
        BytesOrInheritOrNullOrPipeTag::Pipe => StdinMode::Pipe,
    };

    // Convert both path payloads before propagating any conversion failure,
    // so every Roc-owned field is consumed even when another field is invalid.
    let stdout = stdout_config(cmd.stdout, roc_host);
    let stderr = stderr_config(cmd.stderr, roc_host);
    let program = program?;
    let args = args?;
    let envs = envs?;
    let cwd = cwd?;
    let (stdout, stdout_spec) = stdout?;
    let (stderr, stderr_spec) = stderr?;
    let open = |spec: Option<FileOutput>| -> io::Result<Option<std::fs::File>> {
        if crate::signals::is_pending() {
            return Err(io::ErrorKind::Interrupted.into());
        }
        spec.map(|spec| {
            let path = match &cwd {
                Some(directory) if spec.path.is_relative() => directory.join(&spec.path),
                _ => spec.path,
            };
            crate::file_writer::open_file(&path, spec.mode, spec.policy)
        })
        .transpose()
    };
    let stdout_file = open(stdout_spec)?;
    let stderr_file = open(stderr_spec)?;
    let mut command = std::process::Command::new(program);
    command.args(args);
    if cmd.clear_envs {
        command.env_clear();
    }
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    for pair in envs.chunks(2) {
        if let [key, value] = pair {
            command.env(key, value);
        }
    }

    Ok(Config {
        command,
        stdin,
        stdout,
        stderr,
        stdout_file,
        stderr_file,
        timeout: match cmd.timeout.tag {
            AfterNanosOrNoTimeoutTag::AfterNanos => {
                Some(Duration::from_nanos(ManuallyDrop::into_inner(unsafe {
                    cmd.timeout.payload.after_nanos
                })))
            }
            AfterNanosOrNoTimeoutTag::NoTimeout => None,
        },
        output_limit: match cmd.output_limit.tag {
            MaxBytesOrNoLimitTag::MaxBytes => {
                let bytes = ManuallyDrop::into_inner(unsafe { cmd.output_limit.payload.max_bytes });
                // More than the address space holds is no limit at all.
                usize::try_from(bytes).ok()
            }
            MaxBytesOrNoLimitTag::NoLimit => None,
        },
        pending_limit: usize::try_from(cmd.pending_limit).unwrap_or(usize::MAX),
        manage_tree: cmd.manage_tree,
    })
}

struct FileOutput {
    path: std::path::PathBuf,
    mode: AppendOrRequireNewOrTruncate,
    policy: crate::file_security::Policy,
}
fn file_output(
    file: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeFile,
    host: &RocHost,
) -> io::Result<FileOutput> {
    let path = path_from_native(file.path, host)?;
    let policy = match file.create_permissions {
        DefaultOrOwnerOnlyOrPublicRead::Default => crate::file_security::Policy::Default,
        DefaultOrOwnerOnlyOrPublicRead::OwnerOnly => crate::file_security::Policy::OwnerOnly,
        DefaultOrOwnerOnlyOrPublicRead::PublicRead => crate::file_security::Policy::PublicRead,
    };
    Ok(FileOutput {
        path,
        mode: file.mode,
        policy,
    })
}
fn stdout_config(
    mode: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTee,
    host: &RocHost,
) -> io::Result<(OutputMode, Option<FileOutput>)> {
    use CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeTag as Tag;
    let mode = match mode.tag {
        Tag::Capture => OutputMode::Capture,
        Tag::Inherit => OutputMode::Inherit,
        Tag::InheritStderr => OutputMode::InheritStderr,
        Tag::Null => OutputMode::Null,
        Tag::Pipe => OutputMode::Pipe,
        Tag::Tee => OutputMode::Tee,
        Tag::File => {
            return Ok((
                OutputMode::File,
                Some(file_output(
                    ManuallyDrop::into_inner(unsafe { mode.payload.file }),
                    host,
                )?),
            ))
        }
    };
    Ok((mode, None))
}
fn stderr_config(
    mode: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTee,
    host: &RocHost,
) -> io::Result<(StderrMode, Option<FileOutput>)> {
    use CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeeTag as Tag;
    let mode = match mode.tag {
        Tag::Capture => OutputMode::Capture,
        Tag::Inherit => OutputMode::Inherit,
        Tag::Null => OutputMode::Null,
        Tag::Pipe => OutputMode::Pipe,
        Tag::Tee => OutputMode::Tee,
        Tag::MergeWithStdout => return Ok((StderrMode::MergeWithStdout, None)),
        Tag::File => {
            return Ok((
                StderrMode::Separate(OutputMode::File),
                Some(file_output(
                    ManuallyDrop::into_inner(unsafe { mode.payload.file }),
                    host,
                )?),
            ))
        }
    };
    Ok((StderrMode::Separate(mode), None))
}

fn same_command(cmd: HostCmdSpawnArgs) -> Cmd {
    Cmd {
        args: cmd.args,
        clear_envs: cmd.clear_envs,
        cwd: cmd.cwd,
        envs: cmd.envs,
        manage_tree: cmd.manage_tree,
        output_limit: cmd.output_limit,
        pending_limit: cmd.pending_limit,
        program: cmd.program,
        stderr: cmd.stderr,
        stdin: cmd.stdin,
        stdout: cmd.stdout,
        timeout: cmd.timeout,
    }
}

/// Start a command. A command that cannot be converted for this operating
/// system never starts, which is the same failure as a program that is missing.
fn start(cmd: Cmd) -> Result<Child, Error> {
    let config = command_config(cmd, roc_host()).map_err(|error| {
        if error.kind() == io::ErrorKind::Interrupted && crate::signals::is_pending() {
            Error::Interrupted
        } else {
            Error::Start(error)
        }
    })?;
    Child::spawn(config)
}

fn partial_output(partial: &Partial) -> CmdPartialOutput {
    CmdPartialOutput {
        stdout_bytes: roc_u8_list_from_slice(&partial.stdout, roc_host()),
        stderr_bytes: roc_u8_list_from_slice(&partial.stderr, roc_host()),
    }
}

fn cmd_err(error: &Error) -> CmdErr {
    let roc_host = roc_host();
    match error {
        Error::Interrupted => unreachable!("interruption is outside the command cause"),
        Error::Start(error) => CmdErr {
            tag: CmdErrTag::StartFailed,
            payload: CmdErrPayload {
                start_failed: ManuallyDrop::new(cmd_io_err_from_io(error, roc_host)),
            },
        },
        Error::TimedOut(partial) => CmdErr {
            tag: CmdErrTag::TimedOut,
            payload: CmdErrPayload {
                timed_out: ManuallyDrop::new(partial_output(partial)),
            },
        },
        Error::OutputLimitExceeded(partial) => CmdErr {
            tag: CmdErrTag::OutputLimitExceeded,
            payload: CmdErrPayload {
                output_limit_exceeded: ManuallyDrop::new(partial_output(partial)),
            },
        },
        Error::Io(error) => CmdErr {
            tag: CmdErrTag::IOErr,
            payload: CmdErrPayload {
                ioerr: ManuallyDrop::new(cmd_io_err_from_io(error, roc_host)),
            },
        },
    }
}

fn child_err(error: &ChildError) -> ChildErr {
    match error {
        ChildError::Cmd(Error::Interrupted) => ChildErr {
            tag: ChildErrTag::Interrupted,
            payload: ChildErrPayload { interrupted: [] },
        },
        ChildError::Closed => ChildErr {
            tag: ChildErrTag::Closed,
            payload: ChildErrPayload { closed: [] },
        },
        ChildError::Cmd(error) => ChildErr {
            tag: ChildErrTag::CmdErr,
            payload: ChildErrPayload {
                cmd_err: ManuallyDrop::new(cmd_err(error)),
            },
        },
    }
}

fn nonblocking_child_err(error: &ChildError) -> HostChildKillErr {
    match error {
        ChildError::Closed => HostChildKillErr {
            tag: HostChildKillErrTag::Closed,
            payload: HostChildKillErrPayload { closed: [] },
        },
        ChildError::Cmd(error) => HostChildKillErr {
            tag: HostChildKillErrTag::CmdErr,
            payload: HostChildKillErrPayload {
                cmd_err: ManuallyDrop::new(cmd_err(error)),
            },
        },
    }
}

fn command_err(error: &Error) -> HostCmdRunErr {
    match error {
        Error::Interrupted => HostCmdRunErr {
            tag: HostCmdRunErrTag::Interrupted,
            payload: HostCmdRunErrPayload { interrupted: [] },
        },
        error => HostCmdRunErr {
            tag: HostCmdRunErrTag::CmdErr,
            payload: HostCmdRunErrPayload {
                cmd_err: ManuallyDrop::new(cmd_err(error)),
            },
        },
    }
}

fn cmd_output(output: &Output) -> CmdOutput {
    CmdOutput {
        status: match output.status {
            Status::Exited(code) => ExitedOrSignaled {
                tag: ExitedOrSignaledTag::Exited,
                payload: ExitedOrSignaledPayload {
                    exited: ManuallyDrop::new(code),
                },
            },
            Status::Signaled(signal) => ExitedOrSignaled {
                tag: ExitedOrSignaledTag::Signaled,
                payload: ExitedOrSignaledPayload {
                    signaled: ManuallyDrop::new(signal),
                },
            },
        },
        stdout_bytes: roc_u8_list_from_slice(&output.stdout, roc_host()),
        stderr_bytes: roc_u8_list_from_slice(&output.stderr, roc_host()),
    }
}

fn unit_result(result: Result<(), ChildError>) -> ChildUnitResult {
    match result {
        Ok(()) => ChildUnitResult {
            tag: ChildUnitResultTag::Ok,
            payload: ChildUnitResultPayload { ok: [] },
        },
        Err(error) => ChildUnitResult {
            tag: ChildUnitResultTag::Err,
            payload: ChildUnitResultPayload {
                err: ManuallyDrop::new(nonblocking_child_err(&error)),
            },
        },
    }
}

/// Borrow the child behind a handle for one hosted call, then drop the
/// reference the call was passed.
fn with_child<T>(handle: *mut u64, f: impl FnOnce(&Child) -> T) -> T {
    let result = f(unsafe { crate::resources::resource_ref::<Child>(handle) });
    crate::resources::release(handle, roc_host());
    result
}

#[no_mangle]
pub extern "C" fn hosted_cmd_spawn(cmd: HostCmdSpawnArgs) -> HostCmdSpawnResult {
    let spawned = start(same_command(cmd))
        .and_then(|child| crate::resources::box_resource(child, roc_host()).map_err(Error::Start));
    match spawned {
        Ok(handle) => HostCmdSpawnResult {
            tag: HostCmdSpawnResultTag::Ok,
            payload: HostCmdSpawnResultPayload {
                ok: ManuallyDrop::new(handle),
            },
        },
        Err(error) => HostCmdSpawnResult {
            tag: HostCmdSpawnResultTag::Err,
            payload: HostCmdSpawnResultPayload {
                err: ManuallyDrop::new(command_err(&error)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_cmd_run(cmd: HostCmdRunArgs) -> HostCmdRunResult {
    let finished = start(cmd).and_then(|child| match child.wait_foreground() {
        Ok(output) => Ok(output),
        Err(ChildError::Cmd(error)) => Err(error),
        // Nothing else holds this child, so nothing can have closed it.
        Err(ChildError::Closed) => Err(Error::Io(io::Error::other("Child is closed"))),
    });
    match finished {
        Ok(output) => HostCmdRunResult {
            tag: HostCmdRunResultTag::Ok,
            payload: HostCmdRunResultPayload {
                ok: ManuallyDrop::new(cmd_output(&output)),
            },
        },
        Err(error) => HostCmdRunResult {
            tag: HostCmdRunResultTag::Err,
            payload: HostCmdRunResultPayload {
                err: ManuallyDrop::new(command_err(&error)),
            },
        },
    }
}

#[cfg(unix)]
fn replace_process(path: &std::path::Path, args: &[std::ffi::OsString]) -> io::Error {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let arguments = std::iter::once(path.as_os_str()).chain(args.iter().map(|arg| arg.as_os_str()));
    let strings: Result<Vec<_>, _> = arguments.map(|arg| CString::new(arg.as_bytes())).collect();
    let strings = match strings {
        Ok(strings) => strings,
        Err(_) => {
            return io::Error::new(
                io::ErrorKind::InvalidInput,
                "executable and arguments cannot contain NUL",
            )
        }
    };
    let mut pointers: Vec<_> = strings.iter().map(|arg| arg.as_ptr()).collect();
    pointers.push(std::ptr::null());
    // No fork and no process-global setup: an error leaves the running Roc
    // program, its terminal, its environment and its resource owners intact.
    unsafe {
        libc::execv(strings[0].as_ptr(), pointers.as_ptr());
    }
    io::Error::last_os_error()
}

#[cfg(windows)]
fn replace_process(_: &std::path::Path, _: &[std::ffi::OsString]) -> io::Error {
    // A System.Unix proof cannot be obtained on Windows through the public API.
    io::Error::from(io::ErrorKind::Unsupported)
}

#[no_mangle]
pub extern "C" fn hosted_cmd_exec(
    _unix: SystemUnix,
    path: NativeOsStr,
    args: RocList<NativeOsStr>,
) -> ExecFailure {
    // Consume both owned inputs even when conversion or cancellation fails.
    let path = path_from_native(path, roc_host());
    let args = take_arg_list(&args, roc_host());
    if crate::signals::is_pending() {
        return ExecFailure {
            tag: ExecFailureTag::Interrupted,
            payload: ExecFailurePayload { interrupted: [] },
        };
    }
    let error = match (path, args) {
        (Ok(path), Ok(args)) => replace_process(&path, &args),
        (Err(error), _) | (_, Err(error)) => error,
    };
    ExecFailure {
        tag: ExecFailureTag::Failed,
        payload: ExecFailurePayload {
            failed: ManuallyDrop::new(cmd_io_err_from_io(&error, roc_host())),
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_child_pid(handle: *mut u64) -> u32 {
    with_child(handle, |child| child.pid())
}

#[no_mangle]
pub extern "C" fn hosted_child_wait(handle: *mut u64) -> HostChildWaitResult {
    match with_child(handle, |child| child.wait()) {
        Ok(output) => HostChildWaitResult {
            tag: HostChildWaitResultTag::Ok,
            payload: HostChildWaitResultPayload {
                ok: ManuallyDrop::new(cmd_output(&output)),
            },
        },
        Err(error) => HostChildWaitResult {
            tag: HostChildWaitResultTag::Err,
            payload: HostChildWaitResultPayload {
                err: ManuallyDrop::new(child_err(&error)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_child_poll(handle: *mut u64) -> HostChildPollResult {
    let state = match with_child(handle, |child| child.poll()) {
        Ok(Some(output)) => Ok(HostChildPollOk {
            tag: HostChildPollOkTag::Finished,
            payload: HostChildPollOkPayload {
                finished: ManuallyDrop::new(cmd_output(&output)),
            },
        }),
        Ok(None) => Ok(HostChildPollOk {
            tag: HostChildPollOkTag::Running,
            payload: HostChildPollOkPayload { running: [] },
        }),
        Err(error) => Err(nonblocking_child_err(&error)),
    };
    match state {
        Ok(state) => HostChildPollResult {
            tag: HostChildPollResultTag::Ok,
            payload: HostChildPollResultPayload {
                ok: ManuallyDrop::new(state),
            },
        },
        Err(error) => HostChildPollResult {
            tag: HostChildPollResultTag::Err,
            payload: HostChildPollResultPayload {
                err: ManuallyDrop::new(error),
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
    match with_child(handle, |child| child.close()) {
        Ok(()) => HostChildCloseResult {
            tag: HostChildCloseResultTag::Ok,
            payload: HostChildCloseResultPayload { ok: [] },
        },
        Err(error) => HostChildCloseResult {
            tag: HostChildCloseResultTag::Err,
            payload: HostChildCloseResultPayload {
                err: ManuallyDrop::new(cmd_err(&error)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_child_close_stdin(handle: *mut u64) -> HostChildCloseStdinResult {
    unit_result(with_child(handle, |child| child.close_stdin()))
}

#[no_mangle]
pub extern "C" fn hosted_child_write(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
    wait_nanos: u64,
) -> HostChildWriteResult {
    let input = bytes.as_slice().to_vec();
    unsafe { bytes.decref(roc_host()) };
    match with_child(handle, |child| {
        child.write(input, Duration::from_nanos(wait_nanos))
    }) {
        Ok(()) => HostChildWriteResult {
            tag: HostChildWriteResultTag::Ok,
            payload: HostChildWriteResultPayload { ok: [] },
        },
        Err(error) => HostChildWriteResult {
            tag: HostChildWriteResultTag::Err,
            payload: HostChildWriteResultPayload {
                err: ManuallyDrop::new(child_err(&error)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_child_read(handle: *mut u64, wait_nanos: u64) -> HostChildReadResult {
    let read = with_child(handle, |child| child.read(Duration::from_nanos(wait_nanos)));
    let err = |tag, payload| HostChildReadResult {
        tag: HostChildReadResultTag::Err,
        payload: HostChildReadResultPayload {
            err: ManuallyDrop::new(HostChildReadErr { tag, payload }),
        },
    };
    match read {
        Ok(Some(Event { stream, bytes })) => {
            let bytes = ManuallyDrop::new(roc_u8_list_from_slice(&bytes, roc_host()));
            let chunk = match stream {
                Stream::Stdout => HostChildReadOk {
                    tag: HostChildReadOkTag::Stdout,
                    payload: HostChildReadOkPayload { stdout: bytes },
                },
                Stream::Stderr => HostChildReadOk {
                    tag: HostChildReadOkTag::Stderr,
                    payload: HostChildReadOkPayload { stderr: bytes },
                },
            };
            HostChildReadResult {
                tag: HostChildReadResultTag::Ok,
                payload: HostChildReadResultPayload {
                    ok: ManuallyDrop::new(chunk),
                },
            }
        }
        Ok(None) => err(
            HostChildReadErrTag::EndOfInput,
            HostChildReadErrPayload { end_of_input: [] },
        ),
        Err(ChildError::Cmd(Error::Interrupted)) => err(
            HostChildReadErrTag::Interrupted,
            HostChildReadErrPayload { interrupted: [] },
        ),
        Err(ChildError::Closed) => err(
            HostChildReadErrTag::Closed,
            HostChildReadErrPayload { closed: [] },
        ),
        Err(ChildError::Cmd(error)) => err(
            HostChildReadErrTag::CmdErr,
            HostChildReadErrPayload {
                cmd_err: ManuallyDrop::new(cmd_err(&error)),
            },
        ),
    }
}

#[cfg(all(test, unix))]
mod exec_tests {
    use super::*;
    use std::io::Write;
    use std::os::unix::ffi::OsStringExt;
    use std::os::unix::fs::PermissionsExt;
    use std::process::{Command, Stdio};

    #[test]
    fn exec_helper() {
        match std::env::var("BASIC_CLI_EXEC_TEST").as_deref() {
            Ok("replace") => {
                println!("before:{}", std::process::id());
                let script = "printf 'after:%s\\narg:' \"$$\"; printf '%s' \"$1\"; printf '\\nenv:%s\\ncwd:%s\\n' \"$BASIC_CLI_EXEC_ENV\" \"$PWD\"; IFS= read -r line; printf 'stdin:%s\\n' \"$line\"; printf 'stderr preserved\\n' >&2; exit 7";
                let args = vec![
                    "-c".into(),
                    script.into(),
                    "native-exec".into(),
                    std::ffi::OsString::from_vec(vec![255, b' ', b'$', b'*']),
                ];
                panic!(
                    "replacement failed: {}",
                    replace_process(std::path::Path::new("/bin/sh"), &args)
                );
            }
            Ok("format") => {
                let directory = tempfile::tempdir().unwrap();
                let path = directory.path().join("without-shebang");
                std::fs::write(&path, b"exit 0\n").unwrap();
                std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
                assert_eq!(
                    replace_process(&path, &[]).raw_os_error(),
                    Some(libc::ENOEXEC)
                );
                println!("unrecognized format returned without a shell");
            }
            _ => {}
        }
    }

    fn helper(mode: &str) -> Command {
        let mut command = Command::new(std::env::current_exe().unwrap());
        command
            .args(["--exact", "cmd::exec_tests::exec_helper", "--nocapture"])
            .env("BASIC_CLI_EXEC_TEST", mode)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command
    }

    #[test]
    fn native_replacement_preserves_pid_arguments_and_inherited_state() {
        let directory = tempfile::tempdir().unwrap();
        let mut child = helper("replace")
            .env("BASIC_CLI_EXEC_ENV", "visible")
            .current_dir(directory.path())
            .stdin(Stdio::piped())
            .spawn()
            .unwrap();
        let pid = child.id();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(b"input preserved\n")
            .unwrap();
        let output = child.wait_with_output().unwrap();
        assert_eq!(output.status.code(), Some(7));
        let expected = format!("before:{pid}\nafter:{pid}\narg:").into_bytes();
        assert!(output
            .stdout
            .windows(expected.len())
            .any(|bytes| bytes == expected));
        assert!(output
            .stdout
            .windows(9)
            .any(|bytes| bytes == [255, b' ', b'$', b'*', b'\n', b'e', b'n', b'v', b':']));
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(text.contains("env:visible\n"));
        assert!(text.contains(&format!(
            "cwd:{}\n",
            directory.path().canonicalize().unwrap().display()
        )));
        assert!(text.contains("stdin:input preserved\n"));
        assert_eq!(output.stderr, b"stderr preserved\n");
    }

    #[test]
    fn native_replacement_does_not_start_an_implicit_shell() {
        let output = helper("format").output().unwrap();
        assert!(output.status.success());
        assert!(String::from_utf8_lossy(&output.stdout)
            .contains("unrecognized format returned without a shell"));
    }

    #[test]
    fn failed_replacement_rejects_nul_and_preserves_the_current_directory() {
        let cwd = std::env::current_dir().unwrap();
        assert_eq!(
            replace_process(std::path::Path::new("/missing-basic-cli-executable"), &[]).kind(),
            io::ErrorKind::NotFound
        );
        let nul = std::ffi::OsString::from_vec(vec![b'x', 0]);
        assert_eq!(
            replace_process(std::path::Path::new("/bin/sh"), &[nul]).kind(),
            io::ErrorKind::InvalidInput
        );
        assert_eq!(std::env::current_dir().unwrap(), cwd);
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

    /// A command whose every refcounted field owns a heap allocation: the
    /// program, one argument and its list, two environment strings and their
    /// list, the working directory, and the stdin bytes. Eight in all.
    fn heap_command(program: NativeOsStr, host: &RocHost) -> Cmd {
        let args = [utf8("an argument long enough to need the heap", host)];
        let envs = [
            utf8("A_VARIABLE_NAME_LONG_ENOUGH_FOR_THE_HEAP", host),
            utf8("a variable value long enough for the heap", host),
        ];
        Cmd {
            output_limit: MaxBytesOrNoLimit {
                tag: MaxBytesOrNoLimitTag::MaxBytes,
                payload: MaxBytesOrNoLimitPayload {
                    max_bytes: ManuallyDrop::new(7),
                },
            },
            pending_limit: 9,
            timeout: AfterNanosOrNoTimeout {
                tag: AfterNanosOrNoTimeoutTag::AfterNanos,
                payload: AfterNanosOrNoTimeoutPayload {
                    after_nanos: ManuallyDrop::new(0),
                },
            },
            args: unsafe { RocList::from_slice(&args, host) },
            cwd: DirOrInherit {
                tag: DirOrInheritTag::Dir,
                payload: DirOrInheritPayload {
                    dir: ManuallyDrop::new(utf8("a/directory/name/long/enough/for/the/heap", host)),
                },
            },
            envs: unsafe { RocList::from_slice(&envs, host) },
            program,
            stdin: BytesOrInheritOrNullOrPipe {
                tag: BytesOrInheritOrNullOrPipeTag::Bytes,
                payload: BytesOrInheritOrNullOrPipePayload {
                    bytes: ManuallyDrop::new(unsafe {
                        RocListWith::<u8, false>::from_slice(&[0, 42, 255], host)
                    }),
                },
            },
            clear_envs: true,
            manage_tree: true,
            stderr: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTee {
                tag: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeeTag::MergeWithStdout,
                payload: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeePayload {
                    merge_with_stdout: [],
                },
            },
            stdout: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTee {
                tag: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeTag::Tee,
                payload: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeePayload { tee: [] },
            },
        }
    }

    #[test]
    fn command_config_consumes_every_field_and_keeps_typed_settings() {
        let host = host();
        let program = "a program name long enough to need the heap";
        let config = command_config(heap_command(utf8(program, &host), &host), &host).unwrap();
        assert_eq!(config.command.get_program(), program);
        assert_eq!(
            config.command.get_args().collect::<Vec<_>>(),
            ["an argument long enough to need the heap"]
        );
        // The working directory arrives as a union nested in a union.
        assert_eq!(
            config.command.get_current_dir(),
            Some(std::path::Path::new(
                "a/directory/name/long/enough/for/the/heap"
            ))
        );
        assert_eq!(
            config.command.get_envs().collect::<Vec<_>>(),
            [(
                std::ffi::OsStr::new("A_VARIABLE_NAME_LONG_ENOUGH_FOR_THE_HEAP"),
                Some(std::ffi::OsStr::new(
                    "a variable value long enough for the heap"
                ))
            )]
        );
        assert!(matches!(config.stdin, StdinMode::Bytes(bytes) if bytes == [0, 42, 255]));
        assert_eq!(config.stdout, OutputMode::Tee);
        assert_eq!(config.stderr, StderrMode::MergeWithStdout);
        // Zero is a deadline, not the absence of one.
        assert_eq!(config.timeout, Some(Duration::ZERO));
        assert_eq!(config.output_limit, Some(7));
        assert_eq!(config.pending_limit, 9);
        assert!(config.manage_tree);
        finish(host, 8);
    }

    #[test]
    fn command_config_without_a_deadline_limit_or_directory() {
        let host = host();
        let mut cmd = heap_command(utf8("tool", &host), &host);
        // Release the directory this test replaces.
        unsafe { ManuallyDrop::into_inner(cmd.cwd.payload.dir).decref(&host) };
        cmd.cwd = DirOrInherit {
            tag: DirOrInheritTag::Inherit,
            payload: DirOrInheritPayload { inherit: [] },
        };
        cmd.timeout = AfterNanosOrNoTimeout {
            tag: AfterNanosOrNoTimeoutTag::NoTimeout,
            payload: AfterNanosOrNoTimeoutPayload { no_timeout: [] },
        };
        cmd.output_limit = MaxBytesOrNoLimit {
            tag: MaxBytesOrNoLimitTag::NoLimit,
            payload: MaxBytesOrNoLimitPayload { no_limit: [] },
        };
        cmd.stderr = CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTee {
            tag: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeeTag::Pipe,
            payload: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeePayload { pipe: [] },
        };
        let config = command_config(cmd, &host).unwrap();
        assert_eq!(config.command.get_current_dir(), None);
        assert_eq!(config.timeout, None);
        assert_eq!(config.output_limit, None);
        assert_eq!(config.stderr, StderrMode::Separate(OutputMode::Pipe));
        finish(host, 7);
    }

    #[test]
    fn command_that_cannot_be_converted_still_releases_every_field() {
        let host = host();
        // The other operating system's native representation.
        #[cfg(unix)]
        let foreign = NativeOsStr {
            tag: UnixBytesOrUtf8OrWindowsU16sTag::WindowsU16s,
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                windows_u16s: ManuallyDrop::new(unsafe {
                    RocListWith::<u16, false>::from_slice(&[0xd800, 42], &host)
                }),
            },
        };
        #[cfg(windows)]
        let foreign = NativeOsStr {
            tag: UnixBytesOrUtf8OrWindowsU16sTag::UnixBytes,
            payload: UnixBytesOrUtf8OrWindowsU16sPayload {
                unix_bytes: ManuallyDrop::new(unsafe {
                    RocListWith::<u8, false>::from_slice(&[255, 42], &host)
                }),
            },
        };
        let mut command = heap_command(foreign, &host);
        let file = |path| CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeFile {
            path: utf8(path, &host),
            mode: AppendOrRequireNewOrTruncate::RequireNew,
            create_permissions: DefaultOrOwnerOnlyOrPublicRead::OwnerOnly,
        };
        command.stdout = CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTee {
            tag: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeTag::File,
            payload: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeePayload {
                file: ManuallyDrop::new(file("a stdout pathname needing a heap allocation")),
            },
        };
        command.stderr = CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTee {
            tag: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeeTag::File,
            payload: CaptureOrFileOrInheritOrMergeWithStdoutOrNullOrPipeOrTeePayload {
                file: ManuallyDrop::new(file("a stderr pathname needing a heap allocation")),
            },
        };
        let error = command_config(command, &host)
            .err()
            .expect("a foreign program name must not convert");
        assert_eq!(error.kind(), io::ErrorKind::Unsupported);
        finish(host, 10);
    }

    #[test]
    fn pending_stop_does_not_truncate_a_redirected_file() {
        let host = host();
        let path = std::env::temp_dir().join(format!(
            "roc-cmd-pending-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&path, b"keep this log").unwrap();
        let mut command = heap_command(utf8("some program", &host), &host);
        command.stdout = CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTee {
            tag: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeTag::File,
            payload: CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeePayload {
                file: ManuallyDrop::new(
                    CaptureOrFileOrInheritOrInheritStderrOrNullOrPipeOrTeeFile {
                        path: utf8(path.to_str().unwrap(), &host),
                        mode: AppendOrRequireNewOrTruncate::Truncate,
                        create_permissions: DefaultOrOwnerOnlyOrPublicRead::Default,
                    },
                ),
            },
        };
        crate::signals::set_test_pending(true);
        let result = command_config(command, &host);
        crate::signals::set_test_pending(false);
        assert_eq!(result.err().unwrap().kind(), io::ErrorKind::Interrupted);
        assert_eq!(std::fs::read(&path).unwrap(), b"keep this log");
        std::fs::remove_file(path).unwrap();
        finish(host, 8);
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
