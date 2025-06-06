//! This crate provides common functionality for Roc to interface with `std::process::Command`
use roc_std::{RocList, RocResult, RocStr};

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Command {
    pub args: RocList<RocStr>,
    pub envs: RocList<RocStr>,
    pub program: RocStr,
    pub clear_envs: bool,
}

impl roc_std::RocRefcounted for Command {
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

impl From<&Command> for std::process::Command {
    fn from(roc_cmd: &Command) -> Self {
        let args = roc_cmd.args.into_iter().map(|arg| arg.as_str());
        let num_envs = roc_cmd.envs.len() / 2;
        let flat_envs = &roc_cmd.envs;

        // Environment variables must be passed in key=value pairs
        debug_assert_eq!(flat_envs.len() % 2, 0);

        let mut envs = Vec::with_capacity(num_envs);
        for chunk in flat_envs.chunks(2) {
            let key = chunk[0].as_str();
            let value = chunk[1].as_str();
            envs.push((key, value));
        }

        let mut cmd = std::process::Command::new(roc_cmd.program.as_str());

        // Set arguments
        cmd.args(args);

        // Clear environment variables
        if roc_cmd.clear_envs {
            cmd.env_clear();
        };

        // Set environment variables
        cmd.envs(envs);

        cmd
    }
}

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct OutputFromHost {
    pub status: roc_std::RocResult<i32, roc_io_error::IOErr>,
    pub stderr: roc_std::RocList<u8>,
    pub stdout: roc_std::RocList<u8>,
}

impl roc_std::RocRefcounted for OutputFromHost {
    fn inc(&mut self) {
        self.status.inc();
        self.stderr.inc();
        self.stdout.inc();
    }
    fn dec(&mut self) {
        self.status.dec();
        self.stderr.dec();
        self.stdout.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

pub fn command_status(roc_cmd: &Command) -> RocResult<i32, roc_io_error::IOErr> {
    match std::process::Command::from(roc_cmd).status() {
        Ok(status) => from_exit_status(status),
        Err(err) => RocResult::err(err.into()),
    }
}

// Status of the child process, successful/exit code/killed by signal
fn from_exit_status(status: std::process::ExitStatus) -> RocResult<i32, roc_io_error::IOErr> {
    match status.code() {
        Some(code) => RocResult::ok(code),
        None => killed_by_signal(),
    }
}

// If no exit code is returned, the process was terminated by a signal.
fn killed_by_signal() -> RocResult<i32, roc_io_error::IOErr> {
    RocResult::err(roc_io_error::IOErr {
        tag: roc_io_error::IOErrTag::Other,
        msg: "Killed by signal".into(),
    })
}

pub fn command_output(roc_cmd: &Command) -> OutputFromHost {
    match std::process::Command::from(roc_cmd).output() {
        Ok(output) => OutputFromHost {
            status: from_exit_status(output.status),
            stdout: RocList::from(&output.stdout[..]),
            stderr: RocList::from(&output.stderr[..]),
        },
        Err(err) => OutputFromHost {
            status: RocResult::err(err.into()),
            stdout: RocList::empty(),
            stderr: RocList::empty(),
        },
    }
}
