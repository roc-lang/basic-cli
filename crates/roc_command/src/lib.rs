//! This crate provides common functionality for Roc to interface with `std::process::Command`

use roc_io_error::IOErr;
use roc_std_new::{RocList, RocOps, RocRefcounted, RocStr, RocTry};

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
/// Roc type: {stderr_bytes : List(U8), stdout_bytes : List(U8) }
/// Memory layout: Fields sorted by size descending, then alphabetically.
/// Both RocList are 24 bytes, so alphabetical: stderr_bytes, stdout_bytes
#[derive(Clone, Debug)]
#[repr(C)]
pub struct CommandOutputSuccess {
    pub stderr_bytes: RocList<u8>,  // offset 0 (24 bytes)
    pub stdout_bytes: RocList<u8>,  // offset 24 (24 bytes)
}

impl RocRefcounted for CommandOutputSuccess {
    fn inc(&mut self) {
        self.stderr_bytes.inc();
        self.stdout_bytes.inc();
    }
    fn dec(&mut self) {
        self.stderr_bytes.dec();
        self.stdout_bytes.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

/// Output when command fails with non-zero exit code
/// Roc type: {stderr_bytes : List(U8), stdout_bytes : List(U8), exit_code: I32 }
/// Memory layout: Fields sorted by size descending, then alphabetically.
/// RocList (24 bytes) > I32 (4 bytes), so: stderr_bytes (24), stdout_bytes (24), exit_code (4)
#[derive(Clone, Debug)]
#[repr(C)]
pub struct CommandOutputFailure {
    pub stderr_bytes: RocList<u8>,  // offset 0 (24 bytes)
    pub stdout_bytes: RocList<u8>,  // offset 24 (24 bytes)
    pub exit_code: i32,              // offset 48 (4 bytes + padding)
}

impl RocRefcounted for CommandOutputFailure {
    fn inc(&mut self) {
        self.stderr_bytes.inc();
        self.stdout_bytes.inc();
    }
    fn dec(&mut self) {
        self.stderr_bytes.dec();
        self.stdout_bytes.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
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

pub type CommandOutputTry = RocTry<CommandOutputSuccess, RocTry<CommandOutputFailure, IOErr>>;

/// Execute command and capture stdout/stderr as UTF-8 strings.
/// Invalid UTF-8 sequences are replaced with the Unicode replacement character.
pub fn command_exec_output(cmd: &Command, roc_ops: &RocOps) -> CommandOutputTry {
    match cmd.to_std_command().output() {
        Ok(output) => {
            let stdout_bytes = RocList::from_slice(&output.stdout, roc_ops);
            let stderr_bytes = RocList::from_slice(&output.stderr, roc_ops);

            match output.status.code() {
                Some(0) => RocTry::ok(CommandOutputSuccess {
                    stderr_bytes,
                    stdout_bytes,
                }),
                Some(exit_code) => RocTry::err(RocTry::ok(CommandOutputFailure {
                    stderr_bytes,
                    stdout_bytes,
                    exit_code,
                })),
                None => RocTry::err(RocTry::err(
                    IOErr::new_other("Process was killed by signal", roc_ops)
                )),
            }
        }
        Err(e) => RocTry::err(RocTry::err(IOErr::from_io_error(&e, roc_ops))),
    }
}
