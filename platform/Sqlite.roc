module [
    Value,
    Code,
    Error,
    Binding,
    Stmt,
    query!,
    query_many!,
    execute!,
    prepare!,
    query_prepared!,
    query_many_prepared!,
    execute_prepared!,
    err_to_str,
    decode_record,
    map_value,
    tagged_value,
    str,
    bytes,
    i64,
    i32,
    i16,
    i8,
    u64,
    u32,
    u16,
    u8,
    f64,
    f32,
    Nullable,
    nullable_str,
    nullable_bytes,
    nullable_i64,
    nullable_i32,
    nullable_i16,
    nullable_i8,
    nullable_u64,
    nullable_u32,
    nullable_u16,
    nullable_u8,
    nullable_f64,
    nullable_f32,
]

import Host
import InternalSqlite

## Represents a value that can be stored in a Sqlite database.
##
## ```
## [
##     Null,
##     Real F64,
##     Integer I64,
##     String Str,
##     Bytes (List U8),
## ]
## ```
Value : InternalSqlite.SqliteValue

## Represents various error codes that can be returned by Sqlite.
## ```
## [
##     ERROR, # SQL error or missing database
##     INTERNAL, # Internal logic error in Sqlite
##     PERM, # Access permission denied
##     ABORT, # Callback routine requested an abort
##     BUSY, # The database file is locked
##     LOCKED, # A table in the database is locked
##     NOMEM, # A malloc() failed
##     READONLY, # Attempt to write a readonly database
##     INTERRUPT, # Operation terminated by sqlite3_interrupt(
##     IOERR, # Some kind of disk I/O error occurred
##     CORRUPT, # The database disk image is malformed
##     NOTFOUND, # Unknown opcode in sqlite3_file_control()
##     FULL, # Insertion failed because database is full
##     CANTOPEN, # Unable to open the database file
##     PROTOCOL, # Database lock protocol error
##     EMPTY, # Database is empty
##     SCHEMA, # The database schema changed
##     TOOBIG, # String or BLOB exceeds size limit
##     CONSTRAINT, # Abort due to constraint violation
##     MISMATCH, # Data type mismatch
##     MISUSE, # Library used incorrectly
##     NOLFS, # Uses OS features not supported on host
##     AUTH, # Authorization denied
##     FORMAT, # Auxiliary database format error
##     RANGE, # 2nd parameter to sqlite3_bind out of range
##     NOTADB, # File opened that is not a database file
##     NOTICE, # Notifications from sqlite3_log()
##     WARNING, # Warnings from sqlite3_log()
##     ROW, # sqlite3_step() has another row ready
##     DONE, # sqlite3_step() has finished executing
## ]
## ```
Code : InternalSqlite.SqliteErrCode

## An error occured interacting with a Sqlite database.
## This includes the [Code] and a [Str] message.
## ```
## [SqlError Code Str]
## ```
Error : [SqlError Code Str]

## Bind a name and a value to pass to the Sqlite database.
## ```
## {
##     name : Str,
##     value : SqliteValue,
## }
## ```
Binding : InternalSqlite.SqliteBindings

## Represents a prepared statement that can be executed many times.
Stmt := Box {}

## Prepare a [Stmt] for execution at a later time.
##
## This is useful when you have a query that will be called many times, as it is more efficient than
## preparing the query each time it is called. This is usually done in `init!` with the prepared `Stmt` stored in the model.
##
## ```
## prepared_query = try Sqlite.prepare! {
##     path : "path/to/database.db",
##     query : "SELECT * FROM todos;",
## }
##
## Sqlite.query_many_prepared! {
##     stmt: prepared_query,
##     bindings: [],
##     rows: { Sqlite.decode_record <-
##         id: Sqlite.i64 "id" |> Sqlite.map_value Num.toStr,
##         task: Sqlite.str "task",
##     },
## }
## ```
prepare! :
    {
        path : Str,
        query : Str,
    }
    => Result Stmt Error
prepare! = \{ path, query: q } ->
    Host.sqlite_prepare! path q
    |> Result.map @Stmt
    |> Result.mapErr internal_to_external_error

# internal use only
bind! : Stmt, List Binding => Result {} Error
bind! = \@Stmt stmt, bindings ->
    Host.sqlite_bind! stmt bindings
    |> Result.mapErr internal_to_external_error

