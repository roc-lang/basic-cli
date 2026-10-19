//! The native console follows Rust's standard-stream UTF-8 conversion, while
//! redirected handles carry unchanged bytes. No Rust global stream lock is used.
use super::Stream;
use std::io;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, SetLastError, ERROR_INVALID_HANDLE, ERROR_OPERATION_ABORTED,
    GENERIC_READ, HANDLE, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, ReadFile, WriteFile, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
};
use windows_sys::Win32::System::Console::{
    GetConsoleMode, GetConsoleOutputCP, GetStdHandle, ReadConsoleW, WriteConsoleW,
    CONSOLE_READCONSOLE_CONTROL, STD_ERROR_HANDLE, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE,
};
use windows_sys::Win32::System::Threading::{GetCurrentThreadId, OpenThread, THREAD_TERMINATE};
use windows_sys::Win32::System::IO::CancelSynchronousIo;

pub fn prepare() -> io::Result<()> {
    Ok(())
}
pub fn rollback() {}
pub fn thread() -> io::Result<usize> {
    // Dedicated workers live for the life of the process, as does this handle.
    let thread = unsafe { OpenThread(THREAD_TERMINATE, 0, GetCurrentThreadId()) };
    if thread.is_null() {
        Err(io::Error::last_os_error())
    } else {
        Ok(thread as usize)
    }
}
pub fn cancel(thread: usize) {
    unsafe {
        CancelSynchronousIo(thread as HANDLE);
    }
}

fn handle(which: u32) -> io::Result<HANDLE> {
    let handle = unsafe { GetStdHandle(which) };
    if handle.is_null() || handle == INVALID_HANDLE_VALUE {
        Err(io::Error::from_raw_os_error(ERROR_INVALID_HANDLE as i32))
    } else {
        Ok(handle)
    }
}
fn console(handle: HANDLE) -> bool {
    let mut mode = 0;
    unsafe { GetConsoleMode(handle, &mut mode) != 0 }
}
fn invalid_utf8() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        "Windows console output requires UTF-8",
    )
}
fn cancelled(token: &AtomicBool) -> io::Result<()> {
    if token.load(Ordering::Acquire) {
        Err(io::ErrorKind::Interrupted.into())
    } else {
        Ok(())
    }
}
fn native_error(token: &AtomicBool) -> io::Error {
    error_from_code(unsafe { GetLastError() }, token)
}
fn error_from_code(error: u32, token: &AtomicBool) -> io::Error {
    // Cancellation can race setup I/O as well as ReadConsole/ReadFile. The
    // native failure is not always ERROR_OPERATION_ABORTED (console setup can
    // report a timeout), but our request's cancellation still wins.
    if error == ERROR_OPERATION_ABORTED || token.load(Ordering::Acquire) {
        io::ErrorKind::Interrupted.into()
    } else {
        io::Error::from_raw_os_error(error as i32)
    }
}

#[derive(Default)]
pub struct Output {
    incomplete: Vec<u8>,
}
impl Output {
    pub fn cancel(&mut self) {
        self.incomplete.clear();
    }
    pub fn write(&mut self, stream: Stream, bytes: &[u8], token: &AtomicBool) -> io::Result<usize> {
        cancelled(token)?;
        let which = match stream {
            Stream::Stdout => STD_OUTPUT_HANDLE,
            Stream::Stderr => STD_ERROR_HANDLE,
        };
        let handle = match handle(which) {
            Ok(handle) => handle,
            Err(error) if error.raw_os_error() == Some(ERROR_INVALID_HANDLE as i32) => {
                return Ok(bytes.len())
            }
            Err(error) => return Err(error),
        };
        if !console(handle) || unsafe { GetConsoleOutputCP() } == 65001 {
            let mut written = 0;
            if unsafe {
                WriteFile(
                    handle,
                    bytes.as_ptr(),
                    bytes.len() as u32,
                    &mut written,
                    ptr::null_mut(),
                )
            } == 0
            {
                return Err(native_error(token));
            }
            return Ok(written as usize);
        }
        // Preserve successful byte writes that split a UTF-8 scalar across calls.
        let previous = self.incomplete.len();
        let mut combined = std::mem::take(&mut self.incomplete);
        combined.extend_from_slice(bytes);
        let (valid, incomplete) = match std::str::from_utf8(&combined) {
            Ok(_) => (combined.len(), false),
            Err(error) => (error.valid_up_to(), error.error_len().is_none()),
        };
        let mut offset = 0;
        while offset < valid {
            cancelled(token)?;
            let text = std::str::from_utf8(&combined[offset..valid]).unwrap();
            let end = text.floor_char_boundary(text.len().min(4096));
            let units: Vec<u16> = text[..end].encode_utf16().collect();
            let mut cursor = 0;
            while cursor < units.len() {
                cancelled(token)?;
                let mut written = 0;
                if unsafe {
                    WriteConsoleW(
                        handle,
                        units[cursor..].as_ptr().cast(),
                        (units.len() - cursor) as u32,
                        &mut written,
                        ptr::null(),
                    )
                } == 0
                {
                    return Err(native_error(token));
                }
                if written == 0 {
                    return Err(io::ErrorKind::WriteZero.into());
                }
                cursor += written as usize;
            }
            offset += end;
        }
        if valid < combined.len() {
            if incomplete {
                self.incomplete.extend_from_slice(&combined[valid..]);
                return Ok(bytes.len());
            }
            // As with stdio, a valid prefix may already have reached the console.
            return if valid > previous {
                Ok(valid - previous)
            } else {
                Err(invalid_utf8())
            };
        }
        Ok(bytes.len())
    }
}

