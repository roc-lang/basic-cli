//! SQLite connections and running statements behind `Sqlite.Db` and the
//! stream returned by `Sqlite.Db.rows`.
//!
//! # Ownership
//!
//! A `Db` handle owns a reference to a [`Connection`]; so does every [`Cursor`]
//! (a statement that is being stepped). The native connection is closed when
//! the last of them is released, or earlier by `close!`, so the handles can be
//! released in any order.
//!
//! Every prepared statement belongs to its connection, never to a cursor: it is
//! either idle in the connection's cache or listed as active while a cursor
//! steps it. Closing finalizes both sets and clears the connection pointer. A
//! cursor therefore never touches its statement without first checking that the
//! connection is still open, and reports `Closed` when it is not.
use core::mem::ManuallyDrop;
use std::cell::{Cell as LocalCell, RefCell};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::rc::Rc;
use std::time::{Duration, Instant};

use libsqlite3_sys as ffi;

use crate::roc_platform_abi::*;
use crate::{roc_host, roc_u8_list_from_slice};

/// Idle prepared statements kept per connection.
const MAX_CACHED_STATEMENTS: usize = 32;

// libsqlite3-sys 0.33 deliberately omits this stable SQLite API from its Rust
// bindings, although the bundled SQLite library exports it.
extern "C" {
    fn sqlite3_close_v2(connection: *mut ffi::sqlite3) -> c_int;
}

/// An error reported by SQLite. The code is never `SQLITE_OK`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Failure {
    extended_code: c_int,
    message: String,
}

impl Failure {
    fn new(code: c_int, message: impl Into<String>) -> Self {
        debug_assert_ne!(code, ffi::SQLITE_OK);
        Self {
            // A failure must not carry the success code, whatever SQLite said.
            extended_code: if code == ffi::SQLITE_OK {
                ffi::SQLITE_ERROR
            } else {
                code
            },
            message: message.into(),
        }
    }
}

/// Why a statement was not run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Problem {
    Interrupted,
    Failed(Failure),
    Closed,
    WrongParamCount { expected: u64, given: u64 },
    ReturnsRows,
    MultipleStatements,
}

impl From<Failure> for Problem {
    fn from(failure: Failure) -> Self {
        Problem::Failed(failure)
    }
}

/// Why a cursor produced no row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum StepError {
    Interrupted,
    Closed,
    Failed(Failure),
}

// The names are the public ones, `Sqlite.OpenOptions.mode`.
#[allow(clippy::enum_variant_names)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Mode {
    ReadWriteCreate,
    ReadWrite,
    ReadOnly,
}

/// A value to bind, borrowed from the caller; SQLite copies it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum Param<'a> {
    Null,
    Integer(i64),
    Real(f64),
    Text(&'a str),
    Blob(&'a [u8]),
}

/// A column of the current row, borrowed from SQLite until the next step.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum Cell<'a> {
    Null,
    Integer(i64),
    Real(f64),
    /// The stored bytes, which SQLite does not require to be valid UTF-8.
    Text(&'a [u8]),
    Blob(&'a [u8]),
}

// These callbacks execute synchronously inside SQLite. Their stable context is
// outside State's RefCell: borrowing State again from a callback would panic.
struct Callbacks {
    timeout: LocalCell<Duration>,
    busy_started: LocalCell<Option<Instant>>,
    cancelled: LocalCell<bool>,
    cleanup_depth: LocalCell<u32>,
    busy_setting: LocalCell<bool>,
}
impl Callbacks {
    fn pending(&self) -> bool {
        self.cleanup_depth.get() == 0 && crate::signals::is_pending()
    }
    fn begin(&self) -> Result<(), Problem> {
        self.cancelled.set(false);
        self.busy_started.set(None);
        if self.pending() {
            Err(Problem::Interrupted)
        } else {
            Ok(())
        }
    }
}
struct Cleanup<'a>(&'a Callbacks);
impl<'a> Cleanup<'a> {
    fn new(callbacks: &'a Callbacks) -> Self {
        callbacks
            .cleanup_depth
            .set(callbacks.cleanup_depth.get() + 1);
        Self(callbacks)
    }
}
impl Drop for Cleanup<'_> {
    fn drop(&mut self) {
        self.0.cleanup_depth.set(self.0.cleanup_depth.get() - 1);
    }
}
unsafe extern "C" fn progress(context: *mut c_void) -> c_int {
    let callbacks = unsafe { &*context.cast::<Callbacks>() };
    if callbacks.pending() {
        callbacks.cancelled.set(true);
        1
    } else {
        0
    }
}
unsafe extern "C" fn busy(context: *mut c_void, count: c_int) -> c_int {
    let callbacks = unsafe { &*context.cast::<Callbacks>() };
    if callbacks.pending() {
        callbacks.cancelled.set(true);
        return 0;
    }
    let start = if count == 0 {
        let now = Instant::now();
        callbacks.busy_started.set(Some(now));
        now
    } else {
        callbacks.busy_started.get().unwrap_or_else(Instant::now)
    };
    let left = callbacks.timeout.get().saturating_sub(start.elapsed());
    if left.is_zero() {
        return 0;
    }
    let wait = left.min(Duration::from_millis(10));
    if callbacks.cleanup_depth.get() != 0 {
        std::thread::sleep(wait);
    } else if !crate::signals::wait_for(wait) {
        callbacks.cancelled.set(true);
        return 0;
    }
    1
}
unsafe extern "C" fn authorize(
    context: *mut c_void,
    action: c_int,
    name: *const c_char,
    value: *const c_char,
    _database: *const c_char,
    _trigger: *const c_char,
) -> c_int {
    if action == ffi::SQLITE_PRAGMA
        && !name.is_null()
        && !value.is_null()
        && unsafe { CStr::from_ptr(name) }
            .to_bytes()
            .eq_ignore_ascii_case(b"busy_timeout")
    {
        unsafe { &*context.cast::<Callbacks>() }
            .busy_setting
            .set(true);
    }
    ffi::SQLITE_OK
}

struct IdleStatement {
    sql: String,
    stmt: *mut ffi::sqlite3_stmt,
}

struct State {
    /// Null once the connection has been closed.
    raw: *mut ffi::sqlite3,
    /// Reset statements ready for reuse, least recently used first.
    idle: Vec<IdleStatement>,
    /// Statements being stepped by a cursor.
    active: Vec<*mut ffi::sqlite3_stmt>,
    /// How many statements have been prepared for the cache, for tests.
    prepared: u64,
    callbacks: *const Callbacks,
    uncached: Vec<*mut ffi::sqlite3_stmt>,
}

pub(crate) struct Connection {
    state: RefCell<State>,
    callbacks: Box<Callbacks>,
}

/// The value behind a `Resource.SqliteDb` handle.
pub(crate) struct SqliteDb(Rc<Connection>);

/// The value behind a `Resource.SqliteRows` handle.
pub(crate) struct SqliteRows(Cursor);

fn sqlite_transient() -> ffi::sqlite3_destructor_type {
    Some(unsafe {
        core::mem::transmute::<*const c_void, unsafe extern "C" fn(*mut c_void)>(
            -1isize as *const c_void,
        )
    })
}

/// The message for the connection's most recent failure, or the generic text
/// for `code` where there is no connection.
fn error_message(raw: *mut ffi::sqlite3, code: c_int) -> String {
    unsafe {
        let text = if raw.is_null() {
            ffi::sqlite3_errstr(code)
        } else {
            ffi::sqlite3_errmsg(raw)
        };
        if text.is_null() {
            String::from("unknown SQLite error")
        } else {
            CStr::from_ptr(text).to_string_lossy().into_owned()
        }
    }
}

/// Whether `sql` holds nothing SQLite would run: only white space, comments
/// and empty statements. Anything that is not known to be nothing counts as a
/// statement, including text that does not parse.
fn holds_statement(state: &State, sql: &[u8]) -> Result<bool, Problem> {
    let mut rest = sql;
    while !rest.is_empty() {
        let (stmt, tail, _) = match state.prepare(rest) {
            Ok(prepared) => prepared,
            Err(Problem::Interrupted) => return Err(Problem::Interrupted),
            Err(_) => return Ok(true),
        };
        if !stmt.is_null() {
            unsafe { ffi::sqlite3_finalize(stmt) };
            return Ok(true);
        }
        let consumed = (tail as usize).saturating_sub(rest.as_ptr() as usize);
        if tail.is_null() || consumed == 0 || consumed > rest.len() {
            return Ok(false);
        }
        rest = &rest[consumed..];
    }
    Ok(false)
}

fn check_sql_text(sql: &str) -> Result<(), Failure> {
    if sql.as_bytes().contains(&0) {
        // SQLite would stop reading at the NUL and ignore the rest.
        return Err(Failure::new(
            ffi::SQLITE_ERROR,
            "SQL text contains a NUL byte",
        ));
    }
    if sql.len() > c_int::MAX as usize {
        return Err(Failure::new(ffi::SQLITE_TOOBIG, "SQL text is too long"));
    }
    Ok(())
}

impl State {
    fn failure(&self, code: c_int) -> Failure {
        Failure::new(code, error_message(self.raw, code))
    }