# internal use only
columns! : Stmt => List Str
columns! = \@Stmt stmt ->
    Host.sqlite_columns! stmt

# internal use only
column_value! : Stmt, U64 => Result Value Error
column_value! = \@Stmt stmt, i ->
    Host.sqlite_column_value! stmt i
    |> Result.mapErr internal_to_external_error

# internal use only
step! : Stmt => Result [Row, Done] Error
step! = \@Stmt stmt ->
    Host.sqlite_step! stmt
    |> Result.mapErr internal_to_external_error

# internal use only
reset! : Stmt => Result {} Error
reset! = \@Stmt stmt ->
    Host.sqlite_reset! stmt
    |> Result.mapErr internal_to_external_error

## Execute a SQL statement that doesn't return any rows (like INSERT, UPDATE, DELETE).
##
## Example:
## ```
## Sqlite.execute! {
##     path: "path/to/database.db",
##     query: "INSERT INTO names (first, last) VALUES (:first, :last);",
##     bindings: [
##         { name: ":first", value: String "John" },
##         { name: ":last", value: String "Smith" },
##     ],
## }
## ```
execute! :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
    }
    => Result {} [SqlError Code Str, UnhandledRows]
execute! = \{ path, query: q, bindings } ->
    stmt = try prepare! { path, query: q }
    execute_prepared! { stmt, bindings }

## TODO documentation
execute_prepared! :
    {
        stmt : Stmt,
        bindings : List Binding,
    }
    => Result {} [SqlError Code Str, UnhandledRows]
execute_prepared! = \{ stmt, bindings } ->
    try bind! stmt bindings
    res = step! stmt
    try reset! stmt
    when res is
        Ok Done ->
            Ok {}

        Ok Row ->
            Err UnhandledRows

        Err e ->
            Err e

## TODO documentation
query! :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
        row : SqlDecode a (RowCountErr err),
    }
    => Result a (SqlDecodeErr (RowCountErr err))
query! = \{ path, query: q, bindings, row } ->
    stmt = try prepare! { path, query: q }
    query_prepared! { stmt, bindings, row }

## TODO documentation
query_prepared! :
    {
        stmt : Stmt,
        bindings : List Binding,
        row : SqlDecode a (RowCountErr err),
    }
    => Result a (SqlDecodeErr (RowCountErr err))
query_prepared! = \{ stmt, bindings, row: decode } ->
    try bind! stmt bindings
    res = decode_exactly_one_row! stmt decode
    try reset! stmt
    res

## TODO documentation
query_many! :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
        rows : SqlDecode a err,
    }
    => Result (List a) (SqlDecodeErr err)
query_many! = \{ path, query: q, bindings, rows } ->
    stmt = try prepare! { path, query: q }
    query_many_prepared! { stmt, bindings, rows }

## TODO documentation
query_many_prepared! :
    {
        stmt : Stmt,
        bindings : List Binding,
        rows : SqlDecode a err,
    }
    => Result (List a) (SqlDecodeErr err)
query_many_prepared! = \{ stmt, bindings, rows: decode } ->
    try bind! stmt bindings
    res = decode_rows! stmt decode
    try reset! stmt
    res

SqlDecodeErr err : [FieldNotFound Str, SqlError Code Str]err
SqlDecode a err := List Str -> (Stmt => Result a (SqlDecodeErr err))

## TODO documentation
decode_record : SqlDecode a err, SqlDecode b err, (a, b -> c) -> SqlDecode c err
decode_record = \@SqlDecode gen_first, @SqlDecode gen_second, mapper ->
    @SqlDecode \cols ->
        decode_first! = gen_first cols
        decode_second! = gen_second cols

        \stmt ->
            first = try decode_first! stmt
            second = try decode_second! stmt
            Ok (mapper first second)

## TODO documentation
map_value : SqlDecode a err, (a -> b) -> SqlDecode b err
map_value = \@SqlDecode gen_decode, mapper ->
    @SqlDecode \cols ->
        decode! = gen_decode cols

        \stmt ->
            val = try decode! stmt
            Ok (mapper val)

RowCountErr err : [NoRowsReturned, TooManyRowsReturned]err

