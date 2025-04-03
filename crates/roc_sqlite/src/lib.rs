//! This crate provides common functionality common functionality for Roc to interface with sqlite.
#![allow(non_snake_case)]

use roc_std::{roc_refcounted_noop_impl, RocBox, RocList, RocRefcounted, RocResult, RocStr};
use roc_std_heap::ThreadSafeRefcountedResourceHeap;
use std::borrow::Borrow;
use std::cell::RefCell;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::sync::OnceLock;
use thread_local::ThreadLocal;

pub fn heap() -> &'static ThreadSafeRefcountedResourceHeap<SqliteStatement> {
    static STMT_HEAP: OnceLock<ThreadSafeRefcountedResourceHeap<SqliteStatement>> = OnceLock::new();
    STMT_HEAP.get_or_init(|| {
        let default_max_stmts = 65536;
        let max_stmts = std::env::var("ROC_BASIC_CLI_MAX_SQLITE_STMTS")
            .map(|v| v.parse().unwrap_or(default_max_stmts))
            .unwrap_or(default_max_stmts);
        ThreadSafeRefcountedResourceHeap::new(max_stmts)
            .expect("Failed to allocate mmap for sqlite statement handle references.")
    })
}

type SqliteConnection = *mut libsqlite3_sys::sqlite3;

// We are guaranteeing that we are using these on single threads.
// This keeps them thread safe.
#[repr(transparent)]
struct UnsafeStmt(*mut libsqlite3_sys::sqlite3_stmt);

unsafe impl Send for UnsafeStmt {}
unsafe impl Sync for UnsafeStmt {}

// This will lazily prepare an sqlite connection on each thread.
pub struct SqliteStatement {
    db_path: RocStr,
    query: RocStr,
    stmt: ThreadLocal<UnsafeStmt>,
}

impl Drop for SqliteStatement {
    fn drop(&mut self) {
        for stmt in self.stmt.iter() {
            unsafe { libsqlite3_sys::sqlite3_finalize(stmt.0) };
        }
    }
}

thread_local! {
    // TODO: Once roc has atomic refcounts and sharing between threads, this really should be managed by roc.
    // We should have a heap of connections just like statements.
    // Each statement will need to keep a reference to the connection it uses.
    // Connections will still need some sort of thread local to enable multithread access (connection per thread).
    static SQLITE_CONNECTIONS : RefCell<Vec<(CString, SqliteConnection)>> = const { RefCell::new(vec![]) };
}

fn get_connection(path: &str) -> Result<SqliteConnection, SqliteError> {
    SQLITE_CONNECTIONS.with(|connections| {
        for (conn_path, connection) in connections.borrow().iter() {
            if path.as_bytes() == conn_path.as_c_str().to_bytes() {
                return Ok(*connection);
            }
        }

        let path = CString::new(path).unwrap();
        let mut connection: SqliteConnection = std::ptr::null_mut();
        // TODO: we should eventually allow users to decide if they want to create a database.
        // This is errorprone and can lead to creating a database when the user wants to open a existing one.
        let flags = libsqlite3_sys::SQLITE_OPEN_CREATE
            | libsqlite3_sys::SQLITE_OPEN_READWRITE
            | libsqlite3_sys::SQLITE_OPEN_NOMUTEX;
        let err = unsafe {
            libsqlite3_sys::sqlite3_open_v2(path.as_ptr(), &mut connection, flags, std::ptr::null())
        };
        if err != libsqlite3_sys::SQLITE_OK {
            return Err(err_from_sqlite_conn(connection, err));
        }

        connections.borrow_mut().push((path, connection));
        Ok(connection)
    })
}

