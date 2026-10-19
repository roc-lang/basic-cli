//! Isolated real-console tests: cancellation must also finish conhost's read.
use super::*;
use std::io::Read as _;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};
use windows_sys::Win32::Foundation::{GENERIC_WRITE, TRUE};
use windows_sys::Win32::System::Console::{
    AllocConsole, FreeConsole, GenerateConsoleCtrlEvent, SetConsoleMode, SetStdHandle,
    WriteConsoleInputW, CTRL_C_EVENT, ENABLE_ECHO_INPUT, ENABLE_LINE_INPUT, ENABLE_PROCESSED_INPUT,
    INPUT_RECORD, INPUT_RECORD_0, KEY_EVENT, KEY_EVENT_RECORD, KEY_EVENT_RECORD_0,
};
use windows_sys::Win32::System::Threading::{GetThreadIOPendingFlag, THREAD_QUERY_INFORMATION};

const CHILD_MODE: &str = "BASIC_CLI_NATIVE_CONSOLE_TEST";
const LIMIT: Duration = Duration::from_secs(8);

#[test]
fn canceled_requests_normalize_other_native_failures_without_hiding_uncanceled_errors() {
    use windows_sys::Win32::Foundation::ERROR_TIMEOUT;

    let token = AtomicBool::new(false);
    assert_eq!(
        error_from_code(ERROR_TIMEOUT, &token).kind(),
        io::ErrorKind::TimedOut
    );
    token.store(true, Ordering::Release);
    assert_eq!(
        error_from_code(ERROR_TIMEOUT, &token).kind(),
        io::ErrorKind::Interrupted
    );
}

fn open_console(name: &str) -> ConsoleInput {
    let name: Vec<u16> = name.encode_utf16().chain([0]).collect();
    let handle = unsafe {
        CreateFileW(
            name.as_ptr(),
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            ptr::null(),
            OPEN_EXISTING,
            0,
            ptr::null_mut(),
        )
    };
    assert_ne!(
        handle,
        INVALID_HANDLE_VALUE,
        "{}",
        io::Error::last_os_error()
    );
    ConsoleInput(handle)
}

fn input(handle: HANDLE, text: &str) {
    let records: Vec<_> = text
        .encode_utf16()
        .map(|unit| INPUT_RECORD {
            EventType: KEY_EVENT as u16,
            Event: INPUT_RECORD_0 {
                KeyEvent: KEY_EVENT_RECORD {
                    bKeyDown: TRUE,
                    wRepeatCount: 1,
                    wVirtualKeyCode: if unit == 13 { 13 } else { 0 },
                    wVirtualScanCode: 0,
                    uChar: KEY_EVENT_RECORD_0 { UnicodeChar: unit },
                    dwControlKeyState: 0,
                },
            },
        })
        .collect();
    let mut count = 0;
    assert_ne!(
        unsafe { WriteConsoleInputW(handle, records.as_ptr(), records.len() as u32, &mut count) },
        0,
        "{}",
        io::Error::last_os_error()
    );
    assert_eq!(count as usize, records.len());
}

