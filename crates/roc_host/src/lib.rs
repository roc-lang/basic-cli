//! Implementation of the host.
//! The host contains code that calls the Roc main function and provides the
//! Roc app with functions to allocate memory and execute effects such as
//! writing to stdio or making HTTP requests.

use core::ffi::c_void;
use bytes::Bytes;
use http_body_util::BodyExt;
use hyper_util::rt::TokioExecutor;
use roc_env::arg::ArgToAndFromHost;
use roc_io_error::IOErr;
use roc_std::{RocBox, RocList, RocResult, RocStr};
use std::time::Duration;
use tokio::runtime::Runtime;

thread_local! {
   static TOKIO_RUNTIME: Runtime = tokio::runtime::Builder::new_current_thread()
       .enable_io()
       .enable_time()
       .build()
       .unwrap();
}

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
    let heap = roc_http::heap();
    if heap.in_range(c_ptr) {
        heap.dealloc(c_ptr);
        return;
    }
    // !! If you make any changes to this function, you may also need to update roc_dealloc in
    // https://github.com/roc-lang/basic-webserver
    let heap = roc_sqlite::heap();
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

/// This is not currently used but has been included for a future upgrade to roc
/// to help with debugging and prevent a breaking change for users
/// refer to <https://github.com/roc-lang/roc/issues/6930>
///
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
        roc_fx_env_dict as _,
        roc_fx_env_var as _,
        roc_fx_set_cwd as _,
        roc_fx_exe_path as _,
        roc_fx_stdin_line as _,
        roc_fx_stdin_bytes as _,
        roc_fx_stdin_read_to_end as _,
        roc_fx_stdout_line as _,
        roc_fx_stdout_write as _,
        roc_fx_stdout_write_bytes as _,
        roc_fx_stderr_line as _,
        roc_fx_stderr_write as _,
        roc_fx_stderr_write_bytes as _,
        roc_fx_tty_mode_canonical as _,
        roc_fx_tty_mode_raw as _,
        roc_fx_file_write_utf8 as _,
        roc_fx_file_write_bytes as _,
        roc_fx_path_type as _,
        roc_fx_file_read_bytes as _,
        roc_fx_file_reader as _,
        roc_fx_file_read_line as _,
        roc_fx_file_delete as _,
        roc_fx_file_size_in_bytes as _,
        roc_fx_file_is_executable as _,
        roc_fx_file_is_readable as _,
        roc_fx_file_is_writable as _,
        roc_fx_file_time_accessed as _,
        roc_fx_file_time_modified as _,
        roc_fx_file_time_created as _,
        roc_fx_file_exists as _,
        roc_fx_file_rename as _,
        roc_fx_hard_link as _,
        roc_fx_cwd as _,
        roc_fx_posix_time as _,
        roc_fx_sleep_millis as _,
        roc_fx_dir_list as _,
        roc_fx_send_request as _,
        roc_fx_tcp_connect as _,
        roc_fx_tcp_read_up_to as _,
        roc_fx_tcp_read_exactly as _,
        roc_fx_tcp_read_until as _,
        roc_fx_tcp_write as _,
        roc_fx_command_status as _,
        roc_fx_command_output as _,
        roc_fx_dir_create as _,
        roc_fx_dir_create_all as _,
        roc_fx_dir_delete_empty as _,
        roc_fx_dir_delete_all as _,
        roc_fx_current_arch_os as _,
        roc_fx_temp_dir as _,
        roc_fx_get_locale as _,
        roc_fx_get_locales as _,
        roc_fx_sqlite_bind as _,
        roc_fx_sqlite_column_value as _,
        roc_fx_sqlite_columns as _,
        roc_fx_sqlite_prepare as _,
        roc_fx_sqlite_reset as _,
        roc_fx_sqlite_step as _,
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
pub extern "C" fn rust_main(args: RocList<ArgToAndFromHost>) -> i32 {
    init();

    extern "C" {
        #[link_name = "roc__main_for_host_1_exposed_generic"]
        pub fn roc_main_for_host_caller(
            exit_code: &mut i32,
            args: *const RocList<ArgToAndFromHost>,
        );

        #[link_name = "roc__main_for_host_1_exposed_size"]
        pub fn roc_main__for_host_size() -> usize;
    }

    let exit_code: i32 = unsafe {
        let mut exit_code: i32 = -1;
        let args = args;
        roc_main_for_host_caller(&mut exit_code, &args);

        debug_assert_eq!(std::mem::size_of_val(&exit_code), roc_main__for_host_size());

        // roc now owns the args so prevent the args from being
        // dropped by rust and causing a double free
        std::mem::forget(args);

        exit_code
    };

    exit_code
}