    fn callbacks(&self) -> &Callbacks {
        unsafe { &*self.callbacks }
    }
    fn problem(&self, code: c_int) -> Problem {
        if code & 0xff == ffi::SQLITE_INTERRUPT
            || (self.callbacks().cancelled.get()
                && matches!(code & 0xff, ffi::SQLITE_BUSY | ffi::SQLITE_LOCKED))
        {
            Problem::Interrupted
        } else {
            Problem::Failed(self.failure(code))
        }
    }
    // busy_timeout setters take effect during prepare, not step. Read the new
    // native budget and restore our handler before any following statement.
    fn reconcile_busy(&self) -> Result<bool, Problem> {
        let callbacks = self.callbacks();
        if !callbacks.busy_setting.replace(false) {
            return Ok(false);
        }
        let _cleanup = Cleanup::new(callbacks);
        let mut stmt = std::ptr::null_mut();
        let code = unsafe {
            ffi::sqlite3_prepare_v2(
                self.raw,
                c"PRAGMA busy_timeout".as_ptr(),
                -1,
                &mut stmt,
                std::ptr::null_mut(),
            )
        };
        let result = if code == ffi::SQLITE_OK && !stmt.is_null() {
            let code = unsafe { ffi::sqlite3_step(stmt) };
            if code == ffi::SQLITE_ROW {
                callbacks.timeout.set(Duration::from_millis(
                    unsafe { ffi::sqlite3_column_int64(stmt, 0) }.max(0) as u64,
                ));
                Ok(true)
            } else {
                Err(self.problem(code))
            }
        } else {
            Err(self.problem(code))
        };
        if !stmt.is_null() {
            unsafe { ffi::sqlite3_finalize(stmt) };
        }
        unsafe {
            ffi::sqlite3_busy_handler(self.raw, Some(busy), self.callbacks.cast_mut().cast());
        }
        result
    }
    fn prepare(
        &self,
        sql: &[u8],
    ) -> Result<(*mut ffi::sqlite3_stmt, *const c_char, bool), Problem> {
        if self.callbacks().pending() {
            return Err(Problem::Interrupted);
        }
        let mut stmt = std::ptr::null_mut();
        let mut tail = std::ptr::null();
        let code = unsafe {
            ffi::sqlite3_prepare_v2(
                self.raw,
                sql.as_ptr().cast(),
                sql.len() as c_int,
                &mut stmt,
                &mut tail,
            )
        };
        let changed = if code == ffi::SQLITE_OK {
            self.reconcile_busy()
        } else {
            // A failed preparation may have reached the PRAGMA authorizer
            // before applying the setter. Preserve our previous budget and
            // restore the callback without replacing the original failure.
            if self.callbacks().busy_setting.replace(false) {
                unsafe {
                    ffi::sqlite3_busy_handler(
                        self.raw,
                        Some(busy),
                        self.callbacks.cast_mut().cast(),
                    );
                }
            }
            Ok(false)
        };
        if code != ffi::SQLITE_OK || changed.is_err() {
            if !stmt.is_null() {
                unsafe { ffi::sqlite3_finalize(stmt) };
            }
            return if code != ffi::SQLITE_OK {
                Err(self.problem(code))
            } else {
                Err(changed.unwrap_err())
            };
        }
        Ok((stmt, tail, changed.unwrap()))
    }

    /// Take the statement for `sql` out of the cache, preparing it on a miss.
    ///
    /// `None` means the text holds no statement. Text holding more than one is
    /// refused, so a cached statement always stands for its whole text.
    fn checkout(&mut self, sql: &str) -> Result<Option<*mut ffi::sqlite3_stmt>, Problem> {
        if self.raw.is_null() {
            return Err(Problem::Closed);
        }
        if let Some(index) = self.idle.iter().position(|idle| idle.sql == sql) {
            return Ok(Some(self.idle.remove(index).stmt));
        }

        check_sql_text(sql)?;
        let mut rest = sql.as_bytes();
        let mut found: *mut ffi::sqlite3_stmt = core::ptr::null_mut();
        // Empty statements (a lone `;`, a comment) may come before the real one.
        while found.is_null() && !rest.is_empty() {
            let (stmt, tail, changed) = self.prepare(rest)?;
            found = stmt;
            if changed && !stmt.is_null() {
                self.uncached.push(stmt);
            }
            let consumed = (tail as usize).saturating_sub(rest.as_ptr() as usize);
            if tail.is_null() || consumed == 0 || consumed > rest.len() {
                rest = &[];
            } else {
                rest = &rest[consumed..];
            }
        }
        if found.is_null() {
            return Ok(None);
        }
        match holds_statement(self, rest) {
            Ok(false) => {}
            result => {
                self.uncached.retain(|stmt| *stmt != found);
                unsafe { ffi::sqlite3_finalize(found) };
                return match result {
                    Err(error) => Err(error),
                    _ => Err(Problem::MultipleStatements),
                };
            }
        }
        self.prepared += 1;
        Ok(Some(found))
    }

    /// Reset a statement and put it back in the cache as the most recently
    /// used, finalizing the least recently used beyond the limit.
    fn checkin(&mut self, sql: &str, stmt: *mut ffi::sqlite3_stmt) {
        debug_assert!(!self.raw.is_null());
        unsafe {
            // The result repeats the error of the last step, already reported.
            ffi::sqlite3_reset(stmt);
            // Do not keep the caller's values alive in an idle statement.
            ffi::sqlite3_clear_bindings(stmt);
        }
        if let Some(index) = self.uncached.iter().position(|cached| *cached == stmt) {
            self.uncached.swap_remove(index);
            unsafe { ffi::sqlite3_finalize(stmt) };
            return;
        }
        if self.idle.iter().any(|idle| idle.sql == sql) {
            // Two cursors ran the same text at once; one statement is enough.
            unsafe { ffi::sqlite3_finalize(stmt) };
            return;
        }
        self.idle.push(IdleStatement {
            sql: sql.to_owned(),
            stmt,
        });
        while self.idle.len() > MAX_CACHED_STATEMENTS {
            let evicted = self.idle.remove(0);
            unsafe { ffi::sqlite3_finalize(evicted.stmt) };
        }
    }

    /// Check the number of values against the statement and bind them.
    fn bind(&self, stmt: *mut ffi::sqlite3_stmt, params: &[Param]) -> Result<(), Problem> {
        let expected = unsafe { ffi::sqlite3_bind_parameter_count(stmt) }.max(0) as u64;
        if expected != params.len() as u64 {
            return Err(Problem::WrongParamCount {
                expected,
                given: params.len() as u64,
            });
        }
        for (position, param) in params.iter().enumerate() {
            // Checked against the statement's own count, which fits a c_int.
            let index = (position + 1) as c_int;
            let code = unsafe {
                match *param {
                    Param::Null => ffi::sqlite3_bind_null(stmt, index),
                    Param::Integer(value) => ffi::sqlite3_bind_int64(stmt, index, value),
                    Param::Real(value) => ffi::sqlite3_bind_double(stmt, index, value),
                    Param::Text(text) => ffi::sqlite3_bind_text64(
                        stmt,
                        index,
                        text.as_ptr().cast(),
                        text.len() as u64,
                        sqlite_transient(),
                        ffi::SQLITE_UTF8 as u8,
                    ),
                    Param::Blob(bytes) => ffi::sqlite3_bind_blob64(
                        stmt,
                        index,
                        bytes.as_ptr().cast(),
                        bytes.len() as u64,
                        sqlite_transient(),
                    ),
                }
            };
            if code != ffi::SQLITE_OK {
                return Err(self.failure(code).into());
            }
        }
        Ok(())
    }

    fn close(&mut self) -> Result<(), Failure> {
        if self.raw.is_null() {
            return Ok(());
        }
        unsafe {
            ffi::sqlite3_progress_handler(self.raw, 0, None, std::ptr::null_mut());
            ffi::sqlite3_busy_handler(self.raw, None, std::ptr::null_mut());
            ffi::sqlite3_set_authorizer(self.raw, None, std::ptr::null_mut());
        }
        self.uncached.clear();
        for idle in self.idle.drain(..) {
            unsafe { ffi::sqlite3_finalize(idle.stmt) };
        }
        for stmt in self.active.drain(..) {
            unsafe { ffi::sqlite3_finalize(stmt) };
        }
        let code = unsafe { ffi::sqlite3_close(self.raw) };
        let result = if code == ffi::SQLITE_OK {
            Ok(())
        } else {
            // Not expected once every statement is finalized. Report it, and
            // let SQLite free the connection when whatever holds it lets go.
            let failure = self.failure(code);
            unsafe { sqlite3_close_v2(self.raw) };
            Err(failure)
        };
        self.raw = core::ptr::null_mut();
        result
    }
}