fn console_child(mode: &str) {
    eprintln!("{mode}: allocating isolated console");
    // Never broadcast Ctrl-C into the parent test runner's console.
    unsafe { FreeConsole() };
    assert_ne!(
        unsafe { AllocConsole() },
        0,
        "{}",
        io::Error::last_os_error()
    );
    let stdin = open_console("CONIN$");
    let stdout = open_console("CONOUT$");
    assert_ne!(unsafe { SetStdHandle(STD_INPUT_HANDLE, stdin.0) }, 0);
    assert_ne!(unsafe { SetStdHandle(STD_OUTPUT_HANDLE, stdout.0) }, 0);
    let mut flags = 0;
    assert_ne!(unsafe { GetConsoleMode(stdin.0, &mut flags) }, 0);
    flags &= !ENABLE_ECHO_INPUT;
    if mode.ends_with("raw") {
        flags &= !(ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT);
    } else {
        flags |= ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT;
    }
    assert_ne!(unsafe { SetConsoleMode(stdin.0, flags) }, 0);

    let signal = mode.starts_with("interrupt");
    if signal {
        crate::signals::catch(crate::signals::INTERRUPT).unwrap();
    }
    let token = Arc::new(AtomicBool::new(false));
    let cancellation = token.clone();
    let (ready, worker_ready) = mpsc::channel();
    let (acknowledged, acknowledgement) = mpsc::channel();
    let (release, released) = mpsc::channel();
    let (recovered, recovery) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        let thread = thread().unwrap();
        let mut native = Input::default();
        // CONIN$ setup is itself synchronous I/O. Complete it before publishing
        // readiness, so GetThreadIOPendingFlag observes the read we mean to
        // cancel rather than an unrelated handle-open request.
        native.console_handle().unwrap();
        ready
            .send((thread, unsafe { GetCurrentThreadId() }))
            .unwrap();
        let mut bytes = [0u8; 8192];
        let error = native.read(&mut bytes, &cancellation).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted, "{error:?}");
        eprintln!("console worker: cancellation acknowledged");
        acknowledged.send(()).unwrap();
        released.recv_timeout(LIMIT).unwrap();
        cancellation.store(false, Ordering::Release);
        let mut next = Vec::new();
        while !next.ends_with(b"\n") && !next.ends_with(b"\r") {
            let count = native.read(&mut bytes, &cancellation).unwrap();
            assert_ne!(count, 0);
            eprintln!("console worker: recovered {} bytes", count);
            next.extend_from_slice(&bytes[..count]);
        }
        assert_eq!(
            String::from_utf8(next).unwrap().trim_end(),
            "after cancellation"
        );
        unsafe { CloseHandle(thread as HANDLE) };
        recovered.send(()).unwrap();
    });
    let (thread, id) = worker_ready.recv_timeout(LIMIT).unwrap();
    let query = ConsoleInput(unsafe { OpenThread(THREAD_QUERY_INFORMATION, 0, id) });
    assert!(!query.0.is_null(), "{}", io::Error::last_os_error());
    let started = Instant::now();
    loop {
        let mut pending = 0;
        assert_ne!(unsafe { GetThreadIOPendingFlag(query.0, &mut pending) }, 0);
        if pending != 0 {
            break;
        }
        assert!(started.elapsed() < LIMIT, "console read did not start");
        std::thread::sleep(Duration::from_millis(10));
    }
    if signal {
        assert_ne!(unsafe { GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0) }, 0);
    }
    eprintln!("{mode}: native read pending; requesting cancellation");
    loop {
        if !signal || crate::signals::is_pending() {
            token.store(true, Ordering::Release);
            cancel(thread);
        }
        match acknowledgement.recv_timeout(Duration::from_millis(10)) {
            Ok(()) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                assert!(
                    started.elapsed() < LIMIT,
                    "console cancellation did not finish"
                );
            }
            Err(error) => panic!("console reader failed: {error}"),
        }
    }
    if signal {
        assert_eq!(crate::signals::poll(), crate::signals::INTERRUPT);
    }
    eprintln!("{mode}: cancellation completed; queueing recovery input");
    input(stdin.0, "after cancellation\r");
    release.send(()).unwrap();
    recovery
        .recv_timeout(LIMIT)
        .unwrap_or_else(|error| panic!("{mode}: console recovery did not finish: {error}"));
    worker.join().unwrap();
    eprintln!("console cancellation case completed: {mode}");
}

#[test]
fn console_cancellation_releases_raw_and_cooked_reads_without_consuming_the_next_line() {
    if let Ok(mode) = std::env::var(CHILD_MODE) {
        console_child(&mode);
        return;
    }
    for mode in [
        "cancel-cooked",
        "interrupt-cooked",
        "cancel-raw",
        "interrupt-raw",
    ] {
        let test = format!(
            "{}::console_cancellation_releases_raw_and_cooked_reads_without_consuming_the_next_line",
            module_path!().split_once("::").unwrap().1,
        );
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", &test, "--nocapture"])
            .env(CHILD_MODE, mode)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let started = Instant::now();
        // Drain while the child runs: a panic's diagnostic can exceed the
        // Windows anonymous pipe buffer and otherwise prevent child exit.
        let mut stderr = child.stderr.take().unwrap();
        let diagnostic = std::thread::spawn(move || {
            let mut diagnostic = String::new();
            stderr.read_to_string(&mut diagnostic).unwrap();
            diagnostic
        });
        let mut timed_out = false;
        let status = loop {
            if let Some(status) = child.try_wait().unwrap() {
                break status;
            }
            if started.elapsed() > LIMIT * 2 {
                let _ = child.kill();
                timed_out = true;
                break child.wait().unwrap();
            }
            std::thread::sleep(Duration::from_millis(10));
        };
        let diagnostic = diagnostic.join().unwrap();
        assert!(
            !timed_out,
            "{mode}: console cancellation helper timed out\n{diagnostic}"
        );
        assert!(status.success(), "{mode}: {status}\n{diagnostic}");
        assert!(
            diagnostic.contains(&format!("console cancellation case completed: {mode}")),
            "{mode}: console helper did not execute\n{diagnostic}",
        );
    }
}