#[no_mangle]
pub extern "C" fn roc_fx_env_dict() -> RocList<(RocStr, RocStr)> {
    roc_env::env_dict()
}

#[no_mangle]
pub extern "C" fn roc_fx_env_var(roc_str: &RocStr) -> RocResult<RocStr, ()> {
    roc_env::env_var(roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_set_cwd(roc_path: &RocList<u8>) -> RocResult<(), ()> {
    roc_env::set_cwd(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_exe_path() -> RocResult<RocList<u8>, ()> {
    roc_env::exe_path()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdin_line() -> RocResult<RocStr, roc_io_error::IOErr> {
    roc_stdio::stdin_line()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdin_bytes() -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_stdio::stdin_bytes()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdin_read_to_end() -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_stdio::stdin_read_to_end()
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_stdout_write_bytes(bytes: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stdout_write_bytes(bytes)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_line(line: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_line(line)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_write(text: &RocStr) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_write(text)
}

#[no_mangle]
pub extern "C" fn roc_fx_stderr_write_bytes(bytes: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_stdio::stderr_write_bytes(bytes)
}

#[no_mangle]
pub extern "C" fn roc_fx_tty_mode_canonical() {
    crossterm::terminal::disable_raw_mode().expect("failed to disable raw mode");
}

#[no_mangle]
pub extern "C" fn roc_fx_tty_mode_raw() {
    crossterm::terminal::enable_raw_mode().expect("failed to enable raw mode");
}

#[no_mangle]
pub extern "C" fn roc_fx_file_write_utf8(
    roc_path: &RocList<u8>,
    roc_str: &RocStr,
) -> RocResult<(), IOErr> {
    roc_file::file_write_utf8(roc_path, roc_str)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_write_bytes(
    roc_path: &RocList<u8>,
    roc_bytes: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_write_bytes(roc_path, roc_bytes)
}

#[no_mangle]
pub extern "C" fn roc_fx_path_type(
    roc_path: &RocList<u8>,
) -> RocResult<roc_file::InternalPathType, roc_io_error::IOErr> {
    roc_file::path_type(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_read_bytes(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_bytes(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_reader(
    roc_path: &RocList<u8>,
    size: u64,
) -> RocResult<RocBox<()>, roc_io_error::IOErr> {
    roc_file::file_reader(roc_path, size)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_read_line(
    data: RocBox<()>,
) -> RocResult<RocList<u8>, roc_io_error::IOErr> {
    roc_file::file_read_line(data)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_delete(roc_path: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_delete(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_size_in_bytes(
    roc_path: &RocList<u8>,
) -> RocResult<u64, roc_io_error::IOErr> {
    roc_file::file_size_in_bytes(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_is_executable(
    roc_path: &RocList<u8>,
) -> RocResult<bool, roc_io_error::IOErr> {
    roc_file::file_is_executable(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_is_readable(
    roc_path: &RocList<u8>,
) -> RocResult<bool, roc_io_error::IOErr> {
    roc_file::file_is_readable(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_is_writable(
    roc_path: &RocList<u8>,
) -> RocResult<bool, roc_io_error::IOErr> {
    roc_file::file_is_writable(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_time_accessed(
    roc_path: &RocList<u8>,
) -> RocResult<roc_std::U128, roc_io_error::IOErr> {
    roc_file::file_time_accessed(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_time_modified(
    roc_path: &RocList<u8>,
) -> RocResult<roc_std::U128, roc_io_error::IOErr> {
    roc_file::file_time_modified(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_time_created(
    roc_path: &RocList<u8>,
) -> RocResult<roc_std::U128, roc_io_error::IOErr> {
    roc_file::file_time_created(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_exists(roc_path: &RocList<u8>) -> RocResult<bool, roc_io_error::IOErr> {
    roc_file::file_exists(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_file_rename(
    from_path: &RocList<u8>,
    to_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::file_rename(from_path, to_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_cwd() -> RocResult<RocList<u8>, ()> {
    roc_env::cwd()
}

#[no_mangle]
pub extern "C" fn roc_fx_posix_time() -> roc_std::U128 {
    roc_env::posix_time()
}

#[no_mangle]
pub extern "C" fn roc_fx_sleep_millis(milliseconds: u64) {
    roc_env::sleep_millis(milliseconds);
}

#[no_mangle]
pub extern "C" fn roc_fx_dir_list(
    roc_path: &RocList<u8>,
) -> RocResult<RocList<RocList<u8>>, roc_io_error::IOErr> {
    roc_file::dir_list(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_send_request(
    roc_request: &roc_http::RequestToAndFromHost,
) -> roc_http::ResponseToAndFromHost {
    TOKIO_RUNTIME.with(|rt| {
        let request = match roc_request.to_hyper_request() {
            Ok(r) => r,
            Err(err) => return err.into(),
        };

        match roc_request.has_timeout() {
            Some(time_limit) => rt
                .block_on(async {
                    tokio::time::timeout(
                        Duration::from_millis(time_limit),
                        async_send_request(request),
                    )
                    .await
                })
                .unwrap_or_else(|_err| roc_http::ResponseToAndFromHost {
                    status: 408,
                    headers: RocList::empty(),
                    body: roc_http::REQUEST_TIMEOUT_BODY.into(),
                }),
            None => rt.block_on(async_send_request(request)),
        }
    })
}

async fn async_send_request(request: hyper::Request<http_body_util::Full<Bytes>>) -> roc_http::ResponseToAndFromHost {
    use hyper_util::client::legacy::Client;
    use hyper_rustls::HttpsConnectorBuilder;

    let https = match HttpsConnectorBuilder::new()
        .with_native_roots()
    {
        Ok(builder) => builder
            .https_or_http()
            .enable_http1()
            .build(),
        Err(_) => {
            return roc_http::ResponseToAndFromHost {
                status: 500,
                headers: RocList::empty(),
                body: "Failed to initialize HTTPS connector with native roots".as_bytes().into(),
            };
        }
    };

    let client: Client<_, http_body_util::Full<Bytes>> =
        Client::builder(TokioExecutor::new()).build(https);
        
    let response_res = client.request(request).await;

    match response_res {
        Ok(response) => {
            let status = response.status();

            let headers = RocList::from_iter(response.headers().iter().map(|(name, value)| {
                roc_http::Header::new(name.as_str(), value.to_str().unwrap_or_default())
            }));

            let status = status.as_u16();

            let bytes_res =
                response.into_body().collect().await.map(|collected| collected.to_bytes());

            match bytes_res {
                Ok(bytes) => {
                    let body: RocList<u8> = RocList::from_iter(bytes);

                    roc_http::ResponseToAndFromHost {
                        body,
                        status,
                        headers,
                    }
                },
                Err(_) => {
                    roc_http::ResponseToAndFromHost {
                        status: 500,
                        headers: RocList::empty(),
                        body: roc_http::REQUEST_BAD_BODY.into(),
                    }
                }
            }
        }
        Err(err) => {
            // TODO match on the error type to provide more specific responses with appropriate status codes
            /*use std::error::Error;
            let err_source_opt = err.source();*/

            roc_http::ResponseToAndFromHost {
                status: 500,
                headers: RocList::empty(),
                body: format!("ERROR:\n{}", err).as_bytes().into(),
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_connect(host: &RocStr, port: u16) -> RocResult<RocBox<()>, RocStr> {
    roc_http::tcp_connect(host, port)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_read_up_to(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_http::tcp_read_up_to(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_read_exactly(
    stream: RocBox<()>,
    bytes_to_read: u64,
) -> RocResult<RocList<u8>, RocStr> {
    roc_http::tcp_read_exactly(stream, bytes_to_read)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_read_until(
    stream: RocBox<()>,
    byte: u8,
) -> RocResult<RocList<u8>, RocStr> {
    roc_http::tcp_read_until(stream, byte)
}

#[no_mangle]
pub extern "C" fn roc_fx_tcp_write(stream: RocBox<()>, msg: &RocList<u8>) -> RocResult<(), RocStr> {
    roc_http::tcp_write(stream, msg)
}

#[no_mangle]
pub extern "C" fn roc_fx_command_status(
    roc_cmd: &roc_command::Command,
) -> RocResult<i32, roc_io_error::IOErr> {
    roc_command::command_status(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_command_output(
    roc_cmd: &roc_command::Command,
) -> roc_command::OutputFromHost {
    roc_command::command_output(roc_cmd)
}

#[no_mangle]
pub extern "C" fn roc_fx_dir_create(roc_path: &RocList<u8>) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_create(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dir_create_all(
    roc_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_create_all(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dir_delete_empty(
    roc_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_delete_empty(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_dir_delete_all(
    roc_path: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::dir_delete_all(roc_path)
}

#[no_mangle]
pub extern "C" fn roc_fx_hard_link(
    path_original: &RocList<u8>,
    path_link: &RocList<u8>,
) -> RocResult<(), roc_io_error::IOErr> {
    roc_file::hard_link(path_original, path_link)
}

#[no_mangle]
pub extern "C" fn roc_fx_current_arch_os() -> roc_env::ReturnArchOS {
    roc_env::current_arch_os()
}

#[no_mangle]
pub extern "C" fn roc_fx_temp_dir() -> RocList<u8> {
    roc_env::temp_dir()
}

#[no_mangle]
pub extern "C" fn roc_fx_get_locale() -> RocResult<RocStr, ()> {
    roc_env::get_locale()
}

#[no_mangle]
pub extern "C" fn roc_fx_get_locales() -> RocList<RocStr> {
    roc_env::get_locales()
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_bind(
    stmt: RocBox<()>,
    bindings: &RocList<roc_sqlite::SqliteBindings>,
) -> RocResult<(), roc_sqlite::SqliteError> {
    roc_sqlite::bind(stmt, bindings)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_prepare(
    db_path: &roc_std::RocStr,
    query: &roc_std::RocStr,
) -> roc_std::RocResult<RocBox<()>, roc_sqlite::SqliteError> {
    roc_sqlite::prepare(db_path, query)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_columns(stmt: RocBox<()>) -> RocList<RocStr> {
    roc_sqlite::columns(stmt)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_column_value(
    stmt: RocBox<()>,
    i: u64,
) -> RocResult<roc_sqlite::SqliteValue, roc_sqlite::SqliteError> {
    roc_sqlite::column_value(stmt, i)
}

#[no_mangle]
pub extern "C" fn roc_fx_sqlite_step(
    stmt: RocBox<()>,
) -> RocResult<roc_sqlite::SqliteState, roc_sqlite::SqliteError> {
    roc_sqlite::step(stmt)
}

/// Resets a prepared statement back to its initial state, ready to be re-executed.
#[no_mangle]
pub extern "C" fn roc_fx_sqlite_reset(stmt: RocBox<()>) -> RocResult<(), roc_sqlite::SqliteError> {
    roc_sqlite::reset(stmt)
}