#[derive(Default)]
pub struct Input {
    high: Option<u16>,
    pending: Vec<u8>,
    console: Option<ConsoleInput>,
}

struct ConsoleInput(HANDLE);
impl Drop for ConsoleInput {
    fn drop(&mut self) {
        unsafe { CloseHandle(self.0) };
    }
}
impl Input {
    fn console_handle(&mut self) -> io::Result<HANDLE> {
        if let Some(handle) = &self.console {
            return Ok(handle.0);
        }
        let name: Vec<u16> = "CONIN$\0".encode_utf16().collect();
        let handle = unsafe {
            CreateFileW(
                name.as_ptr(),
                GENERIC_READ,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                ptr::null(),
                OPEN_EXISTING,
                0,
                ptr::null_mut(),
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error());
        }
        self.console = Some(ConsoleInput(handle));
        Ok(handle)
    }

    pub fn read(&mut self, bytes: &mut [u8], token: &AtomicBool) -> io::Result<usize> {
        cancelled(token)?;
        if !self.pending.is_empty() {
            let count = bytes.len().min(self.pending.len());
            bytes[..count].copy_from_slice(&self.pending[..count]);
            self.pending.drain(..count);
            return Ok(count);
        }
        let handle = match handle(STD_INPUT_HANDLE) {
            Ok(handle) => handle,
            Err(error) if error.raw_os_error() == Some(ERROR_INVALID_HANDLE as i32) => {
                return Ok(0)
            }
            Err(error) => return Err(error),
        };
        if !console(handle) {
            let mut count = 0;
            if unsafe {
                ReadFile(
                    handle,
                    bytes.as_mut_ptr(),
                    bytes.len() as u32,
                    &mut count,
                    ptr::null_mut(),
                )
            } == 0
            {
                let error = native_error(token);
                // End of a redirected pipe is EOF, as with Rust's stdin backend.
                if error.raw_os_error() == Some(109) {
                    return Ok(0);
                }
                return Err(error);
            }
            return Ok(count as usize);
        }
        // Console cancellation only completes the client request. A canceled
        // cooked read can otherwise remain in conhost and consume the next
        // line. A separate handle lets us close that server-side read after
        // the native call returns, without closing inherited standard input.
        // Keep it across successful reads: long-line remainder is per handle.
        let handle = match self.console_handle() {
            Ok(handle) => handle,
            Err(error) => {
                cancelled(token)?;
                return Err(error);
            }
        };
        loop {
            cancelled(token)?;
            let mut units = [0u16; 4096];
            let mut count = 0;
            let control = CONSOLE_READCONSOLE_CONTROL {
                nLength: std::mem::size_of::<CONSOLE_READCONSOLE_CONTROL>() as u32,
                nInitialChars: 0,
                dwCtrlWakeupMask: 1 << 0x1a,
                dwControlKeyState: 0,
            };
            let success = unsafe {
                SetLastError(0);
                ReadConsoleW(
                    handle,
                    units.as_mut_ptr().cast(),
                    units.len() as u32,
                    &mut count,
                    &control,
                )
            };
            let error = unsafe { GetLastError() };
            let aborted = error == ERROR_OPERATION_ABORTED || token.load(Ordering::Acquire);
            if aborted {
                // HandleClosing completes both raw and cooked server waits.
                // Closing happens after ReadConsole returns, so the native call
                // never races reuse of a handle closed by another thread.
                self.console.take();
            }
            if success == 0 {
                return Err(error_from_code(error, token));
            }
            if count == 0 && aborted {
                return Err(io::ErrorKind::Interrupted.into());
            }
            let mut units = units[..count as usize].to_vec();
            if units.last() == Some(&0x1a) {
                units.pop();
            }
            let eof = units.is_empty();
            if let Some(high) = self.high.take() {
                units.insert(0, high);
            }
            if units
                .last()
                .is_some_and(|unit| (0xd800..=0xdbff).contains(unit))
            {
                self.high = units.pop();
            }
            let text = String::from_utf16(&units).map_err(|_| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    "Windows console input contains an unpaired surrogate",
                )
            })?;
            self.pending.extend_from_slice(text.as_bytes());
            if aborted {
                return Err(io::ErrorKind::Interrupted.into());
            }
            if !self.pending.is_empty() {
                let count = bytes.len().min(self.pending.len());
                bytes[..count].copy_from_slice(&self.pending[..count]);
                self.pending.drain(..count);
                return Ok(count);
            }
            if eof {
                return Ok(0);
            }
        }
    }
}

#[cfg(test)]
#[path = "windows_tests.rs"]
mod tests;