# internal use only
decode_exactly_one_row! : Stmt, SqlDecode a (RowCountErr err) => Result a (SqlDecodeErr (RowCountErr err))
decode_exactly_one_row! = \stmt, @SqlDecode gen_decode ->
    cols = columns! stmt
    decode_row! = gen_decode cols

    when try step! stmt is
        Row ->
            row = try decode_row! stmt
            when try step! stmt is
                Done ->
                    Ok row

                Row ->
                    Err TooManyRowsReturned

        Done ->
            Err NoRowsReturned

# internal use only
decode_rows! : Stmt, SqlDecode a err => Result (List a) (SqlDecodeErr err)
decode_rows! = \stmt, @SqlDecode gen_decode ->
    cols = columns! stmt
    decode_row! = gen_decode cols

    helper! = \out ->
        when try step! stmt is
            Done ->
                Ok out

            Row ->
                row = try decode_row! stmt

                List.append out row
                |> helper!

    helper! []

# internal use only
decoder : (Value -> Result a (SqlDecodeErr err)) -> (Str -> SqlDecode a err)
decoder = \fn -> \name ->
    @SqlDecode \cols ->

        found = List.findFirstIndex cols \x -> x == name
        when found is
            Ok index ->
                \stmt ->
                    try column_value! stmt index
                    |> fn

            Err NotFound ->
                \_ ->
                    Err (FieldNotFound name)

## TODO documentation
tagged_value : Str -> SqlDecode Value []
tagged_value = decoder \val ->
    Ok val

to_unexpected_type_err = \val ->
    type =
        when val is
            Integer _ -> Integer
            Real _ -> Real
            String _ -> String
            Bytes _ -> Bytes
            Null -> Null
    Err (UnexpectedType type)

UnexpectedTypeErr : [UnexpectedType [Integer, Real, String, Bytes, Null]]

## Decode a [Value] to a [Str].
##
## For example here we build a decoder that decodes the rows into a list of records with `id` and `name` fields:
## ```
## Sqlite.query_many! {
##     path: "path/to/database.db",
##     query: "SELECT id, name FROM users;",
##     bindings: [],
##     rows: { Sqlite.decode_record <-
##         id: Sqlite.i64 "id" |> Sqlite.map_value Num.toStr,
##         task: Sqlite.str "name",
##     },
## }
## ```
str : Str -> SqlDecode Str UnexpectedTypeErr
str = decoder \val ->
    when val is
        String s -> Ok s
        _ -> to_unexpected_type_err val

## Decode a [Value] to a [List U8].
bytes : Str -> SqlDecode (List U8) UnexpectedTypeErr
bytes = decoder \val ->
    when val is
        Bytes b -> Ok b
        _ -> to_unexpected_type_err val

# internal use only
int_decoder : (I64 -> Result a err) -> (Str -> SqlDecode a [FailedToDecodeInteger err]UnexpectedTypeErr)
int_decoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.mapErr FailedToDecodeInteger
            _ -> to_unexpected_type_err val

# internal use only
real_decoder : (F64 -> Result a err) -> (Str -> SqlDecode a [FailedToDecodeReal err]UnexpectedTypeErr)
real_decoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.mapErr FailedToDecodeReal
            _ -> to_unexpected_type_err val

## Decode a [Value] to a [I64].
##
## For example here we build a decoder that decodes the rows into a list of records with `id` and `name` fields:
## ```
## Sqlite.query_many! {
##     path: "path/to/database.db",
##     query: "SELECT id, name FROM users;",
##     bindings: [],
##     rows: { Sqlite.decode_record <-
##         id: Sqlite.i64 "id" |> Sqlite.map_value Num.toStr,
##         task: Sqlite.str "name",
##     },
## }
## ```
i64 : Str -> SqlDecode I64 [FailedToDecodeInteger []]UnexpectedTypeErr
i64 = int_decoder Ok

## Decode a [Value] to a [I32].
i32 : Str -> SqlDecode I32 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
i32 = int_decoder Num.toI32Checked

## Decode a [Value] to a [I16].
i16 : Str -> SqlDecode I16 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
i16 = int_decoder Num.toI16Checked

## Decode a [Value] to a [I8].
i8 : Str -> SqlDecode I8 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
i8 = int_decoder Num.toI8Checked

