#![allow(non_snake_case)]

use core::alloc::Layout;
use core::ffi::c_void;
use core::mem::MaybeUninit;
use roc_std::{RocDict, RocList, RocResult, RocStr};
use std::borrow::{Borrow, Cow};
use std::ffi::OsStr;
use std::fs::File;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::net::UdpSocket;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

extern "C" {
    #[link_name = "roc__mainForHost_1_exposed_generic"]
    pub fn roc_main(output: *mut u8);

    #[link_name = "roc__mainForHost_1_exposed_size"]
    pub fn roc_main_size() -> i64;

    #[link_name = "roc__mainForHost_0_caller"]
    fn call_Fx(flags: *const u8, closure_data: *const u8, output: *mut RocResult<(), i32>);

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

#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: &RocStr, msg: &RocStr, src: &RocStr) {
    eprintln!("[{}] {} = {}", loc, src, msg);
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
        roc_dbg as _,
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
        roc_fx_pathType as _,
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
pub extern "C" fn rust_main() -> i32 {
    init();
    let size = unsafe { roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    unsafe {
        let buffer = std::alloc::alloc(layout);

        roc_main(buffer);

        let out = call_the_closure(buffer);

        std::alloc::dealloc(buffer, layout);

        return out;
    }
}

pub unsafe fn call_the_closure(closure_data_ptr: *const u8) -> i32 {
    // Main always returns an i32. just allocate for that.
    let mut out: RocResult<(), i32> = RocResult::ok(());

    call_Fx(
        // This flags pointer will never get dereferenced
        MaybeUninit::uninit().as_ptr(),
        closure_data_ptr as *const u8,
        &mut out,
    );

    match out.into() {
        Ok(()) => 0,
        Err(exit_code) => exit_code,
    }
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

/// See docs in `platform/Stdin.roc` for descriptions
fn handleStdinErr(io_err: std::io::Error) -> RocStr {
    match io_err.kind() {
        ErrorKind::BrokenPipe => RocStr::from("ErrorKind::BrokenPipe"),
        ErrorKind::UnexpectedEof => RocStr::from("ErrorKind::UnexpectedEof"),
        ErrorKind::InvalidInput => RocStr::from("ErrorKind::InvalidInput"),
        ErrorKind::OutOfMemory => RocStr::from("ErrorKind::OutOfMemory"),
        ErrorKind::Interrupted => RocStr::from("ErrorKind::Interrupted"),
        ErrorKind::Unsupported => RocStr::from("ErrorKind::Unsupported"),
        _ => RocStr::from(RocStr::from(format!("{:?}", io_err).as_str())),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinLine() -> RocResult<RocStr, RocStr> {
    let stdin = std::io::stdin();

    match stdin.lock().lines().next() {
        None => RocResult::err(RocStr::from("EOF")),
        Some(Ok(str)) => RocResult::ok(RocStr::from(str.as_str())),
        Some(Err(io_err)) => RocResult::err(handleStdinErr(io_err)),
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

/// See docs in `platform/Stdout.roc` for descriptions
fn handleStdoutErr(io_err: std::io::Error) -> RocStr {
    match io_err.kind() {
        ErrorKind::BrokenPipe => RocStr::from("ErrorKind::BrokenPipe"),
        ErrorKind::WouldBlock => RocStr::from("ErrorKind::WouldBlock"),
        ErrorKind::WriteZero => RocStr::from("ErrorKind::WriteZero"),
        ErrorKind::Unsupported => RocStr::from("ErrorKind::Unsupported"),
        ErrorKind::Interrupted => RocStr::from("ErrorKind::Interrupted"),
        ErrorKind::OutOfMemory => RocStr::from("ErrorKind::OutOfMemory"),
        _ => RocStr::from(RocStr::from(format!("{:?}", io_err).as_str())),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutLine(line: &RocStr) -> RocResult<(), RocStr> {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(handleStdoutErr)
        .into()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutWrite(text: &RocStr) -> RocResult<(), RocStr> {
    let stdout = std::io::stdout();

    let mut handle = stdout.lock();

    handle
        .write_all(text.as_bytes())
        .and_then(|()| handle.flush())
        .map_err(handleStdoutErr)
        .into()
}

/// See docs in `platform/Stdout.roc` for descriptions
fn handleStderrErr(io_err: std::io::Error) -> RocStr {
    match io_err.kind() {
        ErrorKind::BrokenPipe => RocStr::from("ErrorKind::BrokenPipe"),
        ErrorKind::WouldBlock => RocStr::from("ErrorKind::WouldBlock"),
        ErrorKind::WriteZero => RocStr::from("ErrorKind::WriteZero"),
        ErrorKind::Unsupported => RocStr::from("ErrorKind::Unsupported"),
        ErrorKind::Interrupted => RocStr::from("ErrorKind::Interrupted"),
        ErrorKind::OutOfMemory => RocStr::from("ErrorKind::OutOfMemory"),
        _ => RocStr::from(RocStr::from(format!("{:?}", io_err).as_str())),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrLine(line: &RocStr) -> RocResult<(), RocStr> {
    let stderr = std::io::stderr();

    let mut handle = stderr.lock();

    handle
        .write_all(line.as_bytes())
        .and_then(|()| handle.write_all("\n".as_bytes()))
        .and_then(|()| handle.flush())
        .map_err(handleStderrErr)
        .into()
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrWrite(text: &RocStr) -> RocResult<(), RocStr> {
    let stderr = std::io::stderr();

    let mut handle = stderr.lock();

    handle
        .write_all(text.as_bytes())
        .and_then(|()| handle.flush())
        .map_err(handleStderrErr)
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
) -> RocResult<(), roc_app::WriteErr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteBytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), roc_app::WriteErr> {
    write_slice(roc_path, roc_bytes.as_slice())
}

fn write_slice(roc_path: &RocList<u8>, bytes: &[u8]) -> RocResult<(), roc_app::WriteErr> {
    match File::create(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.write_all(bytes) {
            Ok(()) => RocResult::ok(()),
            Err(err) => RocResult::err(toRocWriteError(err)),
        },
        Err(err) => RocResult::err(toRocWriteError(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_pathType(
    roc_path: &RocList<u8>,
) -> RocResult<roc_app::InternalPathType, roc_app::GetMetadataErr> {
    let path = path_from_roc_path(roc_path);
    match path.symlink_metadata() {
        Ok(m) => RocResult::ok(roc_app::InternalPathType {
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
pub extern "C" fn roc_fx_fileReadBytes(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<u8>, roc_app::ReadErr> {
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
pub extern "C" fn roc_fx_fileDelete(roc_path: &RocList<u8>) -> RocResult<(), roc_app::ReadErr> {
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
    roc_path: &RocList<u8>,
) -> RocResult<RocList<RocList<u8>>, RocStr> {
    let path = path_from_roc_path(roc_path);

    if path.is_dir() {
        let dir = match std::fs::read_dir(path) {
            Ok(dir) => dir,
            Err(err) => return RocResult::err(handleDirError(err)),
        };

        let mut entries = Vec::new();

        for entry in dir {
            match entry {
                Ok(entry) => {
                    let path = entry.path();
                    let str = path.as_os_str();
                    entries.push(os_str_to_roc_path(str));
                }
                Err(_) => {} // TODO should we ignore errors reading directory??
            }
        }

        return roc_std::RocResult::ok(RocList::from_iter(entries));
    } else {
        return roc_std::RocResult::err("ErrorKind::NotADirectory".into());
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

#[no_mangle]
pub extern "C" fn roc_fx_sendRequest(roc_request: &roc_app::Request) -> roc_app::InternalResponse {
    use hyper::Client;
    use hyper_rustls::HttpsConnectorBuilder;

    let https = HttpsConnectorBuilder::new()
        .with_native_roots()
        .https_or_http()
        .enable_http1()
        .build();

    let client: Client<_, String> = Client::builder().build(https);

    let method = match roc_request.method {
        roc_app::Method::Connect => hyper::Method::CONNECT,
        roc_app::Method::Delete => hyper::Method::DELETE,
        roc_app::Method::Get => hyper::Method::GET,
        roc_app::Method::Head => hyper::Method::HEAD,
        roc_app::Method::Options => hyper::Method::OPTIONS,
        roc_app::Method::Patch => hyper::Method::PATCH,
        roc_app::Method::Post => hyper::Method::POST,
        roc_app::Method::Put => hyper::Method::PUT,
        roc_app::Method::Trace => hyper::Method::TRACE,
    };

    let mut req_builder = hyper::Request::builder()
        .method(method)
        .uri(roc_request.url.as_str());
    let mut has_content_type_header = false;

    for header in roc_request.headers.iter() {
        let (name, value) = header.as_Header();
        req_builder = req_builder.header(name.as_str(), value.as_str());
        if name.eq_ignore_ascii_case("Content-Type") {
            has_content_type_header = true;
        }
    }

    let bytes = String::from_utf8(roc_request.body.as_slice().to_vec()).unwrap();
    let mime_type_str = roc_request.mimeType.as_str();

    if !has_content_type_header && mime_type_str.len() > 0 {
        req_builder = req_builder.header("Content-Type", mime_type_str);
    }

    let request = match req_builder.body(bytes) {
        Ok(req) => req,
        Err(err) => {
            return roc_app::InternalResponse::BadRequest(RocStr::from(err.to_string().as_str()));
        }
    };

    let time_limit = if roc_request.timeout.is_TimeoutMilliseconds() {
        let ms: u64 = roc_request.timeout.clone().unwrap_TimeoutMilliseconds();
        Some(Duration::from_millis(ms))
    } else {
        None
    };

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .unwrap();

    let http_fn = async {
        let res = client.request(request).await;

        match res {
            Ok(response) => {
                let status = response.status();
                let status_str = status.canonical_reason().unwrap_or_else(|| status.as_str());

                let headers_iter = response.headers().iter().map(|(name, value)| {
                    roc_app::Header::Header(
                        RocStr::from(name.as_str()),
                        RocStr::from(value.to_str().unwrap_or_default()),
                    )
                });

                let metadata = roc_app::Metadata {
                    headers: RocList::from_iter(headers_iter),
                    statusText: RocStr::from(status_str),
                    url: RocStr::from(roc_request.url.as_str()),
                    statusCode: status.as_u16(),
                };

                let bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
                let body: RocList<u8> = RocList::from_iter(bytes);

                if status.is_success() {
                    // Glue code made this expect a Response_BadStatus? BadStatus and GoodStatus
                    // have the same fields so deduplication makes sense? But possibly a bug?
                    roc_app::InternalResponse::GoodStatus(roc_app::InternalResponse_BadStatus {
                        f0: metadata,
                        f1: body,
                    })
                } else {
                    roc_app::InternalResponse::BadStatus(roc_app::InternalResponse_BadStatus {
                        f0: metadata,
                        f1: body,
                    })
                }
            }
            Err(err) => {
                if err.is_timeout() {
                    roc_app::InternalResponse::Timeout(
                        time_limit.map(|d| d.as_millis()).unwrap_or_default() as u64,
                    )
                } else if err.is_connect() || err.is_closed() {
                    roc_app::InternalResponse::NetworkError()
                } else {
                    roc_app::InternalResponse::BadRequest(RocStr::from(err.to_string().as_str()))
                }
            }
        }
    };
    match time_limit {
        Some(limit) => match rt.block_on(async { tokio::time::timeout(limit, http_fn).await }) {
            Ok(res) => res,
            Err(_) => roc_app::InternalResponse::Timeout(limit.as_millis() as u64),
        },
        None => rt.block_on(http_fn),
    }
}

fn toRocWriteError(err: std::io::Error) -> roc_app::WriteErr {
    match err.kind() {
        ErrorKind::NotFound => roc_app::WriteErr::NotFound(),
        ErrorKind::AlreadyExists => roc_app::WriteErr::AlreadyExists(),
        ErrorKind::Interrupted => roc_app::WriteErr::Interrupted(),
        ErrorKind::OutOfMemory => roc_app::WriteErr::OutOfMemory(),
        ErrorKind::PermissionDenied => roc_app::WriteErr::PermissionDenied(),
        ErrorKind::TimedOut => roc_app::WriteErr::TimedOut(),
        // TODO investigate support the following IO errors may need to update API
        ErrorKind::WriteZero => roc_app::WriteErr::WriteZero(),
        _ => roc_app::WriteErr::Unsupported(),
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

fn toRocReadError(err: std::io::Error) -> roc_app::ReadErr {
    match err.kind() {
        ErrorKind::Interrupted => roc_app::ReadErr::Interrupted(),
        ErrorKind::NotFound => roc_app::ReadErr::NotFound(),
        ErrorKind::OutOfMemory => roc_app::ReadErr::OutOfMemory(),
        ErrorKind::PermissionDenied => roc_app::ReadErr::PermissionDenied(),
        ErrorKind::TimedOut => roc_app::ReadErr::TimedOut(),
        // TODO investigate support the following IO errors may need to update API
        // std::io::ErrorKind:: => roc_app::ReadErr::TooManyHardlinks,
        // std::io::ErrorKind:: => roc_app::ReadErr::TooManySymlinks,
        // std::io::ErrorKind:: => roc_app::ReadErr::Unrecognized,
        // std::io::ErrorKind::StaleNetworkFileHandle <- unstable language feature
        // std::io::ErrorKind::InvalidFilename <- unstable language feature
        _ => roc_app::ReadErr::Unsupported(),
    }
}

fn toRocGetMetadataError(err: std::io::Error) -> roc_app::GetMetadataErr {
    let kind = err.kind();

    let read_err = roc_app::ReadErr_Unrecognized {
        f1: RocStr::from(kind.to_string().borrow()),
        f0: err.raw_os_error().unwrap_or_default(),
    };

    match kind {
        ErrorKind::NotFound => roc_app::GetMetadataErr::PathDoesNotExist(),
        ErrorKind::PermissionDenied => roc_app::GetMetadataErr::PermissionDenied(),
        _ => roc_app::GetMetadataErr::Unrecognized(read_err),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpConnect(host: &RocStr, port: u16) -> roc_app::ConnectResult {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let reader = BufReader::new(stream);
            let ptr = Box::into_raw(Box::new(reader)) as u64;

            roc_app::ConnectResult::Connected(ptr)
        }
        Err(err) => roc_app::ConnectResult::Error(to_tcp_connect_err(err)),
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
    bytes_to_read: u64,
    stream_ptr: *mut BufReader<TcpStream>,
) -> roc_app::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut chunk = reader.take(bytes_to_read);

    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            reader.consume(received.len());

            let rocList = RocList::from(&received[..]);
            roc_app::ReadResult::Read(rocList)
        }

        Err(err) => roc_app::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadExactly(
    bytes_to_read: u64,
    stream_ptr: *mut BufReader<TcpStream>,
) -> roc_app::ReadExactlyResult {
    let reader = unsafe { &mut *stream_ptr };
    let mut buffer = Vec::with_capacity(bytes_to_read as usize);
    let mut chunk = reader.take(bytes_to_read as u64);

    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if (read as u64) < bytes_to_read {
                roc_app::ReadExactlyResult::UnexpectedEOF()
            } else {
                let rocList = RocList::from(&buffer[..]);
                roc_app::ReadExactlyResult::Read(rocList)
            }
        }

        Err(err) => roc_app::ReadExactlyResult::Error(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUntil(
    byte: u8,
    stream_ptr: *mut BufReader<TcpStream>,
) -> roc_app::ReadResult {
    let reader = unsafe { &mut *stream_ptr };

    let mut buffer = vec![];

    match reader.read_until(byte, &mut buffer) {
        Ok(_) => {
            let rocList = RocList::from(&buffer[..]);
            roc_app::ReadResult::Read(rocList)
        }

        Err(err) => roc_app::ReadResult::Error(to_tcp_stream_err(err)),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpWrite(
    msg: &RocList<u8>,
    stream_ptr: *mut BufReader<TcpStream>,
) -> roc_app::WriteResult {
    let reader = unsafe { &mut *stream_ptr };
    let mut stream = reader.get_ref();

    match stream.write_all(msg.as_slice()) {
        Ok(_) => roc_app::WriteResult::Wrote(),
        Err(err) => roc_app::WriteResult::Error(to_tcp_stream_err(err)),
    }
}

fn to_tcp_connect_err(err: std::io::Error) -> roc_app::ConnectErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => roc_app::ConnectErr::PermissionDenied(),
        ErrorKind::AddrInUse => roc_app::ConnectErr::AddrInUse(),
        ErrorKind::AddrNotAvailable => roc_app::ConnectErr::AddrNotAvailable(),
        ErrorKind::ConnectionRefused => roc_app::ConnectErr::ConnectionRefused(),
        ErrorKind::Interrupted => roc_app::ConnectErr::Interrupted(),
        ErrorKind::TimedOut => roc_app::ConnectErr::TimedOut(),
        ErrorKind::Unsupported => roc_app::ConnectErr::Unsupported(),
        _ => roc_app::ConnectErr::Unrecognized(roc_app::ReadErr_Unrecognized {
            f1: RocStr::from(kind.to_string().borrow()),
            f0: err.raw_os_error().unwrap_or_default(),
        }),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> roc_app::StreamErr {
    let kind = err.kind();
    match kind {
        ErrorKind::PermissionDenied => roc_app::StreamErr::PermissionDenied(),
        ErrorKind::ConnectionRefused => roc_app::StreamErr::ConnectionRefused(),
        ErrorKind::ConnectionReset => roc_app::StreamErr::ConnectionReset(),
        ErrorKind::Interrupted => roc_app::StreamErr::Interrupted(),
        ErrorKind::OutOfMemory => roc_app::StreamErr::OutOfMemory(),
        ErrorKind::BrokenPipe => roc_app::StreamErr::BrokenPipe(),
        _ => roc_app::StreamErr::Unrecognized(roc_app::ReadErr_Unrecognized {
            f1: RocStr::from(kind.to_string().borrow()),
            f0: err.raw_os_error().unwrap_or_default(),
        }),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_udpBind(host: &RocStr, port: u16) -> roc_app::BindResult {
    match UdpSocket::bind((host.as_str(), port)) {
        Ok(socket) => {
            let ptr = Box::into_raw(Box::new(socket)) as u64;

            roc_app::BindResult::Bound(ptr)
        }
        Err(err) => roc_app::BindResult::Error(to_udp_bind_err(err)),
    }
}

fn to_udp_bind_err(err: std::io::Error) -> roc_app::BindErr {
    roc_app::BindErr::Nope()
}

#[no_mangle]
pub extern "C" fn roc_fx_commandStatus(
    roc_cmd: &roc_app::Command,
) -> RocResult<(), roc_app::CommandErr> {
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
                        let error = roc_app::CommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = roc_app::CommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            }
        }
        Err(err) => {
            let str = RocStr::from(err.to_string().borrow());
            let error = roc_app::CommandErr::IOError(str);
            RocResult::err(error)
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_commandOutput(roc_cmd: &roc_app::Command) -> roc_app::Output {
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
                        let error = roc_app::CommandErr::ExitCode(code);
                        RocResult::err(error)
                    }
                    None => {
                        // If no exit code is returned, the process was terminated by a signal.
                        let error = roc_app::CommandErr::KilledBySignal();
                        RocResult::err(error)
                    }
                }
            };

            roc_app::Output {
                status: status,
                stdout: RocList::from(&output.stdout[..]),
                stderr: RocList::from(&output.stderr[..]),
            }
        }
        Err(err) => roc_app::Output {
            status: RocResult::err(roc_app::CommandErr::IOError(RocStr::from(
                err.to_string().borrow(),
            ))),
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
        _ => RocStr::from(RocStr::from(format!("{:?}", io_err).as_str())),
    }
}