fn thread_local_prepare(
    stmt: &SqliteStatement,
) -> Result<*mut libsqlite3_sys::sqlite3_stmt, SqliteError> {
    // Get the connection
    let connection = {
        match get_connection(stmt.db_path.as_str()) {
            Ok(conn) => conn,
            Err(err) => return Err(err),
        }
    };

    stmt.stmt
        .get_or_try(|| {
            let mut unsafe_stmt = UnsafeStmt(std::ptr::null_mut());
            let err = unsafe {
                libsqlite3_sys::sqlite3_prepare_v2(
                    connection,
                    stmt.query.as_str().as_ptr() as *const c_char,
                    stmt.query.len() as i32,
                    &mut unsafe_stmt.0,
                    std::ptr::null_mut(),
                )
            };
            if err != libsqlite3_sys::SQLITE_OK {
                return Err(err_from_sqlite_conn(connection, err));
            }
            Ok(unsafe_stmt)
        })
        .map(|x| x.0)
}

pub fn prepare(
    db_path: &roc_std::RocStr,
    query: &roc_std::RocStr,
) -> roc_std::RocResult<RocBox<()>, SqliteError> {
    // Prepare the query
    let stmt = SqliteStatement {
        db_path: db_path.clone(),
        query: query.clone(),
        stmt: ThreadLocal::new(),
    };

    // Always prepare once to ensure no errors and prep for current thread.
    if let Err(err) = thread_local_prepare(&stmt) {
        return RocResult::err(err);
    }

    let heap = heap();
    let alloc_result = heap.alloc_for(stmt);
    match alloc_result {
        Ok(out) => RocResult::ok(out),
        Err(_) => RocResult::err(SqliteError {
            code: libsqlite3_sys::SQLITE_NOMEM as i64,
            message: "Ran out of memory allocating space for statement".into(),
        }),
    }
}

pub fn bind(stmt: RocBox<()>, bindings: &RocList<SqliteBindings>) -> RocResult<(), SqliteError> {
    let stmt: &SqliteStatement = ThreadSafeRefcountedResourceHeap::box_to_resource(stmt);

    let local_stmt = thread_local_prepare(stmt)
        .expect("Prepare already succeeded in another thread. Should not fail here");

    // Clear old bindings to ensure the users is setting all bindings
    let err = unsafe { libsqlite3_sys::sqlite3_clear_bindings(local_stmt) };
    if err != libsqlite3_sys::SQLITE_OK {
        return roc_err_from_sqlite_errcode(stmt, err);
    }

    for binding in bindings {
        // TODO: if there is extra capacity in the roc str, zero a byte and use the roc str directly.
        let name = CString::new(binding.name.as_str()).unwrap();
        let index =
            unsafe { libsqlite3_sys::sqlite3_bind_parameter_index(local_stmt, name.as_ptr()) };
        if index == 0 {
            return RocResult::err(SqliteError {
                code: libsqlite3_sys::SQLITE_ERROR as i64,
                message: RocStr::from(format!("unknown paramater: {:?}", name).as_str()),
            });
        }
        let err = match binding.value.discriminant() {
            SqliteValueDiscriminant::Integer => unsafe {
                libsqlite3_sys::sqlite3_bind_int64(
                    local_stmt,
                    index,
                    binding.value.borrow_Integer(),
                )
            },
            SqliteValueDiscriminant::Real => unsafe {
                libsqlite3_sys::sqlite3_bind_double(local_stmt, index, binding.value.borrow_Real())
            },
            SqliteValueDiscriminant::String => unsafe {
                let str = binding.value.borrow_String().as_str();
                let transient = std::mem::transmute::<
                    *const std::ffi::c_void,
                    unsafe extern "C" fn(*mut std::ffi::c_void),
                >(-1isize as *const c_void);
                libsqlite3_sys::sqlite3_bind_text64(
                    local_stmt,
                    index,
                    str.as_ptr() as *const c_char,
                    str.len() as u64,
                    Some(transient),
                    libsqlite3_sys::SQLITE_UTF8 as u8,
                )
            },
            SqliteValueDiscriminant::Bytes => unsafe {
                let str = binding.value.borrow_Bytes().as_slice();
                let transient = std::mem::transmute::<
                    *const std::ffi::c_void,
                    unsafe extern "C" fn(*mut std::ffi::c_void),
                >(-1isize as *const c_void);
                libsqlite3_sys::sqlite3_bind_blob64(
                    local_stmt,
                    index,
                    str.as_ptr() as *const c_void,
                    str.len() as u64,
                    Some(transient),
                )
            },
            SqliteValueDiscriminant::Null => unsafe {
                libsqlite3_sys::sqlite3_bind_null(local_stmt, index)
            },
        };
        if err != libsqlite3_sys::SQLITE_OK {
            return roc_err_from_sqlite_errcode(stmt, err);
        }
    }
    RocResult::ok(())
}