impl Connection {
    /// Open a new connection. `path` is UTF-8, or the OS's bytes on Unix.
    pub(crate) fn open(
        path: &CStr,
        mode: Mode,
        busy_timeout: Duration,
    ) -> Result<Rc<Self>, Failure> {
        if crate::signals::is_pending() {
            return Err(Failure::new(ffi::SQLITE_INTERRUPT, "operation interrupted"));
        }
        let access = match mode {
            Mode::ReadWriteCreate => ffi::SQLITE_OPEN_READWRITE | ffi::SQLITE_OPEN_CREATE,
            Mode::ReadWrite => ffi::SQLITE_OPEN_READWRITE,
            Mode::ReadOnly => ffi::SQLITE_OPEN_READONLY,
        };
        // Roc runs on one thread, so the connection needs no mutex of its own.
        let flags = access | ffi::SQLITE_OPEN_NOMUTEX | ffi::SQLITE_OPEN_EXRESCODE;
        let mut raw: *mut ffi::sqlite3 = core::ptr::null_mut();
        let code =
            unsafe { ffi::sqlite3_open_v2(path.as_ptr(), &mut raw, flags, core::ptr::null()) };
        if code != ffi::SQLITE_OK {
            // SQLite returns a connection even when opening fails, unless it
            // could not allocate one; it carries the message and must be closed.
            let extended = if raw.is_null() {
                code
            } else {
                unsafe { ffi::sqlite3_extended_errcode(raw) }
            };
            let failure = Failure::new(extended, error_message(raw, code));
            unsafe { sqlite3_close_v2(raw) };
            return Err(failure);
        }
        let callbacks = Box::new(Callbacks {
            timeout: LocalCell::new(busy_timeout),
            busy_started: LocalCell::new(None),
            cancelled: LocalCell::new(false),
            cleanup_depth: LocalCell::new(0),
            busy_setting: LocalCell::new(false),
        });
        let context = (&*callbacks as *const Callbacks).cast_mut().cast();
        unsafe {
            ffi::sqlite3_extended_result_codes(raw, 1);
            ffi::sqlite3_progress_handler(raw, 1000, Some(progress), context);
            ffi::sqlite3_busy_handler(raw, Some(busy), context);
            ffi::sqlite3_set_authorizer(raw, Some(authorize), context);
        }
        Ok(Rc::new(Self {
            state: RefCell::new(State {
                raw,
                idle: Vec::new(),
                active: Vec::new(),
                prepared: 0,
                callbacks: &*callbacks,
                uncached: Vec::new(),
            }),
            callbacks,
        }))
    }

    /// Close the connection now. Closing a closed connection succeeds.
    pub(crate) fn close(&self) -> Result<(), Failure> {
        self.state.borrow_mut().close()
    }

    /// Run one statement that has no result columns.
    pub(crate) fn execute(&self, sql: &str, params: &[Param]) -> Result<(), Problem> {
        self.callbacks.begin()?;
        let mut state = self.state.borrow_mut();
        let Some(stmt) = state.checkout(sql)? else {
            return if params.is_empty() {
                Ok(())
            } else {
                Err(Problem::WrongParamCount {
                    expected: 0,
                    given: params.len() as u64,
                })
            };
        };
        let result = if unsafe { ffi::sqlite3_column_count(stmt) } > 0 {
            Err(Problem::ReturnsRows)
        } else {
            state.bind(stmt, params).and_then(|()| {
                // A statement without result columns produces no row.
                match unsafe { ffi::sqlite3_step(stmt) } {
                    ffi::SQLITE_DONE | ffi::SQLITE_ROW => Ok(()),
                    code => Err(state.problem(code)),
                }
            })
        };
        state.checkin(sql, stmt);
        result
    }

    /// Run every statement in `sql`, discarding any rows.
    pub(crate) fn execute_script(&self, sql: &str) -> Result<(), Problem> {
        self.callbacks.begin()?;
        let state = self.state.borrow();
        if state.raw.is_null() {
            return Err(Problem::Closed);
        }
        check_sql_text(sql)?;
        let mut rest = sql.as_bytes();
        while !rest.is_empty() {
            let (stmt, tail, _) = state.prepare(rest)?;
            let consumed = (tail as usize).saturating_sub(rest.as_ptr() as usize);
            if !stmt.is_null() {
                let result = loop {
                    if self.callbacks.pending() {
                        break Err(Problem::Interrupted);
                    }
                    let code = unsafe { ffi::sqlite3_step(stmt) };
                    match code {
                        ffi::SQLITE_ROW => {}
                        ffi::SQLITE_DONE => break Ok(()),
                        code => break Err(state.problem(code)),
                    }
                };
                unsafe { ffi::sqlite3_finalize(stmt) };
                result?;
            }
            if consumed == 0 || consumed > rest.len() {
                break;
            }
            rest = &rest[consumed..];
        }
        Ok(())
    }

    /// Fixed cleanup operation; never acknowledges the application's signal.
    pub(crate) fn rollback_cleanup(&self) -> Result<(), Problem> {
        let _cleanup = Cleanup::new(&self.callbacks);
        let active = {
            let state = self.state.borrow();
            if state.raw.is_null() {
                return Err(Problem::Closed);
            }
            unsafe { ffi::sqlite3_get_autocommit(state.raw) == 0 }
        };
        if active {
            self.execute("ROLLBACK", &[])
        } else {
            Ok(())
        }
    }

    /// Prepare and bind a statement, ready to be stepped.
    pub(crate) fn query(self: &Rc<Self>, sql: &str, params: &[Param]) -> Result<Cursor, Problem> {
        self.callbacks.begin()?;
        let mut state = self.state.borrow_mut();
        let Some(stmt) = state.checkout(sql)? else {
            if !params.is_empty() {
                return Err(Problem::WrongParamCount {
                    expected: 0,
                    given: params.len() as u64,
                });
            }
            return Ok(Cursor {
                connection: Rc::clone(self),
                stmt: core::ptr::null_mut(),
                sql: String::new(),
            });
        };
        if let Err(problem) = state.bind(stmt, params) {
            state.checkin(sql, stmt);
            return Err(problem);
        }
        state.active.push(stmt);
        Ok(Cursor {
            connection: Rc::clone(self),
            stmt,
            sql: sql.to_owned(),
        })
    }

    #[cfg(test)]
    fn cached(&self) -> Vec<String> {
        let state = self.state.borrow();
        state.idle.iter().map(|idle| idle.sql.clone()).collect()
    }

    #[cfg(test)]
    fn prepared(&self) -> u64 {
        self.state.borrow().prepared
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        let _ = self.state.get_mut().close();
    }
}

/// A bound statement being stepped through its rows.
pub(crate) struct Cursor {
    connection: Rc<Connection>,
    /// Null when the text held no statement, and once the cursor has finished.
    /// Not to be used without checking that the connection is still open.
    stmt: *mut ffi::sqlite3_stmt,
    sql: String,
}

impl Cursor {
    /// The statement, if the connection is open and the cursor has not
    /// finished. Forgets the statement when the connection has finalized it.
    fn live_stmt(&mut self) -> Result<Option<*mut ffi::sqlite3_stmt>, StepError> {
        if self.connection.state.borrow().raw.is_null() {
            self.stmt = core::ptr::null_mut();
            return Err(StepError::Closed);
        }
        Ok((!self.stmt.is_null()).then_some(self.stmt))
    }

    /// The names of the result columns; none when the text held no statement.
    pub(crate) fn column_names(&mut self) -> Vec<String> {
        let Ok(Some(stmt)) = self.live_stmt() else {
            return Vec::new();
        };
        let count = unsafe { ffi::sqlite3_column_count(stmt) }.max(0);
        (0..count)
            .map(|index| unsafe {
                let name = ffi::sqlite3_column_name(stmt, index);
                if name.is_null() {
                    String::new()
                } else {
                    CStr::from_ptr(name).to_string_lossy().into_owned()
                }
            })
            .collect()
    }

    /// Advance to the next row. `Ok(false)` is the end; the statement then
    /// goes back to the cache, as it does after a failure.
    pub(crate) fn step(&mut self) -> Result<bool, StepError> {
        let Some(stmt) = self.live_stmt()? else {
            return Ok(false);
        };
        if let Err(Problem::Interrupted) = self.connection.callbacks.begin() {
            self.finish();
            return Err(StepError::Interrupted);
        }
        match unsafe { ffi::sqlite3_step(stmt) } {
            ffi::SQLITE_ROW => Ok(true),
            ffi::SQLITE_DONE => {
                self.finish();
                Ok(false)
            }
            code => {
                let problem = self.connection.state.borrow().problem(code);
                self.finish();
                match problem {
                    Problem::Interrupted => Err(StepError::Interrupted),
                    Problem::Failed(failure) => Err(StepError::Failed(failure)),
                    _ => unreachable!(),
                }
            }
        }
    }

    /// How many columns the current row has.
    pub(crate) fn column_count(&mut self) -> usize {
        match self.live_stmt() {
            Ok(Some(stmt)) => unsafe { ffi::sqlite3_data_count(stmt) }.max(0) as usize,
            _ => 0,
        }
    }

    /// A column of the current row, valid until the cursor is stepped again.
    /// Call it only after `step` returned `Ok(true)`, with `index` below
    /// `column_count`.
    pub(crate) fn cell(&mut self, index: usize) -> Cell<'_> {
        let Ok(Some(stmt)) = self.live_stmt() else {
            return Cell::Null;
        };
        let index = index as c_int;
        unsafe {
            match ffi::sqlite3_column_type(stmt, index) {
                ffi::SQLITE_INTEGER => Cell::Integer(ffi::sqlite3_column_int64(stmt, index)),
                ffi::SQLITE_FLOAT => Cell::Real(ffi::sqlite3_column_double(stmt, index)),
                ffi::SQLITE_TEXT => {
                    // The pointer first: asking for the size may convert.
                    let text = ffi::sqlite3_column_text(stmt, index);
                    let len = ffi::sqlite3_column_bytes(stmt, index).max(0) as usize;
                    Cell::Text(if text.is_null() {
                        &[]
                    } else {
                        std::slice::from_raw_parts(text, len)
                    })
                }
                ffi::SQLITE_BLOB => {
                    let blob = ffi::sqlite3_column_blob(stmt, index).cast::<u8>();
                    let len = ffi::sqlite3_column_bytes(stmt, index).max(0) as usize;
                    Cell::Blob(if blob.is_null() {
                        &[]
                    } else {
                        std::slice::from_raw_parts(blob, len)
                    })
                }
                _ => Cell::Null,
            }
        }
    }

    /// Give the statement back to the connection's cache, unless the
    /// connection was closed and has finalized it already.
    fn finish(&mut self) {
        let stmt = std::mem::replace(&mut self.stmt, core::ptr::null_mut());
        if stmt.is_null() {
            return;
        }
        let mut state = self.connection.state.borrow_mut();
        if state.raw.is_null() {
            return;
        }
        state.active.retain(|active| *active != stmt);
        state.checkin(&self.sql, stmt);
    }
}

