module [
    Value,
    ErrCode,
    Binding,
    query!,
    query_many!,
    execute!,
    prepare_query!,
    prepare_query_many!,
    prepare_execute!,
    prepare_transaction!,
    ExecuteFn,
    QueryFn,
    QueryManyFn,
    TransactionFn,
    errcode_to_str,
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
##     Error, # SQL error or missing database
##     Internal, # Internal logic error in Sqlite
##     Perm, # Access permission denied
##     Abort, # Callback routine requested an abort
##     Busy, # The database file is locked
##     Locked, # A table in the database is locked
##     NoMem, # A malloc() failed
##     ReadOnly, # Attempt to write a readonly database
##     Interrupt, # Operation terminated by sqlite3_interrupt(
##     IOErr, # Some kind of disk I/O error occurred
##     Corrupt, # The database disk image is malformed
##     NotFound, # Unknown opcode in sqlite3_file_control()
##     Full, # Insertion failed because database is full
##     CanNotOpen, # Unable to open the database file
##     Protocol, # Database lock protocol error
##     Empty, # Database is empty
##     Schema, # The database schema changed
##     TooBig, # String or BLOB exceeds size limit
##     Constraint, # Abort due to constraint violation
##     Mismatch, # Data type mismatch
##     Misuse, # Library used incorrectly
##     NoLfs, # Uses OS features not supported on host
##     AuthDenied, # Authorization denied
##     Format, # Auxiliary database format error
##     OutOfRange, # 2nd parameter to sqlite3_bind out of range
##     NotADatabase, # File opened that is not a database file
##     Notice, # Notifications from sqlite3_log()
##     Warning, # Warnings from sqlite3_log()
##     Row, # sqlite3_step() has another row ready
##     Done, # sqlite3_step() has finished executing
##     Unknown I64, # error code not known
## ]
## ```
ErrCode : [
    Error, # SQL error or missing database
    Internal, # Internal logic error in Sqlite
    Perm, # Access permission denied
    Abort, # Callback routine requested an abort
    Busy, # The database file is locked
    Locked, # A table in the database is locked
    NoMem, # A malloc() failed
    ReadOnly, # Attempt to write a readonly database
    Interrupt, # Operation terminated by sqlite3_interrupt(
    IOErr, # Some kind of disk I/O error occurred
    Corrupt, # The database disk image is malformed
    NotFound, # Unknown opcode in sqlite3_file_control()
    Full, # Insertion failed because database is full
    CanNotOpen, # Unable to open the database file
    Protocol, # Database lock protocol error
    Empty, # Database is empty
    Schema, # The database schema changed
    TooBig, # String or BLOB exceeds size limit
    Constraint, # Abort due to constraint violation
    Mismatch, # Data type mismatch
    Misuse, # Library used incorrectly
    NoLFS, # Uses OS features not supported on host
    AuthDenied, # Authorization denied
    Format, # Auxiliary database format error
    OutOfRange, # 2nd parameter to sqlite3_bind out of range
    NotADatabase, # File opened that is not a database file
    Notice, # Notifications from sqlite3_log()
    Warning, # Warnings from sqlite3_log()
    Row, # sqlite3_step() has another row ready
    Done, # sqlite3_step() has finished executing
    Unknown I64, # error code not known
]

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
##         id: Sqlite.i64 "id",
##         task: Sqlite.str "task",
##     },
## }
## ```
prepare! :
    {
        path : Str,
        query : Str,
    }
    => Result Stmt [SqliteErr ErrCode Str]
prepare! = \{ path, query: q } ->
    Host.sqlite_prepare! path q
    |> Result.map @Stmt
    |> Result.mapErr internal_to_external_error

# internal use only
bind! : Stmt, List Binding => Result {} [SqliteErr ErrCode Str]
bind! = \@Stmt stmt, bindings ->
    Host.sqlite_bind! stmt bindings
    |> Result.mapErr internal_to_external_error

# internal use only
columns! : Stmt => List Str
columns! = \@Stmt stmt ->
    Host.sqlite_columns! stmt

# internal use only
column_value! : Stmt, U64 => Result Value [SqliteErr ErrCode Str]
column_value! = \@Stmt stmt, i ->
    Host.sqlite_column_value! stmt i
    |> Result.mapErr internal_to_external_error

# internal use only
step! : Stmt => Result [Row, Done] [SqliteErr ErrCode Str]
step! = \@Stmt stmt ->
    Host.sqlite_step! stmt
    |> Result.mapErr internal_to_external_error

# internal use only
reset! : Stmt => Result {} [SqliteErr ErrCode Str]
reset! = \@Stmt stmt ->
    Host.sqlite_reset! stmt
    |> Result.mapErr internal_to_external_error

## Execute a SQL statement that doesn't return any rows (like INSERT, UPDATE, DELETE).
##
## Example:
## ```
## Sqlite.execute! {
##     path: "path/to/database.db",
##     query: "INSERT INTO users (first, last) VALUES (:first, :last);",
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
    => Result {} [SqliteErr ErrCode Str, UnhandledRows]
execute! = \{ path, query: q, bindings } ->
    stmt = try prepare! { path, query: q }
    execute_prepared! { stmt, bindings }

## A function that executes a prepared execute stmt that doesn't return any data.
ExecuteFn in : in => Result {} [SqliteErr ErrCode Str, UnhandledRows]

## Prepare a lambda to execute a SQL statement that doesn't return any rows (like INSERT, UPDATE, DELETE).
##
## This is useful when you have a query that will be called many times, as it is more efficient than
## preparing the query each time it is called. This is usually done in `init!` with the prepared `Stmt` stored in the model.
##
## ```
## prepared_query! = try Sqlite.prepare_execute! {
##     path: "path/to/database.db",
##     query: "INSERT INTO todos (task, status) VALUES (:task, :status)",
##     bindings: \{task, status} -> [{name: ":task", value: String task}, {name: ":status", value: String task}]
## }
##
## try prepared_query! { task: "create a todo", status: "completed" }
## ```
prepare_execute! :
    {
        path : Str,
        query : Str,
        bindings : in -> List Binding,
    }
    => Result (ExecuteFn in) [SqliteErr ErrCode Str]
prepare_execute! = \{ path, query: q, bindings: tranform } ->
    stmt = try prepare! { path, query: q }
    Ok \input ->
        execute_prepared! { stmt, bindings: tranform input }

## Execute a prepared SQL statement that doesn't return any rows.
##
## This is more efficient than [execute!] when running the same query multiple times
## as it reuses the prepared statement.
execute_prepared! :
    {
        stmt : Stmt,
        bindings : List Binding,
    }
    => Result {} [SqliteErr ErrCode Str, UnhandledRows]
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

## Execute a SQL query and decode exactly one row into a value.
##
## Example:
## ```
## # count the number of rows in the `users` table
## count = try Sqlite.query! {
##     path: db_path,
##     query: "SELECT COUNT(*) as \"count\" FROM users;",
##     bindings: [],
##     row: Sqlite.u64 "count",
## }
## ```
query! :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
        row : SqlDecode out (RowCountErr err),
    }
    => Result out (SqlDecodeErr (RowCountErr err))