pub fn columns(stmt: RocBox<()>) -> RocList<RocStr> {
    let stmt: &SqliteStatement = ThreadSafeRefcountedResourceHeap::box_to_resource(stmt);

    let local_stmt = thread_local_prepare(stmt)
        .expect("Prepare already succeeded in another thread. Should not fail here");

    let count = unsafe { libsqlite3_sys::sqlite3_column_count(local_stmt) } as usize;
    let mut list = RocList::with_capacity(count);
    for i in 0..count {
        let col_name = unsafe { libsqlite3_sys::sqlite3_column_name(local_stmt, i as c_int) };
        let col_name = unsafe { CStr::from_ptr(col_name) };
        // Both of these should be safe. Sqlite should always return a utf8 string with null terminator.
        let col_name = RocStr::from(col_name.to_string_lossy().borrow());
        list.append(col_name);
    }
    list
}

pub fn column_value(stmt: RocBox<()>, i: u64) -> RocResult<SqliteValue, SqliteError> {
    let stmt: &SqliteStatement = ThreadSafeRefcountedResourceHeap::box_to_resource(stmt);

    let local_stmt = thread_local_prepare(stmt)
        .expect("Prepare already succeeded in another thread. Should not fail here");

    let count = unsafe { libsqlite3_sys::sqlite3_column_count(local_stmt) } as u64;
    if i >= count {
        return RocResult::err(SqliteError {
            code: libsqlite3_sys::SQLITE_ERROR as i64,
            message: RocStr::from(
                format!("column index out of range: {} of {}", i, count).as_str(),
            ),
        });
    }
    let i = i as i32;
    let value = match unsafe { libsqlite3_sys::sqlite3_column_type(local_stmt, i) } {
        libsqlite3_sys::SQLITE_INTEGER => {
            let val = unsafe { libsqlite3_sys::sqlite3_column_int64(local_stmt, i) };
            SqliteValue::Integer(val)
        }
        libsqlite3_sys::SQLITE_FLOAT => {
            let val = unsafe { libsqlite3_sys::sqlite3_column_double(local_stmt, i) };
            SqliteValue::Real(val)
        }
        libsqlite3_sys::SQLITE_TEXT => unsafe {
            let text = libsqlite3_sys::sqlite3_column_text(local_stmt, i);
            let len = libsqlite3_sys::sqlite3_column_bytes(local_stmt, i);
            let slice = std::slice::from_raw_parts(text, len as usize);
            let val = RocStr::from(std::str::from_utf8_unchecked(slice));
            SqliteValue::String(val)
        },
        libsqlite3_sys::SQLITE_BLOB => unsafe {
            let blob = libsqlite3_sys::sqlite3_column_blob(local_stmt, i) as *const u8;
            let len = libsqlite3_sys::sqlite3_column_bytes(local_stmt, i);
            let slice = std::slice::from_raw_parts(blob, len as usize);
            let val = RocList::<u8>::from(slice);
            SqliteValue::Bytes(val)
        },
        libsqlite3_sys::SQLITE_NULL => SqliteValue::Null(),
        _ => unreachable!(),
    };
    RocResult::ok(value)
}

pub fn step(stmt: RocBox<()>) -> RocResult<SqliteState, SqliteError> {
    let stmt: &SqliteStatement = ThreadSafeRefcountedResourceHeap::box_to_resource(stmt);

    let local_stmt = thread_local_prepare(stmt)
        .expect("Prepare already succeeded in another thread. Should not fail here");

    let err = unsafe { libsqlite3_sys::sqlite3_step(local_stmt) };
    if err == libsqlite3_sys::SQLITE_ROW {
        return RocResult::ok(SqliteState::Row);
    }
    if err == libsqlite3_sys::SQLITE_DONE {
        return RocResult::ok(SqliteState::Done);
    }
    roc_err_from_sqlite_errcode(stmt, err)
}

