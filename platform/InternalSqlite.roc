module [
    SqliteErrCode,
    SqliteError,
    SqliteValue,
    SqliteState,
    SqliteBindings,
]

SqliteErrCode : [
    ERROR, # SQL error or missing database
    INTERNAL, # Internal logic error in Sqlite
    PERM, # Access permission denied
    ABORT, # Callback routine requested an abort
    BUSY, # The database file is locked
    LOCKED, # A table in the database is locked
    NOMEM, # A malloc() failed
    READONLY, # Attempt to write a readonly database
    INTERRUPT, # Operation terminated by sqlite3_interrupt(
    IOERR, # Some kind of disk I/O error occurred
    CORRUPT, # The database disk image is malformed
    NOTFOUND, # Unknown opcode in sqlite3_file_control()
    FULL, # Insertion failed because database is full
    CANTOPEN, # Unable to open the database file
    PROTOCOL, # Database lock protocol error
    EMPTY, # Database is empty
    SCHEMA, # The database schema changed
    TOOBIG, # String or BLOB exceeds size limit
    CONSTRAINT, # Abort due to constraint violation
    MISMATCH, # Data type mismatch
    MISUSE, # Library used incorrectly
    NOLFS, # Uses OS features not supported on host
    AUTH, # Authorization denied
    FORMAT, # Auxiliary database format error
    RANGE, # 2nd parameter to sqlite3_bind out of range
    NOTADB, # File opened that is not a database file
    NOTICE, # Notifications from sqlite3_log()
    WARNING, # Warnings from sqlite3_log()
    ROW, # sqlite3_step() has another row ready
    DONE, # sqlite3_step() has finished executing
]

SqliteError : {
    code : I64,
    message : Str,
}

SqliteValue : [
    Null,
    Real F64,
    Integer I64,
    String Str,
    Bytes (List U8),
]

SqliteState : [
    Row,
    Done,
]

SqliteBindings : {
    name : Str,
    value : SqliteValue,
}