query! = \{ path, query: q, bindings, row } ->
    stmt = try prepare! { path, query: q }
    query_prepared! { stmt, bindings, row }

## A function that executes a perpared query and decodes exactly one row into a value.
QueryFn in out err : in => Result out (SqlDecodeErr (RowCountErr err))

## Prepare a lambda to execute a SQL query and decode exactly one row into a value.
##
## This is useful when you have a query that will be called many times, as it is more efficient than
## preparing the query each time it is called. This is usually done in `init!` with the prepared `Stmt` stored in the model.
##
## ```
## prepared_query! = try Sqlite.prepare_query! {
##     path: "path/to/database.db",
##     query: "SELECT COUNT(*) as \"count\" FROM users;",
##     bindings: \{} -> []
##     row: Sqlite.u64 "count",
## }
##
## count = try prepared_query! {}
## ```
prepare_query! :
    {
        path : Str,
        query : Str,
        bindings : in -> List Binding,
        row : SqlDecode out (RowCountErr err),
    }
    => Result (QueryFn in out err) [SqliteErr ErrCode Str]
prepare_query! = \{ path, query: q, bindings: tranform, row } ->
    stmt = try prepare! { path, query: q }
    Ok \input ->
        query_prepared! { stmt, bindings: tranform input, row }

## Execute a prepared SQL query and decode exactly one row into a value.
##
## This is more efficient than [query!] when running the same query multiple times
## as it reuses the prepared statement.
query_prepared! :
    {
        stmt : Stmt,
        bindings : List Binding,
        row : SqlDecode out (RowCountErr err),
    }
    => Result out (SqlDecodeErr (RowCountErr err))
