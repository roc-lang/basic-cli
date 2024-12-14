//! This crate provides roc glue to wrap `std::process::Command`
//!
//! ```roc
//! CommandErr : [
//!     ExitCode I32,
//!     KilledBySignal,
//!     IOError Str,
//! ]
//!
//! Command : {
//!     program : Str,
//!     args : List Str, # [arg0, arg1, arg2, arg3, ...]
//!     envs : List Str, # [key0, value0, key1, value1, key2, value2, ...]
//!     clearEnvs : Bool,
//! }
//!
//! Output : {
//!     status : Result {} (List U8),
//!     stdout : List U8,
//!     stderr : List U8,
//! }
//!
//! commandStatus! : Box Command => Result {} (List U8)
//! commandOutput! : Box Command => Output
//! ```

use roc_std::{RocList, RocResult, RocStr};

#[repr(C)]
pub struct Command {
    pub args: RocList<RocStr>,
    pub envs: RocList<RocStr>,
    pub program: RocStr,
    pub clear_envs: bool,
}

#[repr(C)]
pub struct CommandOutput {
    pub status: RocResult<(), RocList<u8>>,
    pub stderr: RocList<u8>,
    pub stdout: RocList<u8>,
}

pub fn command_status(roc_cmd: &Command) -> RocResult<(), RocList<u8>> {
    let args = roc_cmd.args.into_iter().map(|arg| arg.as_str());
    let num_envs = roc_cmd.envs.len() / 2;
    let flat_envs = &roc_cmd.envs;

    // Environment variables must be passed in key=value pairs
    assert_eq!(flat_envs.len() % 2, 0);

    let mut envs = Vec::with_capacity(num_envs);
    for chunk in flat_envs.chunks(2) {
        let key = chunk[0].as_str();
        let value = chunk[1].as_str();
        envs.push((key, value));
    }

    // Create command
    let mut cmd = std::process::Command::new(roc_cmd.program.as_str());

    // Set arguments
    cmd.args(args);

    // Clear environment variables if cmd.clearEnvs set
    // otherwise inherit environment variables if cmd.clearEnvs is not set
    if roc_cmd.clear_envs {
        cmd.env_clear();
    };

    // Set environment variables
    cmd.envs(envs);

    match cmd.status() {
        Ok(status) => {
            if status.success() {
                RocResult::ok(())
            } else {
                match status.code() {
                    Some(code) => error_code(code),
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        killed_by_signal()
                    }
                }
            }
        }
        Err(err) => other_error(err),
    }
}

/// TODO replace with glue instead of using a `List U8` for the errors
/// this is currently a temporary solution for incorrect C ABI with small types
/// we consider using a `List U8` acceptable here as calls to command
/// should be infrequent and have negligible affect on performance
fn killed_by_signal() -> RocResult<(), RocList<u8>> {
    let mut error_bytes = Vec::new();
    error_bytes.extend([b'K', b'S']);
    let error = RocList::from(error_bytes.as_slice());
    RocResult::err(error)
}

fn error_code(code: i32) -> RocResult<(), RocList<u8>> {
    let mut error_bytes = Vec::new();
    error_bytes.extend([b'E', b'C']);
    error_bytes.extend(code.to_ne_bytes()); // use NATIVE ENDIANNESS
    let error = RocList::from(error_bytes.as_slice()); //RocList::from([b'E',b'C'].extend(code.to_le_bytes()));
    RocResult::err(error)
}

fn other_error(err: std::io::Error) -> RocResult<(), RocList<u8>> {
    let error = RocList::from(format!("{:?}", err).as_bytes());
    RocResult::err(error)
}

pub fn command_output(roc_cmd: &Command) -> CommandOutput {
    let args = roc_cmd.args.into_iter().map(|arg| arg.as_str());
    let num_envs = roc_cmd.envs.len() / 2;
    let flat_envs = &roc_cmd.envs;

    // Environment vairables must be passed in key=value pairs
    assert_eq!(flat_envs.len() % 2, 0);

    let mut envs = Vec::with_capacity(num_envs);
    for chunk in flat_envs.chunks(2) {
        let key = chunk[0].as_str();
        let value = chunk[1].as_str();
        envs.push((key, value));
    }

    // Create command
    let mut cmd = std::process::Command::new(roc_cmd.program.as_str());

    // Set arguments
    cmd.args(args);

    // Clear environment variables if cmd.clearEnvs set
    // otherwise inherit environment variables if cmd.clearEnvs is not set
    if roc_cmd.clear_envs {
        cmd.env_clear();
    };

    // Set environment variables
    cmd.envs(envs);

    match cmd.output() {
        Ok(output) => {
            // Status of the child process, successful/exit code/killed by signal
            let status = if output.status.success() {
                RocResult::ok(())
            } else {
                match output.status.code() {
                    Some(code) => error_code(code),
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        killed_by_signal()
                    }
                }
            };

            CommandOutput {
                status,
                stdout: RocList::from(&output.stdout[..]),
                stderr: RocList::from(&output.stderr[..]),
            }
        }
        Err(err) => CommandOutput {
            status: other_error(err),
            stdout: RocList::empty(),
            stderr: RocList::empty(),
        },
    }
}
