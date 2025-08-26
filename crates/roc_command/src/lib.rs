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
pub struct OutputFromHostSuccess {
    pub stderr_bytes: roc_std::RocList<u8>,
    pub stdout_bytes: roc_std::RocList<u8>,
}

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct OutputFromHostFailure {
    pub stderr_bytes: roc_std::RocList<u8>,
    pub stdout_bytes: roc_std::RocList<u8>,
    pub exit_code: i32,
}

impl roc_std::RocRefcounted for OutputFromHostSuccess {
    fn inc(&mut self) {
        self.stdout_bytes.inc();
        self.stderr_bytes.inc();
    }
    fn dec(&mut self) {
        self.stdout_bytes.dec();
        self.stderr_bytes.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl roc_std::RocRefcounted for OutputFromHostFailure {
    fn inc(&mut self) {
        self.exit_code.inc();
        self.stdout_bytes.inc();
        self.stderr_bytes.inc();
    }
    fn dec(&mut self) {
        self.exit_code.dec();
        self.stdout_bytes.dec();
        self.stderr_bytes.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

pub fn command_exec_exit_code(roc_cmd: &Command) -> RocResult<i32, roc_io_error::IOErr> {
    match std::process::Command::from(roc_cmd).status() {
        Ok(status) => from_exit_status(status),
        Err(err) => RocResult::err(err.into()),
    }
}

// Status of the child process, successful/exit code/killed by signal
fn from_exit_status(status: std::process::ExitStatus) -> RocResult<i32, roc_io_error::IOErr> {
    match status.code() {
        Some(code) => RocResult::ok(code),
        None => RocResult::err(killed_by_signal_err()),
    }
}

fn killed_by_signal_err() -> roc_io_error::IOErr {
    roc_io_error::IOErr {
        tag: roc_io_error::IOErrTag::Other,
        msg: "Process was killed by operating system signal.".into(),
    }
}

// TODO Can we make this return a tag union (with three variants) ?
pub fn command_exec_output(roc_cmd: &Command) -> RocResult<OutputFromHostSuccess, RocResult<OutputFromHostFailure, roc_io_error::IOErr>> {
    match std::process::Command::from(roc_cmd).output() {
        Ok(output) =>
            match output.status.code() {
                Some(status) => {

                    let stdout_bytes = RocList::from(&output.stdout[..]);
                    let stderr_bytes = RocList::from(&output.stderr[..]);

                    if status == 0 {
                        // Success case
                        RocResult::ok(OutputFromHostSuccess {
                            stderr_bytes,
                            stdout_bytes,
                        })
                    } else {
                        // Failure case
                        RocResult::err(RocResult::ok(OutputFromHostFailure {
                            stderr_bytes,
                            stdout_bytes,
                            exit_code: status,
                        }))
                    }
                },
                None => RocResult::err(RocResult::err(killed_by_signal_err()))
            }
        Err(err) => RocResult::err(RocResult::err(err.into()))
    }
}
