#![allow(non_snake_case)]

mod command_glue;
mod dir_glue;
mod file_glue;
mod glue;
mod tcp_glue;

use core::alloc::Layout;
use core::ffi::c_void;
use core::mem::MaybeUninit;
use glue::Metadata;
use roc_std::{RocDict, RocList, RocResult, RocStr};
use std::borrow::{Borrow, Cow};
use std::ffi::OsStr;
use std::fs::File;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use file_glue::ReadErr;
use file_glue::WriteErr;

use dir_glue::IOError;

extern "C" {
    #[link_name = "roc__mainForHost_1_exposed_generic"]
    fn roc_main(output: *mut u8);

    #[link_name = "roc__mainForHost_1_exposed_size"]
    fn roc_main_size() -> i64;

    #[link_name = "roc__mainForHost_0_caller"]
    fn call_Fx(flags: *const u8, closure_data: *const u8, output: *mut u8);

    #[allow(dead_code)]
    #[link_name = "roc__mainForHost_0_size"]
    fn size_Fx() -> i64;

    #[link_name = "roc__mainForHost_0_result_size"]
    fn size_Fx_result() -> i64;
}

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    libc::malloc(size)
}

#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    _old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    libc::realloc(c_ptr, new_size)
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    libc::free(c_ptr)
}

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

#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn roc_getppid() -> libc::pid_t {
    libc::getppid()
}

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
                    let mut entry: Entry = Default::default();

                    entry.fn_name = format_fn_name(&fn_name);

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
        || fn_name.starts_with("_Effect_effect")
        || fn_name.starts_with("_roc__")
        || fn_name.starts_with("rust_main")
        || fn_name == "_main";

    !is_from_rust && !is_host_fn
}

fn format_fn_name(fn_name: &str) -> String {
    // e.g. convert "_Num_sub_a0c29024d3ec6e3a16e414af99885fbb44fa6182331a70ab4ca0886f93bad5"
    // to ["Num", "sub", "a0c29024d3ec6e3a16e414af99885fbb44fa6182331a70ab4ca0886f93bad5"]
    let mut pieces_iter = fn_name.split("_");

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
        roc_memset as _,
        roc_fx_envDict as _,
        roc_fx_args as _,
        roc_fx_envVar as _,
        roc_fx_setCwd as _,
        roc_fx_exePath as _,
        roc_fx_stdinLine as _,
        roc_fx_stdinBytes as _,
        roc_fx_stdoutLine as _,
        roc_fx_stdoutWrite as _,
        roc_fx_stderrLine as _,
        roc_fx_stderrWrite as _,
        roc_fx_ttyModeCanonical as _,
        roc_fx_ttyModeRaw as _,
        roc_fx_fileWriteUtf8 as _,
        roc_fx_fileWriteBytes as _,
        roc_fx_fileReadBytes as _,
        roc_fx_fileDelete as _,
        roc_fx_cwd as _,
        roc_fx_posixTime as _,
        roc_fx_sleepMillis as _,
        roc_fx_dirList as _,
        roc_fx_sendRequest as _,
        roc_fx_tcpConnect as _,
        roc_fx_tcpClose as _,
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
    ];
    std::mem::forget(std::hint::black_box(funcs));
    if cfg!(unix) {
        let unix_funcs: &[*const extern "C" fn()] =
            &[roc_getppid as _, roc_mmap as _, roc_shm_open as _];
        std::mem::forget(std::hint::black_box(unix_funcs));
    }
}

