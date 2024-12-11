//! Implementation of the host.
//! The host contains code that calls the Roc main function and provides the
//! Roc app with functions to allocate memory and execute effects such as
//! writing to stdio or making HTTP requests.

#![allow(non_snake_case)]
#![allow(improper_ctypes)]
use core::ffi::c_void;
use roc_std::{RocBox, RocList, RocResult, RocStr, ReadOnlyRocList, ReadOnlyRocStr};
use roc_std_heap::ThreadSafeRefcountedResourceHeap;
use std::borrow::{Borrow, Cow};
use std::ffi::OsStr;
use std::fs::File;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::{env, io};
use tokio::runtime::Runtime;

mod glue;

thread_local! {
   static TOKIO_RUNTIME: Runtime = tokio::runtime::Builder::new_current_thread()
       .enable_io()
       .enable_time()
       .build()
       .unwrap();
}

static ARGS : OnceLock<ReadOnlyRocList<ReadOnlyRocStr>> = OnceLock::new();

fn file_heap() -> &'static ThreadSafeRefcountedResourceHeap<BufReader<File>> {
    static FILE_HEAP: OnceLock<ThreadSafeRefcountedResourceHeap<BufReader<File>>> = OnceLock::new();
    FILE_HEAP.get_or_init(|| {
        let DEFAULT_MAX_FILES = 65536;
        let max_files = env::var("ROC_BASIC_CLI_MAX_FILES")
            .map(|v| v.parse().unwrap_or(DEFAULT_MAX_FILES))
            .unwrap_or(DEFAULT_MAX_FILES);
        ThreadSafeRefcountedResourceHeap::new(max_files)
            .expect("Failed to allocate mmap for file handle references.")
    })
}

fn tcp_heap() -> &'static ThreadSafeRefcountedResourceHeap<BufReader<TcpStream>> {
    // TODO: Should this be a BufReader and BufWriter of the tcp stream?
    // like this: https://stackoverflow.com/questions/58467659/how-to-store-tcpstream-with-bufreader-and-bufwriter-in-a-data-structure/58491889#58491889

    static TCP_HEAP: OnceLock<ThreadSafeRefcountedResourceHeap<BufReader<TcpStream>>> =
        OnceLock::new();
    TCP_HEAP.get_or_init(|| {
        let DEFAULT_MAX_TCP_STREAMS = 65536;
        let max_tcp_streams = env::var("ROC_BASIC_CLI_MAX_TCP_STREAMS")
            .map(|v| v.parse().unwrap_or(DEFAULT_MAX_TCP_STREAMS))
            .unwrap_or(DEFAULT_MAX_TCP_STREAMS);
        ThreadSafeRefcountedResourceHeap::new(max_tcp_streams)
            .expect("Failed to allocate mmap for tcp handle references.")
    })
}

const UNEXPECTED_EOF_ERROR: &str = "UnexpectedEof";

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    libc::malloc(size)
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    libc::realloc(c_ptr, new_size)
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    let heap = file_heap();
    if heap.in_range(c_ptr) {
        heap.dealloc(c_ptr);
        return;
    }
    let heap = tcp_heap();
    if heap.in_range(c_ptr) {
        heap.dealloc(c_ptr);
        return;
    }
    libc::free(c_ptr)
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: &RocStr, tag_id: u32) {
    _ = crossterm::terminal::disable_raw_mode();
    match tag_id {
        0 => {
            eprintln!("Roc crashed with:\n\n\t{}\n", msg.as_str());

            print_backtrace();
            std::process::exit(1);
        }
        1 => {
            eprintln!("The program crashed with:\n\n\t{}\n", msg.as_str());

            print_backtrace();
            std::process::exit(1);
        }
        _ => todo!(),
    }
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: &RocStr, msg: &RocStr, src: &RocStr) {
    eprintln!("[{}] {} = {}", loc, src, msg);
}

/// # Safety
///
/// This function is unsafe.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

/// # Safety
///
/// This function should be called with a valid addr pointer.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_mmap(
    addr: *mut libc::c_void,
    len: libc::size_t,
    prot: libc::c_int,
    flags: libc::c_int,
    fd: libc::c_int,
    offset: libc::off_t,
) -> *mut libc::c_void {
    libc::mmap(addr, len, prot, flags, fd, offset)
}

/// # Safety
///
/// This function should be called with a valid name pointer.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_shm_open(
    name: *const libc::c_char,
    oflag: libc::c_int,
    mode: libc::mode_t,
) -> libc::c_int {
    libc::shm_open(name, oflag, mode as libc::c_uint)
}