## Decode a [Value] to a [U64].
u64 : Str -> SqlDecode U64 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u64 = int_decoder Num.toU64Checked

## Decode a [Value] to a [U32].
u32 : Str -> SqlDecode U32 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u32 = int_decoder Num.toU32Checked

## Decode a [Value] to a [U16].
u16 : Str -> SqlDecode U16 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u16 = int_decoder Num.toU16Checked

## Decode a [Value] to a [U8].
u8 : Str -> SqlDecode U8 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u8 = int_decoder Num.toU8Checked

## Decode a [Value] to a [F64].
f64 : Str -> SqlDecode F64 [FailedToDecodeReal []]UnexpectedTypeErr
f64 = real_decoder Ok

## Decode a [Value] to a [F32].
f32 : Str -> SqlDecode F32 [FailedToDecodeReal []]UnexpectedTypeErr
f32 = real_decoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# dec = realSqlDecoder Ok

# These are the same decoders as above but Nullable.
# If the sqlite field is `Null`, they will return `Null`.

## Represents a nullable value that can be stored in a Sqlite database.
Nullable a : [NotNull a, Null]

## Decode a [Value] to a [Nullable Str].
nullable_str : Str -> SqlDecode (Nullable Str) UnexpectedTypeErr
nullable_str = decoder \val ->
    when val is
        String s -> Ok (NotNull s)
        Null -> Ok Null
        _ -> to_unexpected_type_err val

## Decode a [Value] to a [Nullable (List U8)].
nullable_bytes : Str -> SqlDecode (Nullable (List U8)) UnexpectedTypeErr
nullable_bytes = decoder \val ->
    when val is
        Bytes b -> Ok (NotNull b)
        Null -> Ok Null
        _ -> to_unexpected_type_err val

# internal use only
nullable_int_decoder : (I64 -> Result a err) -> (Str -> SqlDecode (Nullable a) [FailedToDecodeInteger err]UnexpectedTypeErr)
nullable_int_decoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.map NotNull |> Result.mapErr FailedToDecodeInteger
            Null -> Ok Null
            _ -> to_unexpected_type_err val

# internal use only
nullable_real_decoder : (F64 -> Result a err) -> (Str -> SqlDecode (Nullable a) [FailedToDecodeReal err]UnexpectedTypeErr)
nullable_real_decoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.map NotNull |> Result.mapErr FailedToDecodeReal
            Null -> Ok Null
            _ -> to_unexpected_type_err val

## Decode a [Value] to a [Nullable I64].
nullable_i64 : Str -> SqlDecode (Nullable I64) [FailedToDecodeInteger []]UnexpectedTypeErr
nullable_i64 = nullable_int_decoder Ok

## Decode a [Value] to a [Nullable I32].
nullable_i32 : Str -> SqlDecode (Nullable I32) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_i32 = nullable_int_decoder Num.toI32Checked

## Decode a [Value] to a [Nullable I16].
nullable_i16 : Str -> SqlDecode (Nullable I16) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_i16 = nullable_int_decoder Num.toI16Checked

## Decode a [Value] to a [Nullable I8].
nullable_i8 : Str -> SqlDecode (Nullable I8) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_i8 = nullable_int_decoder Num.toI8Checked

## Decode a [Value] to a [Nullable U64].
nullable_u64 : Str -> SqlDecode (Nullable U64) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u64 = nullable_int_decoder Num.toU64Checked

## Decode a [Value] to a [Nullable U32].
nullable_u32 : Str -> SqlDecode (Nullable U32) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u32 = nullable_int_decoder Num.toU32Checked

## Decode a [Value] to a [Nullable U16].
nullable_u16 : Str -> SqlDecode (Nullable U16) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u16 = nullable_int_decoder Num.toU16Checked

## Decode a [Value] to a [Nullable U8].
nullable_u8 : Str -> SqlDecode (Nullable U8) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u8 = nullable_int_decoder Num.toU8Checked

## Decode a [Value] to a [Nullable F64].
nullable_f64 : Str -> SqlDecode (Nullable F64) [FailedToDecodeReal []]UnexpectedTypeErr
nullable_f64 = nullable_real_decoder Ok