/// Resets a prepared statement back to its initial state, ready to be re-executed.
pub fn reset(stmt: RocBox<()>) -> RocResult<(), SqliteError> {
    let stmt: &SqliteStatement = ThreadSafeRefcountedResourceHeap::box_to_resource(stmt);

    let local_stmt = thread_local_prepare(stmt)
        .expect("Prepare already succeeded in another thread. Should not fail here");

    let err = unsafe { libsqlite3_sys::sqlite3_reset(local_stmt) };
    if err != libsqlite3_sys::SQLITE_OK {
        return roc_err_from_sqlite_errcode(stmt, err);
    }
    RocResult::ok(())
}

fn roc_err_from_sqlite_errcode<T>(
    stmt: &SqliteStatement,
    code: c_int,
) -> RocResult<T, SqliteError> {
    let mut errstr =
        unsafe { CStr::from_ptr(libsqlite3_sys::sqlite3_errstr(code)) }.to_string_lossy();
    // Attempt to grab a more detailed message if it is available.
    if let Ok(conn) = get_connection(stmt.db_path.as_str()) {
        let errmsg = unsafe { libsqlite3_sys::sqlite3_errmsg(conn) };
        if !errmsg.is_null() {
            errstr = unsafe { CStr::from_ptr(errmsg).to_string_lossy() };
        }
    }
    RocResult::err(SqliteError {
        code: code as i64,
        message: RocStr::from(errstr.borrow()),
    })
}

// If a connections fails to be initialized, we have to load the error directly like so.
fn err_from_sqlite_conn(conn: SqliteConnection, code: c_int) -> SqliteError {
    let mut errstr =
        unsafe { CStr::from_ptr(libsqlite3_sys::sqlite3_errstr(code)) }.to_string_lossy();
    // Attempt to grab a more detailed message if it is available.
    let errmsg = unsafe { libsqlite3_sys::sqlite3_errmsg(conn) };
    if !errmsg.is_null() {
        errstr = unsafe { CStr::from_ptr(errmsg).to_string_lossy() };
    }
    SqliteError {
        code: code as i64,
        message: RocStr::from(errstr.borrow()),
    }
}

// ========= Underlying Roc Type representations ==========

#[derive(Clone, Copy, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum SqliteState {
    Done = 0,
    Row = 1,
}

#[derive(Clone, Copy, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum SqliteValueDiscriminant {
    Bytes = 0,
    Integer = 1,
    Null = 2,
    Real = 3,
    String = 4,
}

roc_refcounted_noop_impl!(SqliteValueDiscriminant);

#[repr(C, align(8))]
pub union union_SqliteValue {
    Bytes: core::mem::ManuallyDrop<roc_std::RocList<u8>>,
    Integer: i64,
    Null: (),
    Real: f64,
    String: core::mem::ManuallyDrop<roc_std::RocStr>,
}

impl SqliteValue {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> SqliteValueDiscriminant {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, SqliteValueDiscriminant>(*bytes.as_ptr().add(24))
        }
    }
}

#[repr(C)]
pub struct SqliteValue {
    payload: union_SqliteValue,
    discriminant: SqliteValueDiscriminant,
}