impl Drop for Cursor {
    fn drop(&mut self) {
        self.finish();
    }
}

// ---- The database path -----------------------------------------------------

type NativePath = UnixBytesOrUtf8OrWindowsU16s;
type NativePathTag = UnixBytesOrUtf8OrWindowsU16sTag;

/// `sqlite3_open_v2` takes UTF-8 on every OS; on Windows SQLite converts it to
/// the wide form itself. A path that is not valid UTF-16 has no UTF-8 form.
fn utf8_from_utf16(units: &[u16]) -> Result<Vec<u8>, &'static str> {
    String::from_utf16(units)
        .map(String::into_bytes)
        .map_err(|_| "database path is not valid Unicode")
}

/// The bytes to pass to SQLite for a path, per OS.
fn sqlite_path_bytes(path: &NativePath) -> Result<Vec<u8>, &'static str> {
    unsafe {
        match path.tag {
            NativePathTag::Utf8 => Ok(path.payload.utf8.as_str().as_bytes().to_vec()),
            NativePathTag::UnixBytes => {
                if cfg!(unix) {
                    Ok(path.payload.unix_bytes.as_slice().to_vec())
                } else {
                    Err("Unix database paths are not supported on this host")
                }
            }
            NativePathTag::WindowsU16s => {
                if cfg!(windows) {
                    utf8_from_utf16(path.payload.windows_u16s.as_slice())
                } else {
                    Err("Windows database paths are not supported on this host")
                }
            }
        }
    }
}

fn sqlite_path(path: &NativePath) -> Result<CString, Failure> {
    let bytes =
        sqlite_path_bytes(path).map_err(|message| Failure::new(ffi::SQLITE_CANTOPEN, message))?;
    CString::new(bytes)
        .map_err(|_| Failure::new(ffi::SQLITE_CANTOPEN, "database path contains a NUL byte"))
}

// ---- Roc values --------------------------------------------------------------

type RocValue = BytesOrIntegerOrNullOrRealOrString;
type RocValueTag = BytesOrIntegerOrNullOrRealOrStringTag;
type RocCell = BytesOrIntegerOrNullOrRealOrText;
type RocCellTag = BytesOrIntegerOrNullOrRealOrTextTag;
type RocCellPayload = BytesOrIntegerOrNullOrRealOrTextPayload;
type RocFailure = HostSqliteCloseErr;
type RocProblem = ClosedOrFailedOrInterruptedOrMultipleStatementsOrReturnsRowsOrWrongParamCount;
type RocProblemTag =
    ClosedOrFailedOrInterruptedOrMultipleStatementsOrReturnsRowsOrWrongParamCountTag;
type RocProblemPayload =
    ClosedOrFailedOrInterruptedOrMultipleStatementsOrReturnsRowsOrWrongParamCountPayload;

fn params_from_roc(values: &[RocValue]) -> Vec<Param<'_>> {
    values
        .iter()
        .map(|value| unsafe {
            match value.tag {
                RocValueTag::Null => Param::Null,
                RocValueTag::Integer => Param::Integer(*value.payload.integer),
                RocValueTag::Real => Param::Real(*value.payload.real),
                RocValueTag::String => Param::Text(value.payload.string.as_str()),
                RocValueTag::Bytes => Param::Blob(value.payload.bytes.as_slice()),
            }
        })
        .collect()
}

fn roc_cell(cell: Cell, roc_host: &RocHost) -> RocCell {
    match cell {
        Cell::Null => RocCell {
            payload: RocCellPayload { null: [] },
            tag: RocCellTag::Null,
        },
        Cell::Integer(value) => RocCell {
            payload: RocCellPayload {
                integer: ManuallyDrop::new(value),
            },
            tag: RocCellTag::Integer,
        },
        Cell::Real(value) => RocCell {
            payload: RocCellPayload {
                real: ManuallyDrop::new(value),
            },
            tag: RocCellTag::Real,
        },
        Cell::Text(bytes) => RocCell {
            payload: RocCellPayload {
                text: ManuallyDrop::new(roc_u8_list_from_slice(bytes, roc_host)),
            },
            tag: RocCellTag::Text,
        },
        Cell::Blob(bytes) => RocCell {
            payload: RocCellPayload {
                bytes: ManuallyDrop::new(roc_u8_list_from_slice(bytes, roc_host)),
            },
            tag: RocCellTag::Bytes,
        },
    }
}

fn roc_failure(failure: &Failure, roc_host: &RocHost) -> RocFailure {
    RocFailure {
        extended_code: failure.extended_code as i64,
        message: RocStr::from_str(&failure.message, roc_host),
    }
}

fn roc_problem(problem: &Problem, roc_host: &RocHost) -> RocProblem {
    match problem {
        Problem::Interrupted => RocProblem {
            payload: RocProblemPayload { interrupted: [] },
            tag: RocProblemTag::Interrupted,
        },
        Problem::Failed(failure) => RocProblem {
            payload: RocProblemPayload {
                failed: ManuallyDrop::new(roc_failure(failure, roc_host)),
            },
            tag: RocProblemTag::Failed,
        },
        Problem::Closed => RocProblem {
            payload: RocProblemPayload { closed: [] },
            tag: RocProblemTag::Closed,
        },
        Problem::WrongParamCount { expected, given } => RocProblem {
            payload: RocProblemPayload {
                wrong_param_count: ManuallyDrop::new(HostSqliteExecuteErrWrongParamCount {
                    expected: *expected,
                    given: *given,
                }),
            },
            tag: RocProblemTag::WrongParamCount,
        },
        Problem::ReturnsRows => RocProblem {
            payload: RocProblemPayload { returns_rows: [] },
            tag: RocProblemTag::ReturnsRows,
        },
        Problem::MultipleStatements => RocProblem {
            payload: RocProblemPayload {
                multiple_statements: [],
            },
            tag: RocProblemTag::MultipleStatements,
        },
    }
}

fn execute_result(result: Result<(), Problem>, roc_host: &RocHost) -> HostSqliteExecuteResult {
    match result {
        Ok(()) => HostSqliteExecuteResult {
            payload: HostSqliteExecuteResultPayload { ok: [] },
            tag: HostSqliteExecuteResultTag::Ok,
        },
        Err(problem) => HostSqliteExecuteResult {
            payload: HostSqliteExecuteResultPayload {
                err: ManuallyDrop::new(roc_problem(&problem, roc_host)),
            },
            tag: HostSqliteExecuteResultTag::Err,
        },
    }
}

fn open_err(failure: &Failure, roc_host: &RocHost) -> HostSqliteOpenResult {
    HostSqliteOpenResult {
        payload: HostSqliteOpenResultPayload {
            err: ManuallyDrop::new(if failure.extended_code & 0xff == ffi::SQLITE_INTERRUPT {
                HostSqliteOpenErr {
                    payload: HostSqliteOpenErrPayload { interrupted: [] },
                    tag: HostSqliteOpenErrTag::Interrupted,
                }
            } else {
                HostSqliteOpenErr {
                    payload: HostSqliteOpenErrPayload {
                        failed: ManuallyDrop::new(roc_failure(failure, roc_host)),
                    },
                    tag: HostSqliteOpenErrTag::Failed,
                }
            }),
        },
        tag: HostSqliteOpenResultTag::Err,
    }
}

fn query_err(problem: &Problem, roc_host: &RocHost) -> HostSqliteQueryResult {
    HostSqliteQueryResult {
        payload: HostSqliteQueryResultPayload {
            err: ManuallyDrop::new(roc_problem(problem, roc_host)),
        },
        tag: HostSqliteQueryResultTag::Err,
    }
}

fn next_err(
    tag: ClosedOrDoneOrFailedOrInterruptedTag,
    payload: ClosedOrDoneOrFailedOrInterruptedPayload,
) -> HostSqliteNextResult {
    HostSqliteNextResult {
        payload: HostSqliteNextResultPayload {
            err: ManuallyDrop::new(ClosedOrDoneOrFailedOrInterrupted { payload, tag }),
        },
        tag: HostSqliteNextResultTag::Err,
    }
}

/// The handle could not be allocated; SQLite has no word in this.
fn handle_failure(error: &std::io::Error) -> Failure {
    Failure::new(ffi::SQLITE_NOMEM, error.to_string())
}

// ---- Hosted functions ----------------------------------------------------------

