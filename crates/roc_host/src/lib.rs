//! Implementation of the host.
//! The host contains code that calls the Roc main function and provides the
//! Roc app with functions to allocate memory and execute effects such as
//! writing to stdio or making HTTP requests.

#![allow(non_snake_case)]
#![allow(improper_ctypes)]
use core::ffi::c_void;
use roc_io_error::IOErr;
use roc_std::{
    roc_refcounted_noop_impl, ReadOnlyRocList, ReadOnlyRocStr, RocBox, RocList, RocRefcounted,
    RocResult, RocStr,
};
use std::borrow::Borrow;
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::runtime::Runtime;

thread_local! {
   static TOKIO_RUNTIME: Runtime = tokio::runtime::Builder::new_current_thread()
       .enable_io()
       .enable_time()
       .build()
       .unwrap();
}

static ARGS: OnceLock<ReadOnlyRocList<ReadOnlyRocStr>> = OnceLock::new();

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
    let heap = roc_file::heap();
    if heap.in_range(c_ptr) {
        heap.dealloc(c_ptr);
        return;
    }
    let heap = roc_tcp::heap();
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
#[no_mangle]
pub unsafe extern "C" fn roc_expect_failed(
    loc: &RocStr,
    src: &RocStr,
    variables: &RocList<Variable>,
) {
    eprintln!("\nExpectation failed at {}:", loc.as_str());
    eprintln!("\nExpression:\n\t{}\n", src.as_str());

    if !variables.is_empty() {
        eprintln!("With values:");
        for var in variables.iter() {
            eprintln!("\t{} = {}", var.name.as_str(), var.value.as_str());
        }
        eprintln!();
    }

    std::process::exit(1);
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
    ARGS.set(args)
        .unwrap_or_else(|_| panic!("only one thread running, must be able to set args"));
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
    ARGS.get()
        .expect("args was set during init and must be here")
        .clone()
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
    match std::env::set_current_dir(roc_file::path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(_) => RocResult::err(()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_exePath(_roc_str: &RocStr) -> RocResult<RocList<u8>, ()> {
    match std::env::current_exe() {
        Ok(path_buf) => RocResult::ok(roc_file::os_str_to_roc_path(path_buf.as_path().as_os_str())),
        Err(_) => RocResult::err(()),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinLine() -> RocResult<RocStr, roc_io_error::IOErr> {
    roc_stdio::stdin_line()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinBytes() -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_stdio::stdin_bytes()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdinReadToEnd() -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_stdio::stdin_read_to_end()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutLine(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdoutWrite(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrLine(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderrWrite(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_write(text)
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
) -> RocResult<(), IOErr> {
    roc_file::file_write_utf8(roc_path, roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileWriteBytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_write_bytes(roc_path, roc_bytes)
}

#[no_mangle]
pub extern "C" fn roc_fx_pathType(
    roc_path: &RocList<u8>,
) -> RocResult<roc_file::InternalPathType, roc_io_error::IOErr> {
    roc_file::path_type(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReadBytes(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_bytes(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReader(
    roc_path: &RocList<u8>,
    size: u64,
) -> RocResult<RocBox<()>, roc_io_error::IOErr> {
    roc_file::file_reader(roc_path, size)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileReadLine(
    data: RocBox<()>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_line(data)
}

#[no_mangle]
pub extern "C" fn roc_fx_fileDelete(roc_path: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_delete(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_cwd() -> RocResult<RocList<u8>, ()> {
    roc_file::cwd()
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
) -> RocResult<RocList<RocList<u8>>, roc_io_error::IOErr> {
    roc_file::dir_list(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_sendRequest(roc_request: &roc_tcp::Request) -> roc_tcp::InternalResponse {
    TOKIO_RUNTIME.with(|rt| roc_tcp::send_request(rt, roc_request))
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpConnect(host: &RocStr, port: u16) -> RocResult<RocBox<()>, RocStr> {
    roc_tcp::tcp_connect(host, port)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUpTo(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_tcp::tcp_read_up_to(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadExactly(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_tcp::tcp_read_exactly(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpReadUntil(
    stream: RocBox<()>,
    byte: u8,
) -> RocResult<RocList<u8>, RocStr> {
    roc_tcp::tcp_read_until(stream, byte)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcpWrite(stream: RocBox<()>, msg: &RocList<u8>) -> RocResult<(), RocStr> {
    roc_tcp::tcp_write(stream, msg)
}

#[no_mangle]
pub extern "C" fn roc_fx_commandStatus(
    roc_cmd: &roc_command::Command,
) -> RocResult<(), RocList<u8>> {
    roc_command::command_status(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_commandOutput(
    roc_cmd: &roc_command::Command,
) -> roc_command::CommandOutput {
    roc_command::command_output(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_dirCreate(roc_path: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_create(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dirCreateAll(
    roc_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_create_all(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dirDeleteEmpty(
    roc_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_delete_empty(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dirDeleteAll(
    roc_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_delete_all(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_hardLink(
    path_from: &RocList<u8>,
    path_to: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::hard_link(path_from, path_to)
}

#[no_mangle]
pub extern "C" fn roc_fx_currentArchOS() -> ReturnArchOS {
    ReturnArchOS {
        arch: std::env::consts::ARCH.into(),
        os: std::env::consts::OS.into(),
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tempDir() -> RocList<u8> {
    roc_file::temp_dir()
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

#[derive(Debug)]
#[repr(C)]
pub struct ReturnArchOS {
    pub arch: RocStr,
    pub os: RocStr,
}

roc_refcounted_noop_impl!(ReturnArchOS);

#[repr(C)]
pub struct Variable {
    pub name: RocStr,
    pub value: RocStr,
}

impl roc_std::RocRefcounted for Variable {
    fn inc(&mut self) {
        self.name.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