fn print_backtrace() {
    eprintln!("Here is the call stack that led to the crash:\n");

    let mut entries = Vec::new();

    #[derive(Default)]
    struct Entry {
        pub fn_name: String,
        pub filename: Option<String>,
        pub line: Option<u32>,
        pub col: Option<u32>,
    }

    backtrace::trace(|frame| {
        backtrace::resolve_frame(frame, |symbol| {
            if let Some(fn_name) = symbol.name() {
                let fn_name = fn_name.to_string();

                if should_show_in_backtrace(&fn_name) {
                    let mut entry = Entry {
                        fn_name: format_fn_name(&fn_name),
                        ..Default::default()
                    };

                    if let Some(path) = symbol.filename() {
                        entry.filename = Some(path.to_string_lossy().into_owned());
                    };

                    entry.line = symbol.lineno();
                    entry.col = symbol.colno();

                    entries.push(entry);
                }
            } else {
                entries.push(Entry {
                    fn_name: "???".to_string(),
                    ..Default::default()
                });
            }
        });

        true // keep going to the next frame
    });

    for entry in entries {
        eprintln!("\t{}", entry.fn_name);

        if let Some(filename) = entry.filename {
            eprintln!("\t\t{filename}");
        }
    }

    eprintln!("\nOptimizations can make this list inaccurate! If it looks wrong, try running without `--optimize` and with `--linker=legacy`\n");
}

fn should_show_in_backtrace(fn_name: &str) -> bool {
    let is_from_rust = fn_name.contains("::");
    let is_host_fn = fn_name.starts_with("roc_panic")
        || fn_name.starts_with("_roc__")
        || fn_name.starts_with("rust_main")
        || fn_name == "_main";

    !is_from_rust && !is_host_fn
}

fn format_fn_name(fn_name: &str) -> String {
    // e.g. convert "_Num_sub_a0c29024d3ec6e3a16e414af99885fbb44fa6182331a70ab4ca0886f93bad5"
    // to ["Num", "sub", "a0c29024d3ec6e3a16e414af99885fbb44fa6182331a70ab4ca0886f93bad5"]
    let mut pieces_iter = fn_name.split('_');

    if let (_, Some(module_name), Some(name)) =
        (pieces_iter.next(), pieces_iter.next(), pieces_iter.next())
    {
        display_roc_fn(module_name, name)
    } else {
        "???".to_string()
    }
}

fn display_roc_fn(module_name: &str, fn_name: &str) -> String {
    let module_name = if module_name == "#UserApp" {
        "app"
    } else {
        module_name
    };

    let fn_name = if fn_name.parse::<u64>().is_ok() {
        "(anonymous function)"
    } else {
        fn_name
    };

    format!("\u{001B}[36m{module_name}\u{001B}[39m.{fn_name}")
}

/// # Safety
///
/// This function should be provided a valid dst pointer.
#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

// Protect our functions from the vicious GC.
// This is specifically a problem with static compilation and musl.
// TODO: remove all of this when we switch to effect interpreter.
pub fn init() {
    let funcs: &[*const extern "C" fn()] = &[
        roc_alloc as _,
        roc_realloc as _,
        roc_dealloc as _,
        roc_panic as _,
        roc_dbg as _,
        roc_memset as _,
        roc_fx_envDict as _,
        roc_fx_args as _,
        roc_fx_envVar as _,
        roc_fx_setCwd as _,
        roc_fx_exePath as _,
        roc_fx_stdinLine as _,
        roc_fx_stdinBytes as _,
        roc_fx_stdinReadToEnd as _,
        roc_fx_stdoutLine as _,
        roc_fx_stdoutWrite as _,
        roc_fx_stderrLine as _,
        roc_fx_stderrWrite as _,
        roc_fx_ttyModeCanonical as _,
        roc_fx_ttyModeRaw as _,
        roc_fx_fileWriteUtf8 as _,
        roc_fx_fileWriteBytes as _,
        roc_fx_pathType as _,
        roc_fx_fileReadBytes as _,
        roc_fx_fileReader as _,
        roc_fx_fileReadLine as _,
        roc_fx_fileDelete as _,
        roc_fx_cwd as _,
        roc_fx_posixTime as _,
        roc_fx_sleepMillis as _,
        roc_fx_dirList as _,
        roc_fx_sendRequest as _,
        roc_fx_tcpConnect as _,
        roc_fx_tcpReadUpTo as _,
        roc_fx_tcpReadExactly as _,
        roc_fx_tcpReadUntil as _,
        roc_fx_tcpWrite as _,
        roc_fx_commandStatus as _,
        roc_fx_commandOutput as _,
        roc_fx_dirCreate as _,
        roc_fx_dirCreateAll as _,
        roc_fx_dirDeleteEmpty as _,
        roc_fx_dirDeleteAll as _,
        roc_fx_currentArchOS as _,
        roc_fx_tempDir as _,
        roc_fx_getLocale as _,
        roc_fx_getLocales as _,
    ];
    #[allow(forgetting_references)]
    std::mem::forget(std::hint::black_box(funcs));
    if cfg!(unix) {
        let unix_funcs: &[*const extern "C" fn()] =
            &[roc_getppid as _, roc_mmap as _, roc_shm_open as _];
        #[allow(forgetting_references)]
        std::mem::forget(std::hint::black_box(unix_funcs));
    }
}