#[no_mangle]
pub extern "C" fn hosted_sqlite_open(
    path: NativePath,
    mode: ReadOnlyOrReadWriteOrReadWriteCreate,
    busy_timeout_nanos: u64,
) -> HostSqliteOpenResult {
    let roc_host = roc_host();
    let native = sqlite_path(&path);
    unsafe { path.decref(roc_host) };
    let mode = match mode {
        ReadOnlyOrReadWriteOrReadWriteCreate::ReadWriteCreate => Mode::ReadWriteCreate,
        ReadOnlyOrReadWriteOrReadWriteCreate::ReadWrite => Mode::ReadWrite,
        ReadOnlyOrReadWriteOrReadWriteCreate::ReadOnly => Mode::ReadOnly,
    };
    let opened = native.and_then(|native| {
        Connection::open(&native, mode, Duration::from_nanos(busy_timeout_nanos))
    });
    let handle = opened.and_then(|connection| {
        crate::resources::box_resource(SqliteDb(connection), roc_host)
            .map_err(|error| handle_failure(&error))
    });
    match handle {
        Ok(handle) => HostSqliteOpenResult {
            payload: HostSqliteOpenResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostSqliteOpenResultTag::Ok,
        },
        Err(failure) => open_err(&failure, roc_host),
    }
}

/// # Safety
///
/// `handle` must be a live database handle from `hosted_sqlite_open`.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_close(handle: *mut u64) -> HostSqliteCloseResult {
    let roc_host = roc_host();
    let db: &mut SqliteDb = unsafe { crate::resources::resource_ref(handle) };
    let result = match db.0.close() {
        Ok(()) => HostSqliteCloseResult {
            payload: HostSqliteCloseResultPayload { ok: [] },
            tag: HostSqliteCloseResultTag::Ok,
        },
        Err(failure) => HostSqliteCloseResult {
            payload: HostSqliteCloseResultPayload {
                err: ManuallyDrop::new(roc_failure(&failure, roc_host)),
            },
            tag: HostSqliteCloseResultTag::Err,
        },
    };
    crate::resources::release(handle, roc_host);
    result
}

/// # Safety
///
/// `handle` must be a live database handle from `hosted_sqlite_open`.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_execute(
    handle: *mut u64,
    sql: RocStr,
    params: RocList<RocValue>,
) -> HostSqliteExecuteResult {
    let roc_host = roc_host();
    let db: &mut SqliteDb = unsafe { crate::resources::resource_ref(handle) };
    let result =
        db.0.execute(sql.as_str(), &params_from_roc(params.as_slice()));
    unsafe {
        sql.decref(roc_host);
        decref_list_of_bytes_or_integer_or_null_or_real_or_string(params, roc_host);
    }
    crate::resources::release(handle, roc_host);
    execute_result(result, roc_host)
}

/// # Safety
///
/// `handle` must be a live database handle from `hosted_sqlite_open`.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_execute_script(
    handle: *mut u64,
    sql: RocStr,
) -> HostSqliteExecuteResult {
    let roc_host = roc_host();
    let db: &mut SqliteDb = unsafe { crate::resources::resource_ref(handle) };
    let result = db.0.execute_script(sql.as_str());
    unsafe { sql.decref(roc_host) };
    crate::resources::release(handle, roc_host);
    execute_result(result, roc_host)
}

/// # Safety
/// `handle` must be a live database handle.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_rollback_cleanup(
    handle: *mut u64,
) -> HostSqliteRollbackCleanupResult {
    let roc_host = roc_host();
    let db: &mut SqliteDb = unsafe { crate::resources::resource_ref(handle) };
    let result = execute_result(db.0.rollback_cleanup(), roc_host);
    crate::resources::release(handle, roc_host);
    result
}

/// # Safety
///
/// `handle` must be a live database handle from `hosted_sqlite_open`.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_query(
    handle: *mut u64,
    sql: RocStr,
    params: RocList<RocValue>,
) -> HostSqliteQueryResult {
    let roc_host = roc_host();
    let db: &mut SqliteDb = unsafe { crate::resources::resource_ref(handle) };
    let cursor =
        db.0.query(sql.as_str(), &params_from_roc(params.as_slice()));
    unsafe {
        sql.decref(roc_host);
        decref_list_of_bytes_or_integer_or_null_or_real_or_string(params, roc_host);
    }
    // The cursor keeps the connection alive, so the database handle can go.
    crate::resources::release(handle, roc_host);
    let boxed = cursor.and_then(|cursor| {
        crate::resources::box_resource(SqliteRows(cursor), roc_host)
            .map_err(|error| Problem::Failed(handle_failure(&error)))
    });
    match boxed {
        Ok(rows) => HostSqliteQueryResult {
            payload: HostSqliteQueryResultPayload {
                ok: ManuallyDrop::new(rows),
            },
            tag: HostSqliteQueryResultTag::Ok,
        },
        Err(problem) => query_err(&problem, roc_host),
    }
}

/// # Safety
///
/// `handle` must be a live rows handle from `hosted_sqlite_query`.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_columns(handle: *mut u64) -> RocList<RocStr> {
    let roc_host = roc_host();
    let rows: &mut SqliteRows = unsafe { crate::resources::resource_ref(handle) };
    let names = rows.0.column_names();
    let list = unsafe { RocList::<RocStr>::allocate(names.len(), roc_host) };
    for (index, name) in names.iter().enumerate() {
        unsafe {
            list.elements
                .add(index)
                .write(RocStr::from_str(name, roc_host));
        }
    }
    crate::resources::release(handle, roc_host);
    list
}