query_prepared! = \{ stmt, bindings, row: decode } ->
    try bind! stmt bindings
    res = decode_exactly_one_row! stmt decode
    try reset! stmt
    res

## Execute a SQL query and decode multiple rows into a list of values.
##
## Example:
## ```
## Sqlite.query_many! {
##     path: "path/to/database.db",
##     query: "SELECT * FROM todos;",
##     bindings: [],
##     rows: { Sqlite.decode_record <-
##         id: Sqlite.i64 "id",
##         task: Sqlite.str "task",
##     },
## }
## ```
query_many! :
    {
        path : Str,
        query : Str,
        bindings : List Binding,
        rows : SqlDecode out err,
    }
    => Result (List out) (SqlDecodeErr err)
query_many! = \{ path, query: q, bindings, rows } ->
    stmt = try prepare! { path, query: q }
    query_many_prepared! { stmt, bindings, rows }

## A function that executes a perpared query and decodes mutliple rows into a list of values.
QueryManyFn in out err : in => Result (List out) (SqlDecodeErr err)

## Prepare a lambda to execute a SQL query and decode multiple rows into a list of values.
##
## This is useful when you have a query that will be called many times, as it is more efficient than
## preparing the query each time it is called. This is usually done in `init!` with the prepared `Stmt` stored in the model.
##
## ```
## prepared_query! = try Sqlite.prepare_query_many! {
##     path: "path/to/database.db",
##     query: "SELECT * FROM todos;",
##     bindings: \{} -> []
##     rows: { Sqlite.decode_record <-
##         id: Sqlite.i64 "id",
##         task: Sqlite.str "task",
##     },
## }
##
## rows = try prepared_query! {}
## ```
prepare_query_many! :
    {
        path : Str,
        query : Str,
        bindings : in -> List Binding,
        rows : SqlDecode out err,
    }
    => Result (QueryManyFn in out err) [SqliteErr ErrCode Str]
prepare_query_many! = \{ path, query: q, bindings: tranform, rows } ->
    stmt = try prepare! { path, query: q }
    Ok \input ->
        query_many_prepared! { stmt, bindings: tranform input, rows }

## Execute a prepared SQL query and decode multiple rows into a list of values.
##
## This is more efficient than [query_many!] when running the same query multiple times
## as it reuses the prepared statement.
query_many_prepared! :
    {
        stmt : Stmt,
        bindings : List Binding,
        rows : SqlDecode out err,
    }
    => Result (List out) (SqlDecodeErr err)
query_many_prepared! = \{ stmt, bindings, rows: decode } ->
    try bind! stmt bindings
    res = decode_rows! stmt decode
    try reset! stmt
    res

## A function to execute a transaction lambda and automatically rollback on failure.
TransactionFn ok err : ({} => Result ok err) => Result ok [FailedToBeginTransaction, FailedToEndTransaction, FailedToRollbackTransaction, TransactionFailed err]