## Decode a [Value] to a [Nullable F32].
nullable_f32 : Str -> SqlDecode (Nullable F32) [FailedToDecodeReal []]UnexpectedTypeErr
nullable_f32 = nullable_real_decoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# nullable_dec = nullable_real_decoder Ok

# internal use only
internal_to_external_error : InternalSqlite.SqliteError -> Error
internal_to_external_error = \{ code, message } ->
    SqlError (code_from_i64 code) message

# internal use only
code_from_i64 : I64 -> InternalSqlite.SqliteErrCode
code_from_i64 = \code ->
    if code == 1 || code == 0 then
        ERROR
    else if code == 2 then
        INTERNAL
    else if code == 3 then
        PERM
    else if code == 4 then
        ABORT
    else if code == 5 then
        BUSY
    else if code == 6 then
        LOCKED
    else if code == 7 then
        NOMEM
    else if code == 8 then
        READONLY
    else if code == 9 then
        INTERRUPT
    else if code == 10 then
        IOERR
    else if code == 11 then
        CORRUPT
    else if code == 12 then
        NOTFOUND
    else if code == 13 then
        FULL
    else if code == 14 then
        CANTOPEN
    else if code == 15 then
        PROTOCOL
    else if code == 16 then
        EMPTY
    else if code == 17 then
        SCHEMA
    else if code == 18 then
        TOOBIG
    else if code == 19 then
        CONSTRAINT
    else if code == 20 then
        MISMATCH
    else if code == 21 then
        MISUSE
    else if code == 22 then
        NOLFS
    else if code == 23 then
        AUTH
    else if code == 24 then
        FORMAT
    else if code == 25 then
        RANGE
    else if code == 26 then
        NOTADB
    else if code == 27 then
        NOTICE
    else if code == 28 then
        WARNING
    else if code == 100 then
        ROW
    else if code == 101 then
        DONE
    else
        crash "unsupported Sqlite error code $(Num.toStr code)"

## Convert a [Error] to a pretty string for display purposes.
err_to_str : Error -> Str
err_to_str = \err ->
    (SqlError code msg2) = err

    msg1 =
        when code is
            ERROR -> "ERROR: Sql error or missing database"
            INTERNAL -> "INTERNAL: Internal logic error in Sqlite"
            PERM -> "PERM: Access permission denied"
            ABORT -> "ABORT: Callback routine requested an abort"
            BUSY -> "BUSY: The database file is locked"
            LOCKED -> "LOCKED: A table in the database is locked"
            NOMEM -> "NOMEM: A malloc() failed"
            READONLY -> "READONLY: Attempt to write a readonly database"
            INTERRUPT -> "INTERRUPT: Operation terminated by sqlite3_interrupt("
            IOERR -> "IOERR: Some kind of disk I/O error occurred"
            CORRUPT -> "CORRUPT: The database disk image is malformed"
            NOTFOUND -> "NOTFOUND: Unknown opcode in sqlite3_file_control()"
            FULL -> "FULL: Insertion failed because database is full"
            CANTOPEN -> "CANTOPEN: Unable to open the database file"
            PROTOCOL -> "PROTOCOL: Database lock protocol error"
            EMPTY -> "EMPTY: Database is empty"
            SCHEMA -> "SCHEMA: The database schema changed"
            TOOBIG -> "TOOBIG: String or BLOB exceeds size limit"
            CONSTRAINT -> "CONSTRAINT: Abort due to constraint violation"
            MISMATCH -> "MISMATCH: Data type mismatch"
            MISUSE -> "MISUSE: Library used incorrectly"
            NOLFS -> "NOLFS: Uses OS features not supported on host"
            AUTH -> "AUTH: Authorization denied"
            FORMAT -> "FORMAT: Auxiliary database format error"
            RANGE -> "RANGE: 2nd parameter to sqlite3_bind out of range"
            NOTADB -> "NOTADB: File opened that is not a database file"
            NOTICE -> "NOTICE: Notifications from sqlite3_log()"
            WARNING -> "WARNING: Warnings from sqlite3_log()"
            ROW -> "ROW: sqlite3_step() has another row ready"
            DONE -> "DONE: sqlite3_step() has finished executing"

    "$(msg1) - $(msg2)"