/// # Safety
///
/// `handle` must be a live rows handle from `hosted_sqlite_query`.
#[no_mangle]
pub unsafe extern "C" fn hosted_sqlite_next(handle: *mut u64) -> HostSqliteNextResult {
    let roc_host = roc_host();
    let rows: &mut SqliteRows = unsafe { crate::resources::resource_ref(handle) };
    let result = match rows.0.step() {
        Ok(true) => {
            let count = rows.0.column_count();
            let cells = unsafe { RocList::<RocCell>::allocate(count, roc_host) };
            for index in 0..count {
                let cell = roc_cell(rows.0.cell(index), roc_host);
                unsafe { cells.elements.add(index).write(cell) };
            }
            HostSqliteNextResult {
                payload: HostSqliteNextResultPayload {
                    ok: ManuallyDrop::new(cells),
                },
                tag: HostSqliteNextResultTag::Ok,
            }
        }
        Ok(false) => next_err(
            ClosedOrDoneOrFailedOrInterruptedTag::Done,
            ClosedOrDoneOrFailedOrInterruptedPayload { done: [] },
        ),
        Err(StepError::Interrupted) => next_err(
            ClosedOrDoneOrFailedOrInterruptedTag::Interrupted,
            ClosedOrDoneOrFailedOrInterruptedPayload { interrupted: [] },
        ),
        Err(StepError::Closed) => next_err(
            ClosedOrDoneOrFailedOrInterruptedTag::Closed,
            ClosedOrDoneOrFailedOrInterruptedPayload { closed: [] },
        ),
        Err(StepError::Failed(failure)) => next_err(
            ClosedOrDoneOrFailedOrInterruptedTag::Failed,
            ClosedOrDoneOrFailedOrInterruptedPayload {
                failed: ManuallyDrop::new(roc_failure(&failure, roc_host)),
            },
        ),
    };
    crate::resources::release(handle, roc_host);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Instant;

    #[test]
    fn cancellation_rolls_back_without_acknowledging_the_signal() {
        let connection = memory();
        connection
            .execute("CREATE TABLE changes(value)", &[])
            .unwrap();
        connection.execute("BEGIN", &[]).unwrap();
        connection
            .execute("INSERT INTO changes VALUES(1)", &[])
            .unwrap();
        crate::signals::set_test_pending(true);
        assert_eq!(connection.execute("COMMIT", &[]), Err(Problem::Interrupted));
        connection.rollback_cleanup().unwrap();
        assert!(crate::signals::is_pending());
        crate::signals::set_test_pending(false);
        assert_eq!(count(&connection, "changes"), 0);
        connection
            .execute("INSERT INTO changes VALUES(2)", &[])
            .unwrap();
        assert_eq!(count(&connection, "changes"), 1);
    }

    #[test]
    fn progress_callback_interrupts_running_bytecode_and_cache_can_be_reused() {
        let connection = memory();
        let sql = "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<10000000) SELECT sum(x) FROM n";
        let stmt = connection
            .state
            .borrow_mut()
            .checkout(sql)
            .unwrap()
            .unwrap();
        crate::signals::set_test_pending(true);
        let code = unsafe { ffi::sqlite3_step(stmt) };
        assert_eq!(code, ffi::SQLITE_INTERRUPT);
        assert_eq!(
            connection.state.borrow().problem(code),
            Problem::Interrupted
        );
        connection.state.borrow_mut().checkin(sql, stmt);
        crate::signals::set_test_pending(false);
        assert_eq!(
            all_rows(&connection, "SELECT 7", &[]),
            vec![vec![Owned::Integer(7)]]
        );
    }

    #[test]
    fn progress_callback_also_interrupts_preparation() {
        let connection = memory();
        let state = connection.state.borrow();
        let context = (&*connection.callbacks as *const Callbacks)
            .cast_mut()
            .cast();
        unsafe { ffi::sqlite3_progress_handler(state.raw, 1, Some(progress), context) };
        let sql = std::iter::repeat_n("SELECT 1", 300)
            .collect::<Vec<_>>()
            .join(" UNION ALL ");
        let mut stmt = std::ptr::null_mut();
        crate::signals::set_test_pending(true);
        let code = unsafe {
            ffi::sqlite3_prepare_v2(
                state.raw,
                sql.as_ptr().cast(),
                sql.len() as c_int,
                &mut stmt,
                std::ptr::null_mut(),
            )
        };
        if !stmt.is_null() {
            unsafe { ffi::sqlite3_finalize(stmt) };
        }
        crate::signals::set_test_pending(false);
        assert_eq!(code, ffi::SQLITE_INTERRUPT);
        assert!(connection.callbacks.cancelled.get());
    }

    #[test]
    fn busy_timeout_setters_in_scripts_keep_the_managed_handler() {
        let connection = memory();
        connection
            .execute_script("PRAGMA busy_timeout=37; CREATE TABLE changes(value);")
            .unwrap();
        assert_eq!(
            connection.callbacks.timeout.get(),
            Duration::from_millis(37)
        );
        assert_eq!(
            all_rows(&connection, "PRAGMA busy_timeout", &[]),
            vec![vec![Owned::Integer(0)]]
        );
        all_rows(&connection, "PRAGMA busy_timeout=41", &[]);
        all_rows(&connection, "PRAGMA busy_timeout=43", &[]);
        all_rows(&connection, "PRAGMA busy_timeout=41", &[]);
        assert_eq!(
            connection.callbacks.timeout.get(),
            Duration::from_millis(41)
        );
        crate::signals::set_test_pending(true);
        let context = (&*connection.callbacks as *const Callbacks)
            .cast_mut()
            .cast();
        assert_eq!(unsafe { busy(context, 0) }, 0);
        assert!(connection.callbacks.cancelled.get());
        crate::signals::set_test_pending(false);
    }

    static NEXT_TEMP_DIR: AtomicUsize = AtomicUsize::new(0);

    /// A directory removed when the test ends, also when it fails.
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            loop {
                let sequence = NEXT_TEMP_DIR.fetch_add(1, Ordering::Relaxed);
                let path = std::env::temp_dir().join(format!(
                    "basic-cli-sqlite-{label}-{}-{sequence}",
                    std::process::id()
                ));
                match std::fs::create_dir(&path) {
                    Ok(()) => return Self(path),
                    Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                    Err(error) => panic!("failed to create test directory: {error}"),
                }
            }
        }

        fn file(&self, name: &str) -> CString {
            c_path(&self.0.join(name))
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn c_path(path: &Path) -> CString {
        CString::new(path.to_str().expect("temporary paths are UTF-8")).unwrap()
    }

    const WAIT: Duration = Duration::from_secs(5);

    fn open(path: &CStr, mode: Mode) -> Rc<Connection> {
        Connection::open(path, mode, WAIT).unwrap()
    }

    fn memory() -> Rc<Connection> {
        open(c":memory:", Mode::ReadWriteCreate)
    }

    #[derive(Debug, Clone, PartialEq)]
    enum Owned {
        Null,
        Integer(i64),
        Real(f64),
        Text(Vec<u8>),
        Blob(Vec<u8>),
    }

    fn next_row(cursor: &mut Cursor) -> Result<Option<Vec<Owned>>, StepError> {
        if !cursor.step()? {
            return Ok(None);
        }
        Ok(Some(
            (0..cursor.column_count())
                .map(|index| match cursor.cell(index) {
                    Cell::Null => Owned::Null,
                    Cell::Integer(value) => Owned::Integer(value),
                    Cell::Real(value) => Owned::Real(value),
                    Cell::Text(bytes) => Owned::Text(bytes.to_vec()),
                    Cell::Blob(bytes) => Owned::Blob(bytes.to_vec()),
                })
                .collect(),
        ))
    }

    fn all_rows(connection: &Rc<Connection>, sql: &str, params: &[Param]) -> Vec<Vec<Owned>> {
        let mut cursor = connection.query(sql, params).unwrap();
        let mut rows = Vec::new();
        while let Some(row) = next_row(&mut cursor).unwrap() {
            rows.push(row);
        }
        rows
    }

    fn count(connection: &Rc<Connection>, table: &str) -> i64 {
        match all_rows(connection, &format!("SELECT COUNT(*) FROM {table}"), &[])[0][0] {
            Owned::Integer(count) => count,
            ref other => panic!("COUNT(*) returned {other:?}"),
        }
    }

    fn failure_of(result: Result<(), Problem>) -> Failure {
        match result {
            Err(Problem::Failed(failure)) => failure,
            other => panic!("expected an SQLite failure, got {other:?}"),
        }
    }

    #[test]
    fn failure_never_carries_the_success_code() {
        // Release builds map a stray SQLITE_OK to a real error code.
        if !cfg!(debug_assertions) {
            assert_eq!(Failure::new(0, "x").extended_code, ffi::SQLITE_ERROR);
        }
        assert_eq!(Failure::new(5, "x").extended_code, 5);
    }

    #[test]
    fn open_modes() {
        let directory = TempDir::new("modes");
        let path = directory.file("database.sqlite");

        // Neither ReadWrite nor ReadOnly creates a missing file.
        for mode in [Mode::ReadWrite, Mode::ReadOnly] {
            let failure = Connection::open(&path, mode, WAIT).err().unwrap();
            assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_CANTOPEN);
            assert!(!failure.message.is_empty());
        }
        assert!(!directory.0.join("database.sqlite").exists());

        let writer = open(&path, Mode::ReadWriteCreate);
        writer.execute("CREATE TABLE t (x INTEGER)", &[]).unwrap();
        writer
            .execute("INSERT INTO t VALUES (?)", &[Param::Integer(1)])
            .unwrap();

        let existing = open(&path, Mode::ReadWrite);
        existing.execute("INSERT INTO t VALUES (2)", &[]).unwrap();

        let reader = open(&path, Mode::ReadOnly);
        assert_eq!(count(&reader, "t"), 2);
        let failure = failure_of(reader.execute("INSERT INTO t VALUES (3)", &[]));
        assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_READONLY);
        let failure = failure_of(reader.execute_script("DELETE FROM t"));
        assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_READONLY);
        assert_eq!(count(&writer, "t"), 2);
    }

    #[test]
    fn open_in_a_missing_directory_fails_and_leaves_nothing_open() {
        let directory = TempDir::new("failed-open");
        let path = directory.file("missing/database.sqlite");
        for _ in 0..64 {
            let failure = Connection::open(&path, Mode::ReadWriteCreate, WAIT)
                .err()
                .unwrap();
            assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_CANTOPEN);
        }
    }

    #[test]
    fn two_opens_are_two_connections() {
        let directory = TempDir::new("two-opens");
        let path = directory.file("database.sqlite");
        let first = open(&path, Mode::ReadWriteCreate);
        let second = open(&path, Mode::ReadWriteCreate);
        assert_ne!(first.state.borrow().raw, second.state.borrow().raw);

        first
            .execute_script("CREATE TABLE t (x INTEGER); BEGIN; INSERT INTO t VALUES (1);")
            .unwrap();
        // The other connection does not see the open transaction's row...
        assert_eq!(count(&second, "t"), 0);
        // ...and closing it does not end the transaction.
        second.close().unwrap();
        first.execute("COMMIT", &[]).unwrap();
        assert_eq!(count(&open(&path, Mode::ReadOnly), "t"), 1);
    }

    #[test]
    fn in_memory_databases_are_private() {
        let first = memory();
        let second = memory();
        first.execute("CREATE TABLE t (x INTEGER)", &[]).unwrap();
        let failure = failure_of(second.execute("INSERT INTO t VALUES (1)", &[]));
        assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_ERROR);
        assert!(failure.message.contains("no such table"));
        second.execute("CREATE TABLE t (x TEXT)", &[]).unwrap();
    }

    #[test]
    fn busy_timeout_waits_then_reports_busy() {
        let directory = TempDir::new("busy");
        let path = directory.file("database.sqlite");
        let holder = open(&path, Mode::ReadWriteCreate);
        holder.execute("CREATE TABLE t (x INTEGER)", &[]).unwrap();
        holder.execute("BEGIN IMMEDIATE", &[]).unwrap();

        let impatient = Connection::open(&path, Mode::ReadWrite, Duration::ZERO).unwrap();
        let started = Instant::now();
        let failure = failure_of(impatient.execute("INSERT INTO t VALUES (1)", &[]));
        assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_BUSY);
        assert!(started.elapsed() < Duration::from_millis(200));

        let patient = Connection::open(&path, Mode::ReadWrite, Duration::from_millis(300)).unwrap();
        let started = Instant::now();
        let failure = failure_of(patient.execute("INSERT INTO t VALUES (1)", &[]));
        assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_BUSY);
        assert!(started.elapsed() >= Duration::from_millis(250));

        // Once the lock is gone the same statement goes through.
        holder.execute("COMMIT", &[]).unwrap();
        patient.execute("INSERT INTO t VALUES (1)", &[]).unwrap();
        assert_eq!(count(&holder, "t"), 1);
    }

    #[test]
    fn statements_are_cached_by_text() {
        let connection = memory();
        connection
            .execute("CREATE TABLE t (x INTEGER)", &[])
            .unwrap();
        let prepared = connection.prepared();

        for value in 0..10 {
            connection
                .execute("INSERT INTO t VALUES (?)", &[Param::Integer(value)])
                .unwrap();
        }
        assert_eq!(connection.prepared(), prepared + 1);
        assert_eq!(count(&connection, "t"), 10);

        // A query goes back to the cache when it ends, and is found again.
        let prepared = connection.prepared();
        assert_eq!(count(&connection, "t"), 10);
        assert_eq!(connection.prepared(), prepared);

        // Bindings do not survive in the cached statement.
        assert_eq!(
            connection.execute("INSERT INTO t VALUES (?)", &[]),
            Err(Problem::WrongParamCount {
                expected: 1,
                given: 0
            })
        );
    }

    #[test]
    fn the_cache_evicts_the_least_recently_used_beyond_32() {
        let connection = memory();
        let sql = |index: usize| format!("SELECT {index}");
        for index in 0..MAX_CACHED_STATEMENTS {
            all_rows(&connection, &sql(index), &[]);
        }
        assert_eq!(connection.cached().len(), MAX_CACHED_STATEMENTS);
        assert_eq!(connection.prepared(), MAX_CACHED_STATEMENTS as u64);

        // Touch the oldest, so that the second oldest is the one to go.
        all_rows(&connection, &sql(0), &[]);
        assert_eq!(connection.prepared(), MAX_CACHED_STATEMENTS as u64);
        all_rows(&connection, &sql(MAX_CACHED_STATEMENTS), &[]);

        let cached = connection.cached();
        assert_eq!(cached.len(), MAX_CACHED_STATEMENTS);
        assert!(cached.contains(&sql(0)));
        assert!(!cached.contains(&sql(1)));
        assert!(cached.contains(&sql(MAX_CACHED_STATEMENTS)));

        // The evicted text is prepared again; a kept one is not.
        let prepared = connection.prepared();
        all_rows(&connection, &sql(2), &[]);
        assert_eq!(connection.prepared(), prepared);
        all_rows(&connection, &sql(1), &[]);
        assert_eq!(connection.prepared(), prepared + 1);
        assert_eq!(connection.cached().len(), MAX_CACHED_STATEMENTS);
    }

    #[test]
    fn two_cursors_over_the_same_text_are_independent() {
        let connection = memory();
        connection
            .execute_script("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1), (2);")
            .unwrap();
        let sql = "SELECT x FROM t ORDER BY x";
        let mut outer = connection.query(sql, &[]).unwrap();
        assert_eq!(next_row(&mut outer), Ok(Some(vec![Owned::Integer(1)])));
        let mut inner = connection.query(sql, &[]).unwrap();
        assert_eq!(next_row(&mut inner), Ok(Some(vec![Owned::Integer(1)])));
        assert_eq!(next_row(&mut outer), Ok(Some(vec![Owned::Integer(2)])));
        assert_eq!(next_row(&mut inner), Ok(Some(vec![Owned::Integer(2)])));
        assert_eq!(next_row(&mut inner), Ok(None));
        assert_eq!(next_row(&mut outer), Ok(None));
        // Stepping past the end stays at the end.
        assert_eq!(next_row(&mut outer), Ok(None));
        assert_eq!(connection.cached(), [sql]);
        assert!(connection.state.borrow().active.is_empty());
    }

    #[test]
    fn a_second_statement_is_detected() {
        let connection = memory();
        let two = "CREATE TABLE a (x INTEGER); CREATE TABLE b (x INTEGER);";
        assert_eq!(
            connection.execute(two, &[]),
            Err(Problem::MultipleStatements)
        );
        assert_eq!(
            connection.query(two, &[]).err(),
            Some(Problem::MultipleStatements)
        );
        // Nothing ran, not even the first statement.
        connection.execute("CREATE TABLE a (y TEXT)", &[]).unwrap();
        // Text after the statement that does not parse is not ignored either.
        assert_eq!(
            connection.execute("INSERT INTO a VALUES ('x'); nonsense", &[]),
            Err(Problem::MultipleStatements)
        );
        assert_eq!(
            connection.execute(";INSERT INTO a VALUES ('x'); SELECT 1", &[]),
            Err(Problem::MultipleStatements)
        );
        assert_eq!(count(&connection, "a"), 0);
        // A refused text is not cached.
        assert!(!connection.cached().iter().any(|sql| sql == two));

        // A trailing semicolon, white space and comments are not a statement.
        connection
            .execute(
                " /* first */ ; INSERT INTO a VALUES ('x') ; ; -- done\n /* really */ ",
                &[],
            )
            .unwrap();
        assert_eq!(count(&connection, "a"), 1);

        connection
            .execute_script(two.replace("a (", "c (").as_str())
            .unwrap();
        assert_eq!(count(&connection, "b"), 0);
        assert_eq!(count(&connection, "c"), 0);
    }

    #[test]
    fn text_without_a_statement_does_nothing() {
        let connection = memory();
        for sql in [
            "",
            "   \n\t",
            "-- only a comment",
            "/* block */",
            ";",
            " ; ; ",
        ] {
            assert_eq!(connection.execute(sql, &[]), Ok(()), "{sql:?}");
            assert_eq!(connection.execute_script(sql), Ok(()), "{sql:?}");
            assert_eq!(
                connection.execute(sql, &[Param::Null]),
                Err(Problem::WrongParamCount {
                    expected: 0,
                    given: 1
                }),
                "{sql:?}"
            );
            assert_eq!(
                connection.query(sql, &[Param::Null]).err(),
                Some(Problem::WrongParamCount {
                    expected: 0,
                    given: 1
                }),
                "{sql:?}"
            );
            let mut cursor = connection.query(sql, &[]).unwrap();
            assert!(cursor.stmt.is_null());
            assert!(cursor.column_names().is_empty(), "{sql:?}");
            assert_eq!(next_row(&mut cursor), Ok(None), "{sql:?}");
            assert_eq!(next_row(&mut cursor), Ok(None), "{sql:?}");
        }
        assert!(connection.cached().is_empty());
        assert_eq!(connection.prepared(), 0);
    }

    #[test]
    fn sql_with_a_nul_byte_is_refused() {
        let connection = memory();
        connection
            .execute("CREATE TABLE t (x INTEGER)", &[])
            .unwrap();
        let sql = "INSERT INTO t VALUES (1)\0; DROP TABLE t";
        for result in [
            connection.execute(sql, &[]),
            connection.execute_script(sql),
            connection.query(sql, &[]).map(|_| ()),
        ] {
            let failure = failure_of(result);
            assert_eq!(failure.extended_code, ffi::SQLITE_ERROR);
            assert_eq!(failure.message, "SQL text contains a NUL byte");
        }
        assert_eq!(count(&connection, "t"), 0);
    }

    #[test]
    fn a_statement_that_returns_rows_is_refused_before_it_runs() {
        let connection = memory();
        connection
            .execute("CREATE TABLE t (x INTEGER)", &[])
            .unwrap();
        assert_eq!(
            connection.execute("INSERT INTO t VALUES (1) RETURNING x", &[]),
            Err(Problem::ReturnsRows)
        );
        assert_eq!(count(&connection, "t"), 0);
        // Also when it would return no row.
        assert_eq!(
            connection.execute("SELECT x FROM t", &[]),
            Err(Problem::ReturnsRows)
        );
        assert_eq!(
            connection.execute("PRAGMA user_version", &[]),
            Err(Problem::ReturnsRows)
        );
        // As a query the same statement runs, once.
        assert_eq!(
            all_rows(&connection, "INSERT INTO t VALUES (1) RETURNING x", &[]),
            [[Owned::Integer(1)]]
        );
        assert_eq!(count(&connection, "t"), 1);
        // A script discards the rows.
        connection
            .execute_script("INSERT INTO t VALUES (2) RETURNING x; SELECT * FROM t;")
            .unwrap();
        assert_eq!(count(&connection, "t"), 2);
    }

    #[test]
    fn the_parameter_count_is_checked() {
        let connection = memory();
        connection.execute("CREATE TABLE t (a, b)", &[]).unwrap();
        let insert = "INSERT INTO t VALUES (?, ?)";
        let wrong = |given: u64| Err(Problem::WrongParamCount { expected: 2, given });
        assert_eq!(connection.execute(insert, &[]), wrong(0));
        assert_eq!(connection.execute(insert, &[Param::Integer(1)]), wrong(1));
        assert_eq!(connection.execute(insert, &[Param::Null; 3]), wrong(3));
        assert_eq!(
            connection.query(insert, &[Param::Null; 3]).err(),
            wrong(3).err()
        );
        assert_eq!(count(&connection, "t"), 0);
        // A refused statement goes back to the cache, not into the active set.
        assert!(connection.state.borrow().active.is_empty());
        assert!(connection.cached().iter().any(|cached| cached == insert));

        connection
            .execute(insert, &[Param::Integer(1), Param::Text("one")])
            .unwrap();
        // A numbered parameter used twice is one parameter.
        assert_eq!(
            all_rows(
                &connection,
                "SELECT a, b, ?1 FROM t WHERE a = ?1",
                &[Param::Integer(1)]
            ),
            [[
                Owned::Integer(1),
                Owned::Text(b"one".to_vec()),
                Owned::Integer(1)
            ]]
        );
    }

    #[test]
    fn values_round_trip() {
        let connection = memory();
        connection
            .execute("CREATE TABLE t (i, r, s, b, n)", &[])
            .unwrap();
        connection
            .execute(
                "INSERT INTO t VALUES (?, ?, ?, ?, ?)",
                &[
                    Param::Integer(i64::MIN),
                    Param::Real(1.5),
                    Param::Text("h\u{e9}llo"),
                    Param::Blob(&[0, 255, 0]),
                    Param::Null,
                ],
            )
            .unwrap();
        connection
            .execute(
                "INSERT INTO t VALUES (?, ?, ?, ?, ?)",
                &[
                    Param::Integer(0),
                    Param::Real(0.0),
                    Param::Text(""),
                    Param::Blob(&[]),
                    Param::Null,
                ],
            )
            .unwrap();
        let mut cursor = connection
            .query("SELECT i, r, s, b, n AS nil FROM t ORDER BY rowid", &[])
            .unwrap();
        assert_eq!(cursor.column_names(), ["i", "r", "s", "b", "nil"]);
        assert_eq!(
            next_row(&mut cursor),
            Ok(Some(vec![
                Owned::Integer(i64::MIN),
                Owned::Real(1.5),
                Owned::Text("h\u{e9}llo".as_bytes().to_vec()),
                Owned::Blob(vec![0, 255, 0]),
                Owned::Null,
            ]))
        );
        // An empty string and an empty blob are values, not NULL.
        assert_eq!(
            next_row(&mut cursor),
            Ok(Some(vec![
                Owned::Integer(0),
                Owned::Real(0.0),
                Owned::Text(Vec::new()),
                Owned::Blob(Vec::new()),
                Owned::Null,
            ]))
        );
        assert_eq!(next_row(&mut cursor), Ok(None));
    }

    #[test]
    fn text_that_is_not_utf8_is_returned_as_stored() {
        let connection = memory();
        // CAST keeps the bytes and only changes the type to TEXT.
        let rows = all_rows(
            &connection,
            "SELECT CAST(? AS TEXT), CAST(x'ff' AS TEXT)",
            &[Param::Blob(&[b'a', 0xc3, 0x28, b'z'])],
        );
        assert_eq!(
            rows,
            [[
                Owned::Text(vec![b'a', 0xc3, 0x28, b'z']),
                Owned::Text(vec![0xff])
            ]]
        );
    }

    #[test]
    fn constraint_violations_carry_their_extended_code() {
        let connection = memory();
        connection
            .execute_script(
                "PRAGMA foreign_keys = ON;
                 CREATE TABLE parent (id INTEGER PRIMARY KEY);
                 CREATE TABLE child (
                     id INTEGER PRIMARY KEY,
                     email TEXT UNIQUE,
                     name TEXT NOT NULL,
                     age INTEGER CHECK (age >= 0),
                     parent INTEGER REFERENCES parent (id)
                 );
                 CREATE TABLE pair (a, b, PRIMARY KEY (a, b)) WITHOUT ROWID;
                 INSERT INTO parent VALUES (1);
                 INSERT INTO child VALUES (1, 'a@example.org', 'a', 1, 1);
                 INSERT INTO pair VALUES (1, 1);",
            )
            .unwrap();
        let cases = [
            (
                "INSERT INTO child VALUES (2, 'a@example.org', 'b', 1, 1)",
                ffi::SQLITE_CONSTRAINT_UNIQUE,
            ),
            (
                "INSERT INTO child VALUES (1, 'b@example.org', 'b', 1, 1)",
                ffi::SQLITE_CONSTRAINT_PRIMARYKEY,
            ),
            (
                "INSERT INTO pair VALUES (1, 1)",
                ffi::SQLITE_CONSTRAINT_PRIMARYKEY,
            ),
            (
                "INSERT INTO child VALUES (2, 'b@example.org', 'b', 1, 99)",
                ffi::SQLITE_CONSTRAINT_FOREIGNKEY,
            ),
            (
                "INSERT INTO child VALUES (2, 'b@example.org', NULL, 1, 1)",
                ffi::SQLITE_CONSTRAINT_NOTNULL,
            ),
            (
                "INSERT INTO child VALUES (2, 'b@example.org', 'b', -1, 1)",
                ffi::SQLITE_CONSTRAINT_CHECK,
            ),
        ];
        for (sql, expected) in cases {
            let failure = failure_of(connection.execute(sql, &[]));
            assert_eq!(failure.extended_code, expected, "{sql}");
            assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_CONSTRAINT);
            assert!(failure.message.contains("constraint failed"), "{sql}");
            // The same through a script and through a query.
            assert_eq!(
                failure_of(connection.execute_script(sql)).extended_code,
                expected
            );
            let mut cursor = connection.query(sql, &[]).unwrap();
            match next_row(&mut cursor) {
                Err(StepError::Failed(failure)) => assert_eq!(failure.extended_code, expected),
                other => panic!("{sql}: {other:?}"),
            }
            // The failed statement went back to the cache and ends there.
            assert_eq!(next_row(&mut cursor), Ok(None));
        }
        assert_eq!(count(&connection, "child"), 1);
    }

    #[test]
    fn a_syntax_error_is_a_failure_with_sqlites_message() {
        let connection = memory();
        let failure = failure_of(connection.execute("SELEC 1", &[]));
        assert_eq!(failure.extended_code, ffi::SQLITE_ERROR);
        assert!(
            failure.message.contains("syntax error"),
            "{}",
            failure.message
        );
        assert!(connection.cached().is_empty());
    }

    #[test]
    fn close_semantics() {
        let directory = TempDir::new("close");
        let path = directory.file("database.sqlite");
        let connection = open(&path, Mode::ReadWriteCreate);
        connection
            .execute_script("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1), (2);")
            .unwrap();
        // An open transaction is rolled back by closing.
        connection.execute("BEGIN", &[]).unwrap();
        connection.execute("INSERT INTO t VALUES (3)", &[]).unwrap();
        let mut cursor = connection.query("SELECT x FROM t ORDER BY x", &[]).unwrap();
        assert_eq!(next_row(&mut cursor), Ok(Some(vec![Owned::Integer(1)])));

        assert_eq!(connection.close(), Ok(()));
        assert_eq!(connection.close(), Ok(()));
        assert!(connection.state.borrow().active.is_empty());

        assert_eq!(connection.execute("SELECT 1", &[]), Err(Problem::Closed));
        assert_eq!(connection.execute("", &[]), Err(Problem::Closed));
        assert_eq!(connection.execute_script("SELECT 1"), Err(Problem::Closed));
        assert_eq!(connection.execute_script(""), Err(Problem::Closed));
        assert_eq!(
            connection.query("SELECT 1", &[]).err(),
            Some(Problem::Closed)
        );
        // The running cursor reports it too, every time, and has no columns.
        assert_eq!(next_row(&mut cursor), Err(StepError::Closed));
        assert_eq!(next_row(&mut cursor), Err(StepError::Closed));
        assert!(cursor.column_names().is_empty());
        drop(cursor);

        assert_eq!(count(&open(&path, Mode::ReadOnly), "t"), 2);
    }

    #[test]
    fn handles_can_be_released_in_either_order() {
        let directory = TempDir::new("release-order");
        let path = directory.file("database.sqlite");
        let setup = open(&path, Mode::ReadWriteCreate);
        setup
            .execute_script("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1), (2);")
            .unwrap();
        let sql = "SELECT x FROM t ORDER BY x";

        // The database handle first: the cursor keeps the connection open.
        let db = SqliteDb(open(&path, Mode::ReadWrite));
        let mut rows = SqliteRows(db.0.query(sql, &[]).unwrap());
        assert_eq!(next_row(&mut rows.0), Ok(Some(vec![Owned::Integer(1)])));
        let connection = Rc::downgrade(&db.0);
        drop(db);
        assert_eq!(connection.strong_count(), 1);
        assert_eq!(next_row(&mut rows.0), Ok(Some(vec![Owned::Integer(2)])));
        drop(rows);
        assert_eq!(connection.strong_count(), 0);

        // The cursor first, unfinished: its statement goes back to the cache
        // and no longer holds a read transaction, so the table can be dropped.
        let db = SqliteDb(open(&path, Mode::ReadWrite));
        let mut rows = SqliteRows(db.0.query(sql, &[]).unwrap());
        assert_eq!(next_row(&mut rows.0), Ok(Some(vec![Owned::Integer(1)])));
        let failure = failure_of(db.0.execute("DROP TABLE t", &[]));
        assert_eq!(failure.extended_code & 0xff, ffi::SQLITE_LOCKED);
        drop(rows);
        assert!(db.0.state.borrow().active.is_empty());
        assert!(db.0.cached().iter().any(|cached| cached == sql));
        db.0.execute("DROP TABLE t", &[]).unwrap();
        let connection = Rc::downgrade(&db.0);
        drop(db);
        assert_eq!(connection.strong_count(), 0);

        // Closed while a cursor is alive, then released in both orders.
        for cursor_first in [true, false] {
            let db = SqliteDb(open(&path, Mode::ReadWrite));
            let mut rows = SqliteRows(db.0.query("SELECT 1 UNION SELECT 2", &[]).unwrap());
            assert_eq!(next_row(&mut rows.0), Ok(Some(vec![Owned::Integer(1)])));
            db.0.close().unwrap();
            assert_eq!(next_row(&mut rows.0), Err(StepError::Closed));
            let connection = Rc::downgrade(&db.0);
            if cursor_first {
                drop(rows);
                drop(db);
            } else {
                drop(db);
                drop(rows);
            }
            assert_eq!(connection.strong_count(), 0);
        }
    }

    #[test]
    fn utf16_paths_become_utf8() {
        let wide: Vec<u16> = "C:\\d\u{e9}p\u{f4}t\\\u{1f600}.db".encode_utf16().collect();
        assert_eq!(
            utf8_from_utf16(&wide).unwrap(),
            "C:\\d\u{e9}p\u{f4}t\\\u{1f600}.db".as_bytes()
        );
        // An unpaired surrogate has no UTF-8 form.
        assert!(utf8_from_utf16(&[0x0041, 0xd800, 0x0042]).is_err());
    }
}