#[no_mangle]
pub extern "C" fn rust_main(args: ReadOnlyRocList<ReadOnlyRocStr>) -> i32 {
    ARGS.set(args).unwrap_or_else(|_| panic!("only one thread running, must be able to set args"));
    init();

    extern "C" {
        #[link_name = "roc__mainForHost_1_exposed"]
        pub fn roc_main_for_host_caller(not_used: i32) -> i32;

        #[link_name = "roc__mainForHost_1_exposed_size"]
        pub fn roc_main__for_host_size() -> usize;
    }

    let exit_code: i32 = unsafe {
        let code = roc_main_for_host_caller(0);

        debug_assert_eq!(std::mem::size_of_val(&code), roc_main__for_host_size());

        code
    };

    exit_code
}

#[no_mangle]
pub extern "C" fn roc_fx_envDict() -> RocList<(RocStr, RocStr)> {
    // TODO: can we be more efficient about reusing the String's memory for RocStr?
    std::env::vars_os()
        .map(|(key, val)| {
            (
                RocStr::from(key.to_string_lossy().borrow()),
                RocStr::from(val.to_string_lossy().borrow()),
            )
        })
        .collect()
}

#[no_mangle]
pub extern "C" fn roc_fx_args() -> ReadOnlyRocList<ReadOnlyRocStr> {
    // Note: the clone here is no-op since the refcount is readonly. Just goes from &RocList to RocList.
    ARGS.get().expect("args was set during init and must be here").clone()
}

