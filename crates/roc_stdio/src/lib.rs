//! This crate provides common functionality for Roc to interface with `std::io`
use roc_std::{RocList, RocResult, RocStr};
use std::io::{BufRead, Read, Write};

/// stdinLine! : {} => Result Str IOErr
pub fn stdin_line() -> RocResult<RocStr, roc_io_error::IOErr> {
    let stdin = std::io::stdin();

    match stdin.lock().lines().next() {
        None => RocResult::err(roc_io_error::IOErr {
            msg: RocStr::empty(),
            tag: roc_io_error::IOErrTag::EndOfFile,
        }),
        Some(Ok(str)) => RocResult::ok(str.as_str().into()),
        Some(Err(io_err)) => RocResult::err(io_err.into()),
    }
}

/// stdinBytes! : {} => Result (List U8) IOErr
pub fn stdin_bytes() -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    const BUF_SIZE: usize = 16_384; // 16 KiB = 16 * 1024 = 16,384 bytes
    let stdin = std::io::stdin();
    let mut buffer: [u8; BUF_SIZE] = [0; BUF_SIZE];

    match stdin.lock().read(&mut buffer) {
        Ok(bytes_read) => RocResult::ok(RocList::from(&buffer[0..bytes_read])),
        Err(io_err) => RocResult::err(io_err.into()),
    }
}

/// stdinReadToEnd! : {} => Result (List U8) IOErr
pub fn stdin_read_to_end() -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    let stdin = std::io::stdin();
    let mut buf = Vec::new();
    match stdin.lock().read_to_end(&mut buf) {
        Ok(bytes_read) => RocResult::ok(RocList::from(&buf[0..bytes_read])),
        Err(io_err) => RocResult::err(io_err.into()),
    }
}

/// stdoutLine! : Str => Result {} IOErr
pub fn stdout_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

/// stdoutWrite! : Str => Result {} IOErr
pub fn stdout_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    let stdout = std::io::stdout();
    let mut handle = stdout.lock();

    handle
        .write_all(text.as_bytes())
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

pub fn stdout_write_bytes(bytes: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    let stdout = std::io::stdout();
    let mut handle = stdout.lock();

    handle
        .write_all(bytes.as_slice())
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

/// stderrLine! : Str => Result {} IOErr
pub fn stderr_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    let stderr = std::io::stderr();
    let mut handle = stderr.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

/// stderrWrite! : Str => Result {} IOErr
pub fn stderr_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    let stderr = std::io::stderr();
    let mut handle = stderr.lock();

    handle
        .write_all(text.as_bytes())
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

pub fn stderr_write_bytes(bytes: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    let stderr = std::io::stderr();
    let mut handle = stderr.lock();

    handle
        .write_all(bytes.as_slice())
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}