#[no_mangle]
pub extern "C" fn rust_main() {
    init();
    let size = unsafe { roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    unsafe {
        // TODO allocate on the stack if it's under a certain size
        let buffer = std::alloc::alloc(layout);

        roc_main(buffer);

        call_the_closure(buffer);

        std::alloc::dealloc(buffer, layout);
    }
}

unsafe fn call_the_closure(closure_data_ptr: *const u8) -> u8 {
    let size = size_Fx_result() as usize;
    let layout = Layout::array::<u8>(size).unwrap();
    let buffer = std::alloc::alloc(layout) as *mut u8;

    call_Fx(
        // This flags pointer will never get dereferenced
        MaybeUninit::uninit().as_ptr(),
        closure_data_ptr as *const u8,
        buffer as *mut u8,
    );

    std::alloc::dealloc(buffer, layout);

    // TODO return the u8 exit code returned by the Fx closure
    0
}

#[no_mangle]
pub extern "C" fn roc_fx_envDict() -> RocDict<RocStr, RocStr> {
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
pub extern "C" fn roc_fx_args() -> RocList<RocStr> {
    // TODO: can we be more efficient about reusing the String's memory for RocStr?
    std::env::args_os()
        .map(|os_str| RocStr::from(os_str.to_string_lossy().borrow()))
        .collect()
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
pub extern "C" fn roc_fx_stdinLine() -> RocResult<RocStr, ()> { // () is used for EOF
    let stdin = std::io::stdin();

    match stdin.lock().lines().next() {
        None => RocResult::err(()),
        Some(Ok(str)) => RocResult::ok(RocStr::from(str.as_str())),
        Some(Err(err)) => panic!("Failed to get next line from stdin:\n\t{:?}", err),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinBytes() -> RocList<u8> {
    let stdin = std::io::stdin();
    let mut buffer: [u8; 256] = [0; 256];

    match stdin.lock().read(&mut buffer) {
        Ok(bytes_read) => RocList::from(&buffer[0..bytes_read]),
        Err(_) => RocList::from((&[]).as_slice()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutLine(line: &RocStr) {
    let string = line.as_str();
    println!("{}", string);
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutWrite(text: &RocStr) {
    let string = text.as_str();
    print!("{}", string);
    std::io::stdout().flush().unwrap();
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrLine(line: &RocStr) {
    let string = line.as_str();
    eprintln!("{}", string);
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrWrite(text: &RocStr) {
    let string = text.as_str();
    eprint!("{}", string);
    std::io::stderr().flush().unwrap();
}

#[no_mangle]
pub extern "C" fn roc_fx_ttyModeCanonical() {
    crossterm::terminal::disable_raw_mode().expect("failed to disable raw mode");
}

#[no_mangle]
pub extern "C" fn roc_fx_ttyModeRaw() {
    crossterm::terminal::enable_raw_mode().expect("failed to enable raw mode");
}

// #[no_mangle]
// pub extern "C" fn roc_fx_fileWriteUtf8(
//     roc_path: &RocList<u8>,
//     roc_string: &RocStr,
//     // ) -> RocResult<(), WriteErr> {
// ) -> (u8, u8) {
//     let _ = write_slice(roc_path, roc_string.as_str().as_bytes());

//     (255, 255)
// }

// #[no_mangle]
// pub extern "C" fn roc_fx_fileWriteUtf8(roc_path: &RocList<u8>, roc_string: &RocStr) -> Fail {
//     write_slice2(roc_path, roc_string.as_str().as_bytes())
// }
#[no_mangle]
pub extern "C" fn roc_fx_fileWriteUtf8(
    roc_path: &RocList<u8>,
    roc_str: &RocStr,
) -> RocResult<(), WriteErr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteBytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), WriteErr> {
    write_slice(roc_path, roc_bytes.as_slice())
}

fn write_slice(roc_path: &RocList<u8>, bytes: &[u8]) -> RocResult<(), WriteErr> {
    match File::create(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.write_all(bytes) {
            Ok(()) => RocResult::ok(()),
            Err(err) => RocResult::err(toRocWriteError(err)),
        },
        Err(err) => RocResult::err(toRocWriteError(err)),
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
pub extern "C" fn roc_fx_fileReadBytes(roc_path: &RocList<u8>) -> RocResult<RocList<u8>, ReadErr> {
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
pub extern "C" fn roc_fx_fileDelete(roc_path: &RocList<u8>) -> RocResult<(), ReadErr> {
    match std::fs::remove_file(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(toRocReadError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_cwd() -> RocList<u8> {
    // TODO instead, call getcwd on UNIX and GetCurrentDirectory on Windows
    match std::env::current_dir() {
        Ok(path_buf) => os_str_to_roc_path(path_buf.into_os_string().as_os_str()),
        Err(_) => {
            // Default to empty path
            RocList::empty()
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
    _roc_path: &RocList<u8>,
) -> RocResult<RocList<RocList<u8>>, IOError> {
    // match std::fs::read_dir(path_from_roc_path(roc_path)) {
    //     Ok(dir_entries) => {

    //         let entries = dir_entries
    //             .filter_map(|opt_dir_entry| match opt_dir_entry {
    //                 Ok(entry) => Some(os_str_to_roc_path(entry.path().into_os_string().as_os_str())),
    //                 Err(_) => None
    //             })
    //             .collect::<RocList<RocList<u8>>>();

    //         dbg!(&entries);

    //         RocResult::ok(entries)

    //     },
    //     Err(err) => RocResult::err(toRocIOError(err)),
    // }

    // TODO implement this function
    RocResult::err(IOError::Other())
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

#[no_mangle]
pub extern "C" fn roc_fx_sendRequest(roc_request: &glue::Request) -> glue::Response {
    let mut builder = reqwest::blocking::ClientBuilder::new();

    if roc_request.timeout.discriminant() == glue::discriminant_TimeoutConfig::TimeoutMilliseconds {
        let ms: &u64 = unsafe { roc_request.timeout.as_TimeoutMilliseconds() };
        builder = builder.timeout(Duration::from_millis(*ms));
    }

    let client = match builder.build() {
        Ok(c) => c,
        Err(_) => {
            return glue::Response::NetworkError; // TLS backend cannot be initialized
        }
    };

    let method = match roc_request.method {
        glue::Method::Connect => reqwest::Method::CONNECT,
        glue::Method::Delete => reqwest::Method::DELETE,
        glue::Method::Get => reqwest::Method::GET,
        glue::Method::Head => reqwest::Method::HEAD,
        glue::Method::Options => reqwest::Method::OPTIONS,
        glue::Method::Patch => reqwest::Method::PATCH,
        glue::Method::Post => reqwest::Method::POST,
        glue::Method::Put => reqwest::Method::PUT,
        glue::Method::Trace => reqwest::Method::TRACE,
    };

    let url = roc_request.url.as_str();

    let mut req_builder = client.request(method, url);
    for header in roc_request.headers.iter() {
        let (name, value) = unsafe { header.as_Header() };
        req_builder = req_builder.header(name.as_str(), value.as_str());
    }
    if roc_request.body.discriminant() == glue::discriminant_Body::Body {
        let (mime_type_tag, body_byte_list) = unsafe { roc_request.body.as_Body() };
        let mime_type_str: &RocStr = unsafe { mime_type_tag.as_MimeType() };

        req_builder = req_builder.header("Content-Type", mime_type_str.as_str());
        req_builder = req_builder.body(body_byte_list.as_slice().to_vec());
    }

    let request = match req_builder.build() {
        Ok(req) => req,
        Err(err) => {
            return glue::Response::BadRequest(RocStr::from(err.to_string().as_str()));
        }
    };

    match client.execute(request) {
        Ok(response) => {
            let status = response.status();
            let status_str = status.canonical_reason().unwrap_or_else(|| status.as_str());

            let headers_iter = response.headers().iter().map(|(name, value)| {
                glue::Header::Header(
                    RocStr::from(name.as_str()),
                    RocStr::from(value.to_str().unwrap_or_default()),
                )
            });

            let metadata = Metadata {
                headers: RocList::from_iter(headers_iter),
                statusText: RocStr::from(status_str),
                url: RocStr::from(url),
                statusCode: status.as_u16(),
            };

            let bytes = response.bytes().unwrap_or_default();
            let body: RocList<u8> = RocList::from_iter(bytes.into_iter());

            if status.is_success() {
                glue::Response::GoodStatus(metadata, body)
            } else {
                glue::Response::BadStatus(metadata, body)
            }
        }
        Err(err) => {
            if err.is_timeout() {
                glue::Response::Timeout
            } else if err.is_request() {
                glue::Response::BadRequest(RocStr::from(err.to_string().as_str()))
            } else {
                glue::Response::NetworkError
            }
        }
    }
}

fn toRocWriteError(err: std::io::Error) -> file_glue::WriteErr {
    match err.kind() {
        ErrorKind::NotFound => file_glue::WriteErr::NotFound,
        ErrorKind::AlreadyExists => file_glue::WriteErr::AlreadyExists,
        ErrorKind::Interrupted => file_glue::WriteErr::Interrupted,
        ErrorKind::OutOfMemory => file_glue::WriteErr::OutOfMemory,
        ErrorKind::PermissionDenied => file_glue::WriteErr::PermissionDenied,
        ErrorKind::TimedOut => file_glue::WriteErr::TimedOut,
        // TODO investigate support the following IO errors may need to update API
        ErrorKind::WriteZero => file_glue::WriteErr::WriteZero,
        _ => file_glue::WriteErr::Unsupported,
        // TODO investigate support the following IO errors
        // std::io::ErrorKind::FileTooLarge <- unstable language feature
        // std::io::ErrorKind::ExecutableFileBusy <- unstable language feature
        // std::io::ErrorKind::FilesystemQuotaExceeded <- unstable language feature
        // std::io::ErrorKind::InvalidFilename <- unstable language feature
        // std::io::ErrorKind::ResourceBusy <- unstable language feature
        // std::io::ErrorKind::ReadOnlyFilesystem <- unstable language feature
        // std::io::ErrorKind::TooManyLinks <- unstable language feature
        // std::io::ErrorKind::StaleNetworkFileHandle <- unstable language feature
        // std::io::ErrorKind::StorageFull <- unstable language feature
    }
}

fn toRocReadError(err: std::io::Error) -> file_glue::ReadErr {
    match err.kind() {
        ErrorKind::Interrupted => file_glue::ReadErr::Interrupted,
        ErrorKind::NotFound => file_glue::ReadErr::NotFound,
        ErrorKind::OutOfMemory => file_glue::ReadErr::OutOfMemory,
        ErrorKind::PermissionDenied => file_glue::ReadErr::PermissionDenied,
        ErrorKind::TimedOut => file_glue::ReadErr::TimedOut,
        // TODO investigate support the following IO errors may need to update API
        // std::io::ErrorKind:: => file_glue::ReadErr::TooManyHardlinks,
        // std::io::ErrorKind:: => file_glue::ReadErr::TooManySymlinks,
        // std::io::ErrorKind:: => file_glue::ReadErr::Unrecognized,
        // std::io::ErrorKind::StaleNetworkFileHandle <- unstable language feature
        // std::io::ErrorKind::InvalidFilename <- unstable language feature
        _ => file_glue::ReadErr::Unsupported,
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpConnect(host: &RocStr, port: u16) -> tcp_glue::ConnectResult {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let reader = BufReader::new(stream);
            let ptr = Box::into_raw(Box::new(reader)) as u64;

            tcp_glue::ConnectResult::Connected(ptr)
        }
        Err(err) => tcp_glue::ConnectResult::Error(to_tcp_connect_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpClose(stream_ptr: *mut BufReader<TcpStream>) {
    unsafe {
        drop(Box::from_raw(stream_ptr));
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUpTo(
    bytes_to_read: usize,
    stream_ptr: *mut BufReader<TcpStream>,
) -> tcp_glue::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            reader.consume(received.len());

            let rocList = RocList::from(&received[..]);
            tcp_glue::ReadResult::Read(rocList)
        }

        Err(err) => tcp_glue::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadExactly(
    bytes_to_read: usize,
    stream_ptr: *mut BufReader<TcpStream>,
) -> tcp_glue::ReadExactlyResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = Vec::with_capacity(bytes_to_read);
    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if read < bytes_to_read {
                tcp_glue::ReadExactlyResult::UnexpectedEOF
            } else {
                let rocList = RocList::from(&buffer[..]);
                tcp_glue::ReadExactlyResult::Read(rocList)
            }
        }

        Err(err) => tcp_glue::ReadExactlyResult::Error(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUntil(
    byte: u8,
    stream_ptr: *mut BufReader<TcpStream>,
) -> tcp_glue::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = vec![];

    match reader.read_until(byte, &mut buffer) {
        Ok(_) => {
            let rocList = RocList::from(&buffer[..]);
            tcp_glue::ReadResult::Read(rocList)
        }

        Err(err) => tcp_glue::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpWrite(
    msg: &RocList<u8>,
    stream_ptr: *mut BufReader<TcpStream>,
) -> tcp_glue::WriteResult {
    let reader = unsafe { &mut *stream_ptr };
    let mut stream = reader.get_ref();

    match stream.write_all(msg.as_slice()) {
        Ok(_) => tcp_glue::WriteResult::Wrote,
        Err(err) => tcp_glue::WriteResult::Error(to_tcp_stream_err(err)),
    }
}

fn to_tcp_connect_err(err: std::io::Error) -> tcp_glue::ConnectErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => tcp_glue::ConnectErr::PermissionDenied,
        ErrorKind::AddrInUse => tcp_glue::ConnectErr::AddrInUse,
        ErrorKind::AddrNotAvailable => tcp_glue::ConnectErr::AddrNotAvailable,
        ErrorKind::ConnectionRefused => tcp_glue::ConnectErr::ConnectionRefused,
        ErrorKind::Interrupted => tcp_glue::ConnectErr::Interrupted,
        ErrorKind::TimedOut => tcp_glue::ConnectErr::TimedOut,
        ErrorKind::Unsupported => tcp_glue::ConnectErr::Unsupported,
        _ => tcp_glue::ConnectErr::Unrecognized(
            RocStr::from(kind.to_string().borrow()),
            err.raw_os_error().unwrap_or_default(),
        ),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> tcp_glue::StreamErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => tcp_glue::StreamErr::PermissionDenied,
        ErrorKind::ConnectionRefused => tcp_glue::StreamErr::ConnectionRefused,
        ErrorKind::ConnectionReset => tcp_glue::StreamErr::ConnectionReset,
        ErrorKind::Interrupted => tcp_glue::StreamErr::Interrupted,
        ErrorKind::OutOfMemory => tcp_glue::StreamErr::OutOfMemory,
        ErrorKind::BrokenPipe => tcp_glue::StreamErr::BrokenPipe,
        _ => tcp_glue::StreamErr::Unrecognized(
            RocStr::from(kind.to_string().borrow()),
            err.raw_os_error().unwrap_or_default(),
        ),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_commandStatus(
    roc_cmd: &command_glue::Command,
) -> RocResult<(), command_glue::CommandErr> {
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
                    Some(code) => {
                        let error = command_glue::CommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = command_glue::CommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            }
        }
        Err(err) => {
            let str = RocStr::from(err.to_string().borrow());
            let error = command_glue::CommandErr::IOError(str);
            RocResult::err(error)
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_commandOutput(roc_cmd: &command_glue::Command) -> command_glue::Output {
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
                    Some(code) => {
                        let error = command_glue::CommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = command_glue::CommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            };

            command_glue::Output {
                status: status,
                stdout: RocList::from(&output.stdout[..]),
                stderr: RocList::from(&output.stderr[..]),
            }
        }
        Err(err) => command_glue::Output {
            status: RocResult::err(command_glue::CommandErr::IOError(RocStr::from(
                err.to_string().borrow(),
            ))),
            stdout: RocList::empty(),
            stderr: RocList::empty(),
        },
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirCreate(roc_path: &RocList<u8>) -> RocResult<(), IOError> {
    match std::fs::create_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(toRocIOError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirCreateAll(roc_path: &RocList<u8>) -> RocResult<(), IOError> {
    match std::fs::create_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(toRocIOError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirDeleteEmpty(roc_path: &RocList<u8>) -> RocResult<(), IOError> {
    match std::fs::remove_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(toRocIOError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dirDeleteAll(roc_path: &RocList<u8>) -> RocResult<(), IOError> {
    match std::fs::remove_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(toRocIOError(err)),
    }
}

// Note commented out error kinds are not available in stable Rust
fn toRocIOError(err: std::io::Error) -> IOError {
    match err.kind() {
        ErrorKind::NotFound => IOError::NotFound(),
        ErrorKind::PermissionDenied => IOError::PermissionDenied(),
        ErrorKind::ConnectionRefused => IOError::ConnectionRefused(),
        ErrorKind::ConnectionReset => IOError::ConnectionReset(),
        // ErrorKind::HostUnreachable => IOError::HostUnreachable(),
        // ErrorKind::NetworkUnreachable => IOError::NetworkUnreachable(),
        ErrorKind::ConnectionAborted => IOError::ConnectionAborted(),
        ErrorKind::NotConnected => IOError::NotConnected(),
        ErrorKind::AddrInUse => IOError::AddrInUse(),
        ErrorKind::AddrNotAvailable => IOError::AddrNotAvailable(),
        // ErrorKind::NetworkDown => IOError::NetworkDown(),
        ErrorKind::BrokenPipe => IOError::BrokenPipe(),
        ErrorKind::AlreadyExists => IOError::AlreadyExists(),
        ErrorKind::WouldBlock => IOError::WouldBlock(),
        // ErrorKind::NotADirectory => IOError::NotADirectory(),
        // ErrorKind::IsADirectory => IOError::IsADirectory(),
        // ErrorKind::DirectoryNotEmpty => IOError::DirectoryNotEmpty(),
        // ErrorKind::ReadOnlyFilesystem => IOError::ReadOnlyFilesystem(),
        // ErrorKind::FilesystemLoop => IOError::FilesystemLoop(),
        // ErrorKind::StaleNetworkFileHandle => IOError::StaleNetworkFileHandle(),
        ErrorKind::InvalidInput => IOError::InvalidInput(),
        ErrorKind::InvalidData => IOError::InvalidData(),
        ErrorKind::TimedOut => IOError::TimedOut(),
        ErrorKind::WriteZero => IOError::WriteZero(),
        // ErrorKind::StorageFull => IOError::StorageFull(),
        // ErrorKind::NotSeekable => IOError::NotSeekable(),
        // ErrorKind::FilesystemQuotaExceeded => IOError::FilesystemQuotaExceeded(),
        // ErrorKind::FileTooLarge => IOError::FileTooLarge(),
        // ErrorKind::ResourceBusy => IOError::ResourceBusy(),
        // ErrorKind::ExecutableFileBusy => IOError::ExecutableFileBusy(),
        // ErrorKind::Deadlock => IOError::Deadlock(),
        // ErrorKind::CrossesDevices => IOError::CrossesDevices(),
        // ErrorKind::TooManyLinks => IOError::TooManyLinks(),
        // ErrorKind::InvalidFilename => IOError::InvalidFilename(),
        // ErrorKind::ArgumentListTooLong => IOError::ArgumentListTooLong(),
        ErrorKind::Interrupted => IOError::Interrupted(),
        ErrorKind::UnexpectedEof => IOError::UnexpectedEof(),
        ErrorKind::OutOfMemory => IOError::OutOfMemory(),
        ErrorKind::Other => IOError::Other(),
        _ => IOError::Unsupported(),
    }
}