## Generates a higher order function for running a transaction.
## The transaction will automatically rollback on any error.
##
## Deferred means that the transaction does not actually start until the database is first accessed.
## Immediate causes the database connection to start a new write immediately, without waiting for a write statement.
## Exclusive is similar to Immediate in that a write transaction is started immediately. Exclusive and Immediate are the same in WAL mode, but in other journaling modes, Exclusive prevents other database connections from reading the database while the transaction is underway.
##
## ```
## exec_transaction! = try prepare_transaction! { path: "path/to/database.db" }
##
## try exec_transaction! \{} ->
##     try Sqlite.execute! {
##         path: "path/to/database.db",
##         query: "INSERT INTO users (first, last) VALUES (:first, :last);",
##         bindings: [
##             { name: ":first", value: String "John" },
##             { name: ":last", value: String "Smith" },
##         ],
##     }
##
##     # Oh no, hit an error. Need to rollback.
##     # Note: Error could be anything.
##     Err NeedToRollback
## ```
prepare_transaction! :
    {
        path : Str,
        mode ? [Deferred, Immediate, Exclusive],
    }
    =>
    Result (TransactionFn ok err) [SqliteErr ErrCode Str]
prepare_transaction! = \{ path, mode ? Deferred } ->
    mode_str =
        when mode is
            Deferred -> "DEFERRED"
            Immediate -> "IMMEDIATE"
            Exclusive -> "EXCLUSIVE"

    begin_stmt = try prepare! { path, query: "BEGIN $(mode_str)" }
    end_stmt = try prepare! { path, query: "END" }
    rollback_stmt = try prepare! { path, query: "ROLLBACK" }

    Ok \transaction! ->
        Sqlite.execute_prepared! {
            stmt: begin_stmt,
            bindings: [],
        }
        |> Result.mapErr \_ -> FailedToBeginTransaction
        |> try

        end_transaction! = \res ->
            when res is
                Ok v ->
                    Sqlite.execute_prepared! {
                        stmt: end_stmt,
                        bindings: [],
                    }
                    |> Result.mapErr \_ -> FailedToEndTransaction
                    |> try
                    Ok v

                Err e ->
                    Err (TransactionFailed e)

        when transaction! {} |> end_transaction! is
            Ok v ->
                Ok v

            Err e ->
                Sqlite.execute_prepared! {
                    stmt: rollback_stmt,
                    bindings: [],
                }
                |> Result.mapErr \_ -> FailedToRollbackTransaction
                |> try

                Err e

SqlDecodeErr err : [FieldNotFound Str, SqliteErr ErrCode Str]err
SqlDecode a err := List Str -> (Stmt => Result a (SqlDecodeErr err))

## Decode a Sqlite row into a record by combining decoders.
##
## Example:
## ```
## { Sqlite.decode_record <-
##     id: Sqlite.i64 "id",
##     task: Sqlite.str "task",
## }
## ```
decode_record : SqlDecode a err, SqlDecode b err, (a, b -> c) -> SqlDecode c err
decode_record = \@SqlDecode gen_first, @SqlDecode gen_second, mapper ->
    @SqlDecode \cols ->
        decode_first! = gen_first cols
        decode_second! = gen_second cols

        \stmt ->
            first = try decode_first! stmt
            second = try decode_second! stmt
            Ok (mapper first second)

## Transform the output of a decoder by applying a function to the decoded value.
##
## Example:
## ```
## Sqlite.i64 "id" |> Sqlite.map_value Num.toStr
## ```
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
decoder = \fn ->
    \name ->
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

