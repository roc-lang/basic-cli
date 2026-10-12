//! Terminal raw mode, with host-side tracking of whether the host enabled it.
//!
//! The host only reverts a mode it enabled itself. `restore` is the cleanup
//! entry point for every path on which the app stops running.

use std::io;
use std::sync::{Mutex, TryLockError};

use crossterm::terminal;

/// Whether the host currently holds the terminal in raw mode.
struct RawMode {
    enabled: bool,
}

impl RawMode {
    const fn new() -> Self {
        Self { enabled: false }
    }

    /// Idempotent: a second enable must not overwrite the mode saved by the first.
    fn enable(&mut self, enable: impl FnOnce() -> io::Result<()>) -> io::Result<()> {
        if !self.enabled {
            enable()?;
            self.enabled = true;
        }
        Ok(())
    }

    /// Stays enabled when the terminal rejects the change, so cleanup retries.
    fn disable(&mut self, disable: impl FnOnce() -> io::Result<()>) -> io::Result<()> {
        if self.enabled {
            disable()?;
            self.enabled = false;
        }
        Ok(())
    }
}

static RAW_MODE: Mutex<RawMode> = Mutex::new(RawMode::new());

pub(crate) fn enable_raw_mode() -> io::Result<()> {
    RAW_MODE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .enable(terminal::enable_raw_mode)
}

pub(crate) fn disable_raw_mode() -> io::Result<()> {
    RAW_MODE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .disable(terminal::disable_raw_mode)
}

/// Best-effort cleanup for when the app stops running. There is nobody left to
/// report a failure to, and this must not block a process that is going down.
pub(crate) fn restore() {
    let mut raw_mode = match RAW_MODE.try_lock() {
        Ok(raw_mode) => raw_mode,
        Err(TryLockError::Poisoned(poisoned)) => poisoned.into_inner(),
        Err(TryLockError::WouldBlock) => return,
    };
    let _ = raw_mode.disable(terminal::disable_raw_mode);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn rejected() -> io::Result<()> {
        Err(io::Error::from(io::ErrorKind::PermissionDenied))
    }

    #[test]
    fn repeated_enables_change_the_terminal_once() {
        let calls = Cell::new(0);
        let count = || {
            calls.set(calls.get() + 1);
            Ok(())
        };
        let mut raw_mode = RawMode::new();

        raw_mode.enable(count).unwrap();
        raw_mode.enable(count).unwrap();

        assert_eq!(calls.get(), 1);
    }

    #[test]
    fn disable_leaves_a_mode_the_host_did_not_enable() {
        let mut raw_mode = RawMode::new();

        raw_mode
            .disable(|| panic!("reverted a mode the host never enabled"))
            .unwrap();
    }

    #[test]
    fn one_disable_reverts_any_number_of_enables() {
        let calls = Cell::new(0);
        let count = || {
            calls.set(calls.get() + 1);
            Ok(())
        };
        let mut raw_mode = RawMode::new();
        raw_mode.enable(|| Ok(())).unwrap();
        raw_mode.enable(|| Ok(())).unwrap();

        raw_mode.disable(count).unwrap();
        raw_mode.disable(count).unwrap();

        assert_eq!(calls.get(), 1);
    }

    #[test]
    fn rejected_enable_leaves_nothing_to_revert() {
        let mut raw_mode = RawMode::new();

        assert!(raw_mode.enable(rejected).is_err());

        raw_mode
            .disable(|| panic!("reverted a mode that was never enabled"))
            .unwrap();
    }

    #[test]
    fn rejected_disable_is_retried() {
        let mut raw_mode = RawMode::new();
        raw_mode.enable(|| Ok(())).unwrap();

        assert!(raw_mode.disable(rejected).is_err());

        let retried = Cell::new(false);
        raw_mode
            .disable(|| {
                retried.set(true);
                Ok(())
            })
            .unwrap();
        assert!(retried.get());
    }
}