impl SqliteValue {
    pub fn unwrap_Bytes(mut self) -> roc_std::RocList<u8> {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Bytes);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.Bytes) }
    }

    pub fn borrow_Bytes(&self) -> &roc_std::RocList<u8> {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Bytes);
        unsafe { self.payload.Bytes.borrow() }
    }

    pub fn borrow_mut_Bytes(&mut self) -> &mut roc_std::RocList<u8> {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Bytes);
        use core::borrow::BorrowMut;
        unsafe { self.payload.Bytes.borrow_mut() }
    }

    pub fn is_Bytes(&self) -> bool {
        matches!(self.discriminant, SqliteValueDiscriminant::Bytes)
    }

    pub fn unwrap_Integer(self) -> i64 {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Integer);
        unsafe { self.payload.Integer }
    }

    pub fn borrow_Integer(&self) -> i64 {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Integer);
        unsafe { self.payload.Integer }
    }

    pub fn borrow_mut_Integer(&mut self) -> &mut i64 {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Integer);
        unsafe { &mut self.payload.Integer }
    }

    pub fn is_Integer(&self) -> bool {
        matches!(self.discriminant, SqliteValueDiscriminant::Integer)
    }

    pub fn is_Null(&self) -> bool {
        matches!(self.discriminant, SqliteValueDiscriminant::Null)
    }

    pub fn unwrap_Real(self) -> f64 {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Real);
        unsafe { self.payload.Real }
    }

    pub fn borrow_Real(&self) -> f64 {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Real);
        unsafe { self.payload.Real }
    }

    pub fn borrow_mut_Real(&mut self) -> &mut f64 {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::Real);
        unsafe { &mut self.payload.Real }
    }

    pub fn is_Real(&self) -> bool {
        matches!(self.discriminant, SqliteValueDiscriminant::Real)
    }

    pub fn unwrap_String(mut self) -> roc_std::RocStr {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::String);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.String) }
    }

    pub fn borrow_String(&self) -> &roc_std::RocStr {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::String);
        unsafe { self.payload.String.borrow() }
    }

    pub fn borrow_mut_String(&mut self) -> &mut roc_std::RocStr {
        debug_assert_eq!(self.discriminant, SqliteValueDiscriminant::String);
        use core::borrow::BorrowMut;
        unsafe { self.payload.String.borrow_mut() }
    }

    pub fn is_String(&self) -> bool {
        matches!(self.discriminant, SqliteValueDiscriminant::String)
    }
}

impl SqliteValue {
    pub fn Bytes(payload: roc_std::RocList<u8>) -> Self {
        Self {
            discriminant: SqliteValueDiscriminant::Bytes,
            payload: union_SqliteValue {
                Bytes: core::mem::ManuallyDrop::new(payload),
            },
        }
    }

    pub fn Integer(payload: i64) -> Self {
        Self {
            discriminant: SqliteValueDiscriminant::Integer,
            payload: union_SqliteValue { Integer: payload },
        }
    }

    pub fn Null() -> Self {
        Self {
            discriminant: SqliteValueDiscriminant::Null,
            payload: union_SqliteValue { Null: () },
        }
    }

    pub fn Real(payload: f64) -> Self {
        Self {
            discriminant: SqliteValueDiscriminant::Real,
            payload: union_SqliteValue { Real: payload },
        }
    }

    pub fn String(payload: roc_std::RocStr) -> Self {
        Self {
            discriminant: SqliteValueDiscriminant::String,
            payload: union_SqliteValue {
                String: core::mem::ManuallyDrop::new(payload),
            },
        }
    }
}

impl Drop for SqliteValue {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            SqliteValueDiscriminant::Bytes => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.Bytes)
            },
            SqliteValueDiscriminant::Integer => {}
            SqliteValueDiscriminant::Null => {}
            SqliteValueDiscriminant::Real => {}
            SqliteValueDiscriminant::String => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.String)
            },
        }
    }
}

impl roc_std::RocRefcounted for SqliteValue {
    fn inc(&mut self) {
        unimplemented!();
    }
    fn dec(&mut self) {
        unimplemented!();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(C)]
pub struct SqliteBindings {
    pub name: roc_std::RocStr,
    pub value: SqliteValue,
}

impl RocRefcounted for SqliteBindings {
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

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct SqliteError {
    pub code: i64,
    pub message: roc_std::RocStr,
}

impl RocRefcounted for SqliteError {
    fn inc(&mut self) {
        self.message.inc();
    }
    fn dec(&mut self) {
        self.message.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