## Decode a [Value] keeping it tagged. This is useful when data could be many possible types.
##
## For example here we build a decoder that decodes the rows into a list of records with `id` and `mixed_data` fields:
## ```
## Sqlite.query_many! {
##     path: "path/to/database.db",
##     query: "SELECT id, mix_data FROM users;",
##     bindings: [],
##     rows: { Sqlite.decode_record <-
##         id: Sqlite.i64 "id",
##         mix_data: Sqlite.tagged_value "mixed_data",
##     },
## }
## ```
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
##         id: Sqlite.i64 "id",
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
##         id: Sqlite.i64 "id",
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
internal_to_external_error : InternalSqlite.SqliteError -> [SqliteErr ErrCode Str]
internal_to_external_error = \{ code, message } ->
    SqliteErr (code_from_i64 code) message

# internal use only
code_from_i64 : I64 -> ErrCode
code_from_i64 = \code ->
    if code == 1 || code == 0 then
        Error
    else if code == 2 then
        Internal
    else if code == 3 then
        Perm
    else if code == 4 then
        Abort
    else if code == 5 then
        Busy
    else if code == 6 then
        Locked
    else if code == 7 then
        NoMem
    else if code == 8 then
        ReadOnly
    else if code == 9 then
        Interrupt
    else if code == 10 then
        IOErr
    else if code == 11 then
        Corrupt
    else if code == 12 then
        NotFound
    else if code == 13 then
        Full
    else if code == 14 then
        CanNotOpen
    else if code == 15 then
        Protocol
    else if code == 16 then
        Empty
    else if code == 17 then
        Schema
    else if code == 18 then
        TooBig
    else if code == 19 then
        Constraint
    else if code == 20 then
        Mismatch
    else if code == 21 then
        Misuse
    else if code == 22 then
        NoLFS
    else if code == 23 then
        AuthDenied
    else if code == 24 then
        Format
    else if code == 25 then
        OutOfRange
    else if code == 26 then
        NotADatabase
    else if code == 27 then
        Notice
    else if code == 28 then
        Warning
    else if code == 100 then
        Row
    else if code == 101 then
        Done
    else
        Unknown code

## Convert a [ErrCode] to a pretty string for display purposes.
errcode_to_str : ErrCode -> Str
errcode_to_str = \code ->
    when code is
        Error -> "Error: Sql error or missing database"
        Internal -> "Internal: Internal logic error in Sqlite"
        Perm -> "Perm: Access permission denied"
        Abort -> "Abort: Callback routine requested an abort"
        Busy -> "Busy: The database file is locked"
        Locked -> "Locked: A table in the database is locked"
        NoMem -> "NoMem: A malloc() failed"
        ReadOnly -> "ReadOnly: Attempt to write a readonly database"
        Interrupt -> "Interrupt: Operation terminated by sqlite3_interrupt("
        IOErr -> "IOErr: Some kind of disk I/O error occurred"
        Corrupt -> "Corrupt: The database disk image is malformed"
        NotFound -> "NotFound: Unknown opcode in sqlite3_file_control()"
        Full -> "Full: Insertion failed because database is full"
        CanNotOpen -> "CanNotOpen: Unable to open the database file"
        Protocol -> "Protocol: Database lock protocol error"
        Empty -> "Empty: Database is empty"
        Schema -> "Schema: The database schema changed"
        TooBig -> "TooBig: String or BLOB exceeds size limit"
        Constraint -> "Constraint: Abort due to constraint violation"
        Mismatch -> "Mismatch: Data type mismatch"
        Misuse -> "Misuse: Library used incorrectly"
        NoLFS -> "NoLFS: Uses OS features not supported on host"
        AuthDenied -> "AuthDenied: Authorization denied"
        Format -> "Format: Auxiliary database format error"
        OutOfRange -> "OutOfRange: 2nd parameter to sqlite3_bind out of range"
        NotADatabase -> "NotADatabase: File opened that is not a database file"
        Notice -> "Notice: Notifications from sqlite3_log()"
        Warning -> "Warning: Warnings from sqlite3_log()"
        Row -> "Row: sqlite3_step() has another row ready"
        Done -> "Done: sqlite3_step() has finished executing"
        Unknown c -> "Unknown: error code $(Num.toStr c) not known"