#[no_mangle]
pub extern "C" fn roc_fx_envVar(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    // TODO: can we be more efficient about reusing the String's memory for RocStr?
    match std::env::var_os(roc_str.as_str()) {
        Some(os_str) => RocResult::ok(RocStr::from(os_str.to_string_lossy().borrow())),
        None => RocResult::err(()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_setCwd(roc_path: &RocList<u8>) -> RocResult<(), ()> {
    match std::env::set_current_dir(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(_) => RocResult::err(()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_exePath(_roc_str: &RocStr) -> RocResult<RocList<u8>, ()> {
    match std::env::current_exe() {
        Ok(path_buf) => RocResult::ok(os_str_to_roc_path(path_buf.as_path().as_os_str())),
        Err(_) => RocResult::err(()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinLine() -> RocResult<RocStr, glue::IOErr> {
    let stdin = std::io::stdin();

    match stdin.lock().lines().next() {
        None => RocResult::err(glue::IOErr {
            msg: RocStr::empty(),
            tag: glue::IOErrTag::EndOfFile,
        }),
        Some(Ok(str)) => RocResult::ok(str.as_str().into()),
        Some(Err(io_err)) => RocResult::err(io_err.into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinBytes() -> RocResult<RocList<u8>, glue::IOErr> {
    const BUF_SIZE: usize = 16_384; // 16 KiB = 16 * 1024 = 16,384 bytes
    let stdin = std::io::stdin();
    let mut buffer: [u8; BUF_SIZE] = [0; BUF_SIZE];

    match stdin.lock().read(&mut buffer) {
        Ok(bytes_read) => RocResult::ok(RocList::from(&buffer[0..bytes_read])),
        Err(io_err) => RocResult::err(io_err.into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinReadToEnd() -> RocResult<RocList<u8>, glue::IOErr> {
    let stdin = std::io::stdin();
    let mut buf = Vec::new();
    match stdin.lock().read_to_end(&mut buf) {
        Ok(bytes_read) => RocResult::ok(RocList::from(&buf[0..bytes_read])),
        Err(io_err) => RocResult::err(io_err.into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutLine(line: &RocStr) -> RocResult<(), glue::IOErr> {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutWrite(text: &RocStr) -> RocResult<(), glue::IOErr> {
    let stdout = std::io::stdout();
    let mut handle = stdout.lock();

    handle
        .write_all(text.as_bytes())
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrLine(line: &RocStr) -> RocResult<(), glue::IOErr> {
    let stderr = std::io::stderr();
    let mut handle = stderr.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrWrite(text: &RocStr) -> RocResult<(), glue::IOErr> {
    let stderr = std::io::stderr();
    let mut handle = stderr.lock();

    handle
        .write_all(text.as_bytes())
        .and_then(|()| handle.flush())
        .map_err(|io_err| io_err.into())
        .into()
}

#[no_mangle]
pub extern "C" fn roc_fx_ttyModeCanonical() {
    crossterm::terminal::disable_raw_mode().expect("failed to disable raw mode");
}

#[no_mangle]
pub extern "C" fn roc_fx_ttyModeRaw() {
    crossterm::terminal::enable_raw_mode().expect("failed to enable raw mode");
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteUtf8(
    roc_path: &RocList<u8>,
    roc_str: &RocStr,
) -> RocResult<(), RocStr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteBytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), RocStr> {
    write_slice(roc_path, roc_bytes.as_slice())
}

fn write_slice(roc_path: &RocList<u8>, bytes: &[u8]) -> RocResult<(), RocStr> {
    match File::create(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.write_all(bytes) {
            Ok(()) => RocResult::ok(()),
            Err(err) => RocResult::err(toRocWriteError(err)),
        },
        Err(err) => RocResult::err(toRocWriteError(err)),
    }
}

#[repr(C)]
pub struct InternalPathType {
    isDir: bool,
    isFile: bool,
    isSymLink: bool,
}

#[no_mangle]
pub extern "C" fn roc_fx_pathType(
    roc_path: &RocList<u8>,
) -> RocResult<InternalPathType, RocList<u8>> {
    let path = path_from_roc_path(roc_path);
    match path.symlink_metadata() {
        Ok(m) => RocResult::ok(InternalPathType {
            isDir: m.is_dir(),
            isFile: m.is_file(),
            isSymLink: m.is_symlink(),
        }),
        Err(err) => RocResult::err(toRocGetMetadataError(err)),
    }
}

#[cfg(target_family = "unix")]
fn path_from_roc_path(bytes: &RocList<u8>) -> Cow<'_, Path> {
    use std::os::unix::ffi::OsStrExt;
    let os_str = OsStr::from_bytes(bytes.as_slice());
    Cow::Borrowed(Path::new(os_str))
}

#[cfg(target_family = "windows")]
fn path_from_roc_path(bytes: &RocList<u8>) -> Cow<'_, Path> {
    use std::os::windows::ffi::OsStringExt;

    let bytes = bytes.as_slice();
    assert_eq!(bytes.len() % 2, 0);
    let characters: &[u16] =
        unsafe { std::slice::from_raw_parts(bytes.as_ptr().cast(), bytes.len() / 2) };

    let os_string = std::ffi::OsString::from_wide(characters);

    Cow::Owned(std::path::PathBuf::from(os_string))
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReadBytes(roc_path: &RocList<u8>) -> RocResult<RocList<u8>, RocStr> {
    // TODO: write our own duplicate of `read_to_end` that directly fills a `RocList<u8>`.
    // This adds an extra O(n) copy.
    let mut bytes = Vec::new();

    match File::open(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.read_to_end(&mut bytes) {
            Ok(_bytes_read) => RocResult::ok(RocList::from(bytes.as_slice())),
            Err(err) => RocResult::err(toRocReadError(err)),
        },
        Err(err) => RocResult::err(toRocReadError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReader(
    roc_path: &RocList<u8>,
    size: u64,
) -> RocResult<RocBox<()>, RocStr> {
    match File::open(path_from_roc_path(roc_path)) {
        Ok(file) => {
            let buf_reader = if size > 0 {
                BufReader::with_capacity(size as usize, file)
            } else {
                BufReader::new(file)
            };

            let heap = file_heap();
            let alloc_result = heap.alloc_for(buf_reader);
            match alloc_result {
                Ok(out) => RocResult::ok(out),
                Err(err) => RocResult::err(toRocReadError(err)),
            }
        }
        Err(err) => RocResult::err(toRocReadError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReadLine(data: RocBox<()>) -> RocResult<RocList<u8>, RocStr> {
    let buf_reader: &mut BufReader<File> = ThreadSafeRefcountedResourceHeap::box_to_resource(data);

    let mut buffer = RocList::empty();
    match read_until(buf_reader, b'\n', &mut buffer) {
        Ok(..) => {
            // Note: this returns an empty list when no bytes were read, e.g. End Of File
            RocResult::ok(buffer)
        }
        Err(err) => RocResult::err(err.to_string().as_str().into()),
    }
}

fn read_until<R: BufRead + ?Sized>(
    r: &mut R,
    delim: u8,
    buf: &mut RocList<u8>,
) -> io::Result<usize> {
    let mut read = 0;
    loop {
        let (done, used) = {
            let available = match r.fill_buf() {
                Ok(n) => n,
                Err(ref e) if matches!(e.kind(), ErrorKind::Interrupted) => continue,
                Err(e) => return Err(e),
            };
            match memchr::memchr(delim, available) {
                Some(i) => {
                    buf.extend_from_slice(&available[..=i]);
                    (true, i + 1)
                }
                None => {
                    buf.extend_from_slice(available);
                    (false, available.len())
                }
            }
        };
        r.consume(used);
        read += used;
        if done || used == 0 {
            return Ok(read);
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_fileDelete(roc_path: &RocList<u8>) -> RocResult<(), RocStr> {
    match std::fs::remove_file(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(toRocReadError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_cwd() -> RocResult<RocList<u8>, ()> {
    // TODO instead, call getcwd on UNIX and GetCurrentDirectory on Windows
    match std::env::current_dir() {
        Ok(path_buf) => RocResult::ok(os_str_to_roc_path(path_buf.into_os_string().as_os_str())),
        Err(_) => {
            // Default to empty path
            RocResult::ok(RocList::empty())
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_posixTime() -> roc_std::U128 {
    // TODO in future may be able to avoid this panic by using C APIs
    let since_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time went backwards");

    roc_std::U128::from(since_epoch.as_nanos())
}

#[no_mangle]
pub extern "C" fn roc_fx_sleepMillis(milliseconds: u64) {
    let duration = Duration::from_millis(milliseconds);
    std::thread::sleep(duration);
}

#[no_mangle]
pub extern "C" fn roc_fx_dirList(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<RocList<u8>>, RocStr> {
    let path = path_from_roc_path(roc_path);

    if path.is_dir() {
        let dir = match std::fs::read_dir(path) {
            Ok(dir) => dir,
            Err(err) => return RocResult::err(handleDirError(err)),
        };

        let mut entries = Vec::new();

        for entry in dir.flatten() {
            let path = entry.path();
            let str = path.as_os_str();
            entries.push(os_str_to_roc_path(str));
        }

        RocResult::ok(RocList::from_iter(entries))
    } else {
        RocResult::err("ErrorKind::NotADirectory".into())
    }
}

#[cfg(target_family = "unix")]
fn os_str_to_roc_path(os_str: &OsStr) -> RocList<u8> {
    use std::os::unix::ffi::OsStrExt;

    RocList::from(os_str.as_bytes())
}

#[cfg(target_family = "windows")]
fn os_str_to_roc_path(os_str: &OsStr) -> RocList<u8> {
    use std::os::windows::ffi::OsStrExt;

    let bytes: Vec<_> = os_str.encode_wide().flat_map(|c| c.to_be_bytes()).collect();

    RocList::from(bytes.as_slice())
}

#[repr(C)]
pub struct Request {
    body: RocList<u8>,
    headers: RocList<Header>,
    method: RocStr,
    mimeType: RocStr,
    timeoutMs: u64,
    url: RocStr,
}

#[repr(C)]
pub struct Header {
    key: RocStr,
    value: RocStr,
}

impl roc_std::RocRefcounted for Header {
    fn inc(&mut self) {
        self.key.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(C)]
pub struct Metadata {
    headers: RocList<Header>,
    statusText: RocStr,
    url: RocStr,
    statusCode: u16,
}

impl Metadata {
    fn empty() -> Metadata {
        Metadata {
            headers: RocList::empty(),
            statusText: RocStr::empty(),
            url: RocStr::empty(),
            statusCode: 0,
        }
    }
}

#[repr(C)]
pub struct InternalResponse {
    body: RocList<u8>,
    metadata: Metadata,
    variant: RocStr,
}

impl InternalResponse {
    fn bad_request(error: &str) -> InternalResponse {
        InternalResponse {
            variant: "BadRequest".into(),
            metadata: Metadata {
                statusText: RocStr::from(error),
                ..Metadata::empty()
            },
            body: RocList::empty(),
        }
    }

    fn good_status(metadata: Metadata, body: RocList<u8>) -> InternalResponse {
        InternalResponse {
            variant: "GoodStatus".into(),
            metadata,
            body,
        }
    }

    fn bad_status(metadata: Metadata, body: RocList<u8>) -> InternalResponse {
        InternalResponse {
            variant: "BadStatus".into(),
            metadata,
            body,
        }
    }

    fn timeout() -> InternalResponse {
        InternalResponse {
            variant: "Timeout".into(),
            metadata: Metadata::empty(),
            body: RocList::empty(),
        }
    }

    fn network_error() -> InternalResponse {
        InternalResponse {
            variant: "NetworkError".into(),
            metadata: Metadata::empty(),
            body: RocList::empty(),
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_sendRequest(roc_request: &Request) -> InternalResponse {
    let method = parse_http_method(roc_request.method.as_str());
    let mut req_builder = hyper::Request::builder()
        .method(method)
        .uri(roc_request.url.as_str());
    let mut has_content_type_header = false;

    for header in roc_request.headers.iter() {
        req_builder = req_builder.header(header.key.as_str(), header.value.as_str());
        if header.key.eq_ignore_ascii_case("Content-Type") {
            has_content_type_header = true;
        }
    }

    let bytes = String::from_utf8(roc_request.body.as_slice().to_vec()).unwrap();
    let mime_type_str = roc_request.mimeType.as_str();

    if !has_content_type_header && !mime_type_str.is_empty() {
        req_builder = req_builder.header("Content-Type", mime_type_str);
    }

    let request = match req_builder.body(bytes) {
        Ok(req) => req,
        Err(err) => return InternalResponse::bad_request(err.to_string().as_str()),
    };

    if roc_request.timeoutMs > 0 {
        let time_limit = Duration::from_millis(roc_request.timeoutMs);

        TOKIO_RUNTIME.with(|rt| {
            rt.block_on(async {
                tokio::time::timeout(time_limit, send_request(request, &roc_request.url)).await
            })
            .unwrap_or_else(|_err| InternalResponse::timeout())
        })
    } else {
        TOKIO_RUNTIME.with(|rt| rt.block_on(send_request(request, &roc_request.url)))
    }
}

fn parse_http_method(method: &str) -> hyper::Method {
    match method {
        "Connect" => hyper::Method::CONNECT,
        "Delete" => hyper::Method::DELETE,
        "Get" => hyper::Method::GET,
        "Head" => hyper::Method::HEAD,
        "Options" => hyper::Method::OPTIONS,
        "Patch" => hyper::Method::PATCH,
        "Post" => hyper::Method::POST,
        "Put" => hyper::Method::PUT,
        "Trace" => hyper::Method::TRACE,
        _other => unreachable!("Should only pass known HTTP methods from Roc side"),
    }
}

async fn send_request(request: hyper::Request<String>, url: &str) -> InternalResponse {
    use hyper::Client;
    use hyper_rustls::HttpsConnectorBuilder;

    let https = HttpsConnectorBuilder::new()
        .with_native_roots()
        .https_or_http()
        .enable_http1()
        .build();

    let client: Client<_, String> = Client::builder().build(https);
    let res = client.request(request).await;

    match res {
        Ok(response) => {
            let status = response.status();
            let status_str = status.canonical_reason().unwrap_or_else(|| status.as_str());

            let headers_iter = response.headers().iter().map(|(name, value)| Header {
                key: RocStr::from(name.as_str()),
                value: RocStr::from(value.to_str().unwrap_or_default()),
            });

            let metadata = Metadata {
                headers: RocList::from_iter(headers_iter),
                statusText: RocStr::from(status_str),
                url: RocStr::from(url),
                statusCode: status.as_u16(),
            };

            let bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
            let body: RocList<u8> = RocList::from_iter(bytes);

            if status.is_success() {
                InternalResponse::good_status(metadata, body)
            } else {
                InternalResponse::bad_status(metadata, body)
            }
        }
        Err(err) => {
            if err.is_timeout() {
                InternalResponse::timeout()
            } else if err.is_connect() || err.is_closed() {
                InternalResponse::network_error()
            } else {
                InternalResponse::bad_request(err.to_string().as_str())
            }
        }
    }
}

fn toRocWriteError(err: std::io::Error) -> RocStr {
    match err.kind() {
        ErrorKind::NotFound => "ErrorKind::NotFound".into(),
        ErrorKind::AlreadyExists => "ErrorKind::AlreadyExists".into(),
        ErrorKind::Interrupted => "ErrorKind::Interrupted".into(),
        ErrorKind::OutOfMemory => "ErrorKind::OutOfMemory".into(),
        ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".into(),
        ErrorKind::TimedOut => "ErrorKind::TimedOut".into(),
        ErrorKind::WriteZero => "ErrorKind::WriteZero".into(),
        _ => format!("{:?}", err).as_str().into(),
    }
}

fn toRocReadError(err: std::io::Error) -> RocStr {
    match err.kind() {
        ErrorKind::Interrupted => "ErrorKind::Interrupted".into(),
        ErrorKind::NotFound => "ErrorKind::NotFound".into(),
        ErrorKind::OutOfMemory => "ErrorKind::OutOfMemory".into(),
        ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".into(),
        ErrorKind::TimedOut => "ErrorKind::TimedOut".into(),
        _ => format!("{:?}", err).as_str().into(),
    }
}

fn toRocGetMetadataError(err: std::io::Error) -> RocList<u8> {
    match err.kind() {
        ErrorKind::PermissionDenied => RocList::from([b'P', b'D']),
        ErrorKind::NotFound => RocList::from([b'N', b'F']),
        _ => RocList::from(format!("{:?}", err).as_bytes()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpConnect(host: &RocStr, port: u16) -> RocResult<RocBox<()>, RocStr> {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let buf_reader = BufReader::new(stream);

            let heap = tcp_heap();
            let alloc_result = heap.alloc_for(buf_reader);
            match alloc_result {
                Ok(out) => RocResult::ok(out),
                Err(err) => RocResult::err(to_tcp_connect_err(err)),
            }
        }
        Err(err) => RocResult::err(to_tcp_connect_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUpTo(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut chunk = stream.take(bytes_to_read);

    //TODO: fill a roc list directly. This is an extra O(n) copy.
    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            stream.consume(received.len());

            RocResult::ok(RocList::from(&received[..]))
        }
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadExactly(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut buffer = Vec::with_capacity(bytes_to_read as usize);
    let mut chunk = stream.take(bytes_to_read);

    //TODO: fill a roc list directly. This is an extra O(n) copy.
    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if (read as u64) < bytes_to_read {
                RocResult::err(UNEXPECTED_EOF_ERROR.into())
            } else {
                RocResult::ok(RocList::from(&buffer[..]))
            }
        }
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUntil(
    stream: RocBox<()>,
    byte: u8,
) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut buffer = RocList::empty();
    match read_until(stream, byte, &mut buffer) {
        Ok(_) => RocResult::ok(buffer),
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpWrite(stream: RocBox<()>, msg: &RocList<u8>) -> RocResult<(), RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    match stream.get_mut().write_all(msg.as_slice()) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

fn to_tcp_connect_err(err: std::io::Error) -> RocStr {
    match err.kind() {
        ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".into(),
        ErrorKind::AddrInUse => "ErrorKind::AddrInUse".into(),
        ErrorKind::AddrNotAvailable => "ErrorKind::AddrNotAvailable".into(),
        ErrorKind::ConnectionRefused => "ErrorKind::ConnectionRefused".into(),
        ErrorKind::Interrupted => "ErrorKind::Interrupted".into(),
        ErrorKind::TimedOut => "ErrorKind::TimedOut".into(),
        ErrorKind::Unsupported => "ErrorKind::Unsupported".into(),
        other => format!("{:?}", other).as_str().into(),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> RocStr {
    match err.kind() {
        ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".into(),
        ErrorKind::ConnectionRefused => "ErrorKind::ConnectionRefused".into(),
        ErrorKind::ConnectionReset => "ErrorKind::ConnectionReset".into(),
        ErrorKind::Interrupted => "ErrorKind::Interrupted".into(),
        ErrorKind::OutOfMemory => "ErrorKind::OutOfMemory".into(),
        ErrorKind::BrokenPipe => "ErrorKind::BrokenPipe".into(),
        other => format!("{:?}", other).as_str().into(),
    }
}

#[repr(C)]
pub struct Command {
    pub args: RocList<RocStr>,
    pub envs: RocList<RocStr>,
    pub program: RocStr,
    pub clearEnvs: bool,
}

#[repr(C)]
pub struct CommandOutput {
    pub status: RocResult<(), RocList<u8>>,
    pub stderr: RocList<u8>,
    pub stdout: RocList<u8>,
}

#[no_mangle]
pub extern "C" fn roc_fx_commandStatus(roc_cmd: &Command) -> RocResult<(), RocList<u8>> {
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
    if roc_cmd.clearEnvs {
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
                    Some(code) => commandStatusErrorCode(code),
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        commandStatusKilledBySignal()
                    }
                }
            }
        }
        Err(err) => commandStatusOtherError(err),
    }
}

fn commandStatusKilledBySignal() -> RocResult<(), RocList<u8>> {
    let mut error_bytes = Vec::new();
    error_bytes.extend([b'K', b'S']);
    let error = RocList::from(error_bytes.as_slice());
    RocResult::err(error)
}

fn commandStatusErrorCode(code: i32) -> RocResult<(), RocList<u8>> {
    let mut error_bytes = Vec::new();
    error_bytes.extend([b'E', b'C']);
    error_bytes.extend(code.to_ne_bytes()); // use NATIVE ENDIANNESS
    let error = RocList::from(error_bytes.as_slice()); //RocList::from([b'E',b'C'].extend(code.to_le_bytes()));
    RocResult::err(error)
}

fn commandStatusOtherError(err: std::io::Error) -> RocResult<(), RocList<u8>> {
    let error = RocList::from(format!("{:?}", err).as_bytes());
    RocResult::err(error)
}

#[no_mangle]
pub extern "C" fn roc_fx_commandOutput(roc_cmd: &Command) -> CommandOutput {
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
    if roc_cmd.clearEnvs {
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
                    Some(code) => commandStatusErrorCode(code),
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        commandStatusKilledBySignal()
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
            status: commandStatusOtherError(err),
            stdout: RocList::empty(),
            stderr: RocList::empty(),
        },
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirCreate(roc_path: &RocList<u8>) -> RocResult<(), RocStr> {
    match std::fs::create_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(handleDirError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirCreateAll(roc_path: &RocList<u8>) -> RocResult<(), RocStr> {
    match std::fs::create_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(handleDirError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirDeleteEmpty(roc_path: &RocList<u8>) -> RocResult<(), RocStr> {
    match std::fs::remove_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(handleDirError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirDeleteAll(roc_path: &RocList<u8>) -> RocResult<(), RocStr> {
    match std::fs::remove_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(handleDirError(err)),
    }
}

/// See docs in `platform/Stdout.roc` for descriptions
fn handleDirError(io_err: std::io::Error) -> RocStr {
    match io_err.kind() {
        ErrorKind::NotFound => RocStr::from("ErrorKind::NotFound"),
        ErrorKind::PermissionDenied => RocStr::from("ErrorKind::PermissionDenied"),
        ErrorKind::AlreadyExists => RocStr::from("ErrorKind::AlreadyExists"),
        // The below are unstable features see https://github.com/rust-lang/rust/issues/86442
        // TODO add these when available
        // ErrorKind::NotADirectory => RocStr::from("ErrorKind::NotADirectory"),
        // ErrorKind::IsADirectory => RocStr::from("ErrorKind::IsADirectory"),
        // ErrorKind::DirectoryNotEmpty => RocStr::from("ErrorKind::DirectoryNotEmpty"),
        // ErrorKind::ReadOnlyFilesystem => RocStr::from("ErrorKind::ReadOnlyFilesystem"),
        // ErrorKind::FilesystemLoop => RocStr::from("ErrorKind::FilesystemLoop"),
        // ErrorKind::FilesystemQuotaExceeded => RocStr::from("ErrorKind::FilesystemQuotaExceeded"),
        // ErrorKind::StorageFull => RocStr::from("ErrorKind::StorageFull"),
        // ErrorKind::InvalidFilename => RocStr::from("ErrorKind::InvalidFilename"),
        _ => RocStr::from(format!("{:?}", io_err).as_str()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_hardLink(
    path_from: &RocList<u8>,
    path_to: &RocList<u8>,
) -> RocResult<(), glue::IOErr> {
    match std::fs::hard_link(path_from_roc_path(path_from), path_from_roc_path(path_to)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_currentArchOS() -> glue::ReturnArchOS {
    glue::ReturnArchOS {
        arch: std::env::consts::ARCH.into(),
        os: std::env::consts::OS.into(),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tempDir() -> RocList<u8> {
    let path_os_string_bytes = std::env::temp_dir().into_os_string().into_encoded_bytes();

    RocList::from(path_os_string_bytes.as_slice())
}

#[no_mangle]
pub extern "C" fn roc_fx_getLocale() -> RocResult<RocStr, ()> {
    sys_locale::get_locale().map_or_else(
        || RocResult::err(()),
        |locale| RocResult::ok(locale.to_string().as_str().into()),
    )
}

#[no_mangle]
pub extern "C" fn roc_fx_getLocales() -> RocList<RocStr> {
    const DEFAULT_MAX_LOCALES: usize = 10;
    let locales = sys_locale::get_locales();
    let mut roc_locales = RocList::with_capacity(DEFAULT_MAX_LOCALES);
    for l in locales {
        roc_locales.push(l.to_string().as_str().into());
    }
    roc_locales
}
