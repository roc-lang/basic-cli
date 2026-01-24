//! This crate provides common functionality for Roc to interface with `std::process::Command`

use roc_io_error::IOErr;
use roc_std_new::{RocList, RocOps, RocRefcounted, RocStr};

/// Command struct matching the Roc record memory layout.
///
/// IMPORTANT: Roc optimizes struct layouts by putting larger fields first!
/// The type signature is `{ args, clear_envs, envs, program }` (alphabetical),
/// but the MEMORY layout is: args (24), envs (24), program (24), clear_envs (1).
#[derive(Clone, Debug)]
#[repr(C)]
pub struct Command {
    pub args: RocList<RocStr>,    // offset 0 (24 bytes)
    pub envs: RocList<RocStr>,    // offset 24 (24 bytes)
    pub program: RocStr,          // offset 48 (24 bytes)
    pub clear_envs: u8,           // offset 72 (1 byte + 7 padding = 80 total)
}

impl RocRefcounted for Command {
    fn inc(&mut self) {
        self.args.inc();
        self.envs.inc();
        self.program.inc();
    }
    fn dec(&mut self) {
        self.args.dec();
        self.envs.dec();
        self.program.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl Command {
    /// Convert to std::process::Command
    pub fn to_std_command(&self) -> std::process::Command {
        let mut cmd = std::process::Command::new(self.program.as_str());

        // Add arguments
        for arg in self.args.iter() {
            cmd.arg(arg.as_str());
        }

        // Clear environment if requested
        if self.clear_envs != 0 {
            cmd.env_clear();
        }

        // Add environment variables (key-value pairs in flat list)
        // Format: [key0, value0, key1, value1, ...]
        let env_slice = self.envs.as_slice();
        for chunk in env_slice.chunks(2) {
            if chunk.len() == 2 {
                cmd.env(chunk[0].as_str(), chunk[1].as_str());
            }
        }

        cmd
    }
}

/// Output when command succeeds (exit code 0)
/// Roc type: { stdout_utf8 : Str, stderr_utf8_lossy : Str }
/// Memory layout: Fields sorted by size descending, then alphabetically.
/// Both RocStr are 24 bytes, so alphabetical: stderr_utf8_lossy, stdout_utf8
#[derive(Clone, Debug)]
#[repr(C)]
pub struct CommandOutputSuccess {
    pub stderr_utf8_lossy: RocStr,  // offset 0 (24 bytes)
    pub stdout_utf8: RocStr,        // offset 24 (24 bytes)
}

impl RocRefcounted for CommandOutputSuccess {
    fn inc(&mut self) {
        self.stderr_utf8_lossy.inc();
        self.stdout_utf8.inc();
    }
    fn dec(&mut self) {
        self.stderr_utf8_lossy.dec();
        self.stdout_utf8.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

/// Output when command fails (non-zero exit code)
/// Roc type: { exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str }
/// Memory layout: Fields sorted by size descending, then alphabetically.
/// RocStr (24 bytes) > I32 (4 bytes), so: stderr_utf8_lossy (24), stdout_utf8_lossy (24), exit_code (4)
#[derive(Clone, Debug)]
#[repr(C)]
pub struct CommandOutputFailure {
    pub stderr_utf8_lossy: RocStr,   // offset 0 (24 bytes)
    pub stdout_utf8_lossy: RocStr,   // offset 24 (24 bytes)
    pub exit_code: i32,              // offset 48 (4 bytes + padding)
}

impl RocRefcounted for CommandOutputFailure {
    fn inc(&mut self) {
        self.stderr_utf8_lossy.inc();
        self.stdout_utf8_lossy.inc();
    }
    fn dec(&mut self) {
        self.stderr_utf8_lossy.dec();
        self.stdout_utf8_lossy.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

/// Convert bytes to RocStr using lossy UTF-8 conversion.
/// Invalid UTF-8 sequences are replaced with the Unicode replacement character (U+FFFD).
fn bytes_to_roc_str_lossy(bytes: &[u8], roc_ops: &RocOps) -> RocStr {
    let s = String::from_utf8_lossy(bytes);
    RocStr::from_str(s.as_ref(), roc_ops)
}

/// Result of executing a command for output
pub enum CommandOutputResult {
    /// Command succeeded with exit code 0
    Success(CommandOutputSuccess),
    /// Command failed with non-zero exit code
    NonZeroExit(CommandOutputFailure),
    /// Command failed to execute
    Error(IOErr),
}

/// Execute command and return exit code
pub fn command_exec_exit_code(cmd: &Command, roc_ops: &RocOps) -> Result<i32, IOErr> {
    match cmd.to_std_command().status() {
        Ok(status) => match status.code() {
            Some(code) => Ok(code),
            None => Err(IOErr::new_other("Process was killed by signal", roc_ops)),
        },
        Err(e) => Err(IOErr::from_io_error(&e, roc_ops)),
    }
}

/// Execute command and capture stdout/stderr as UTF-8 strings.
/// Invalid UTF-8 sequences are replaced with the Unicode replacement character.
pub fn command_exec_output(cmd: &Command, roc_ops: &RocOps) -> CommandOutputResult {
    match cmd.to_std_command().output() {
        Ok(output) => {
            let stdout_utf8 = bytes_to_roc_str_lossy(&output.stdout, roc_ops);
            let stderr_utf8_lossy = bytes_to_roc_str_lossy(&output.stderr, roc_ops);

            match output.status.code() {
                Some(0) => CommandOutputResult::Success(CommandOutputSuccess {
                    stderr_utf8_lossy,
                    stdout_utf8,
                }),
                Some(exit_code) => CommandOutputResult::NonZeroExit(CommandOutputFailure {
                    stderr_utf8_lossy,
                    stdout_utf8_lossy: stdout_utf8,
                    exit_code,
                }),
                None => CommandOutputResult::Error(
                    IOErr::new_other("Process was killed by signal", roc_ops)
                ),
            }
        }
        Err(e) => CommandOutputResult::Error(IOErr::from_io_error(&e, roc_ops)),
    }
}
