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

Value : InternalSqlite.SqliteValue
Code : InternalSqlite.SqliteErrCode
Error : [SqlError Code Str]
Binding : InternalSqlite.SqliteBindings
Stmt := Box {}

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

bind! : Stmt, List Binding => Result {} Error
bind! = \@Stmt stmt, bindings ->
    Host.sqlite_bind! stmt bindings
    |> Result.mapErr internal_to_external_error

columns! : Stmt => List Str
columns! = \@Stmt stmt ->
    Host.sqlite_columns! stmt

column_value! : Stmt, U64 => Result Value Error
column_value! = \@Stmt stmt, i ->
    Host.sqlite_column_value! stmt i
    |> Result.mapErr internal_to_external_error

step! : Stmt => Result [Row, Done] Error
step! = \@Stmt stmt ->
    Host.sqlite_step! stmt
    |> Result.mapErr internal_to_external_error

reset! : Stmt => Result {} Error
reset! = \@Stmt stmt ->
    Host.sqlite_reset! stmt
    |> Result.mapErr internal_to_external_error

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

decode_record : SqlDecode a err, SqlDecode b err, (a, b -> c) -> SqlDecode c err
decode_record = \@SqlDecode gen_first, @SqlDecode gen_second, mapper ->
    @SqlDecode \cols ->
        decode_first! = gen_first cols
        decode_second! = gen_second cols

        \stmt ->
            first = try decode_first! stmt
            second = try decode_second! stmt
            Ok (mapper first second)

map_value : SqlDecode a err, (a -> b) -> SqlDecode b err
map_value = \@SqlDecode gen_decode, mapper ->
    @SqlDecode \cols ->
        decode! = gen_decode cols

        \stmt ->
            val = try decode! stmt
            Ok (mapper val)

RowCountErr err : [NoRowsReturned, TooManyRowsReturned]err
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

str : Str -> SqlDecode Str UnexpectedTypeErr
str = decoder \val ->
    when val is
        String s -> Ok s
        _ -> to_unexpected_type_err val

bytes : Str -> SqlDecode (List U8) UnexpectedTypeErr
bytes = decoder \val ->
    when val is
        Bytes b -> Ok b
        _ -> to_unexpected_type_err val

int_decoder : (I64 -> Result a err) -> (Str -> SqlDecode a [FailedToDecodeInteger err]UnexpectedTypeErr)
int_decoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.mapErr FailedToDecodeInteger
            _ -> to_unexpected_type_err val

real_decoder : (F64 -> Result a err) -> (Str -> SqlDecode a [FailedToDecodeReal err]UnexpectedTypeErr)
real_decoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.mapErr FailedToDecodeReal
            _ -> to_unexpected_type_err val

i64 : Str -> SqlDecode I64 [FailedToDecodeInteger []]UnexpectedTypeErr
i64 = int_decoder Ok

i32 : Str -> SqlDecode I32 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
i32 = int_decoder Num.toI32Checked

i16 : Str -> SqlDecode I16 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
i16 = int_decoder Num.toI16Checked

i8 : Str -> SqlDecode I8 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
i8 = int_decoder Num.toI8Checked

u64 : Str -> SqlDecode U64 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u64 = int_decoder Num.toU64Checked

u32 : Str -> SqlDecode U32 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u32 = int_decoder Num.toU32Checked

u16 : Str -> SqlDecode U16 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u16 = int_decoder Num.toU16Checked

u8 : Str -> SqlDecode U8 [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
u8 = int_decoder Num.toU8Checked

f64 : Str -> SqlDecode F64 [FailedToDecodeReal []]UnexpectedTypeErr
f64 = real_decoder Ok

f32 : Str -> SqlDecode F32 [FailedToDecodeReal []]UnexpectedTypeErr
f32 = real_decoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# dec = realSqlDecoder Ok

# These are the same decoders as above but Nullable.
# If the sqlite field is `Null`, they will return `Null`.

Nullable a : [NotNull a, Null]

nullable_str : Str -> SqlDecode (Nullable Str) UnexpectedTypeErr
nullable_str = decoder \val ->
    when val is
        String s -> Ok (NotNull s)
        Null -> Ok Null
        _ -> to_unexpected_type_err val

nullable_bytes : Str -> SqlDecode (Nullable (List U8)) UnexpectedTypeErr
nullable_bytes = decoder \val ->
    when val is
        Bytes b -> Ok (NotNull b)
        Null -> Ok Null
        _ -> to_unexpected_type_err val

nullable_int_decoder : (I64 -> Result a err) -> (Str -> SqlDecode (Nullable a) [FailedToDecodeInteger err]UnexpectedTypeErr)
nullable_int_decoder = \cast ->
    decoder \val ->
        when val is
            Integer i -> cast i |> Result.map NotNull |> Result.mapErr FailedToDecodeInteger
            Null -> Ok Null
            _ -> to_unexpected_type_err val

nullable_real_decoder : (F64 -> Result a err) -> (Str -> SqlDecode (Nullable a) [FailedToDecodeReal err]UnexpectedTypeErr)
nullable_real_decoder = \cast ->
    decoder \val ->
        when val is
            Real r -> cast r |> Result.map NotNull |> Result.mapErr FailedToDecodeReal
            Null -> Ok Null
            _ -> to_unexpected_type_err val

nullable_i64 : Str -> SqlDecode (Nullable I64) [FailedToDecodeInteger []]UnexpectedTypeErr
nullable_i64 = nullable_int_decoder Ok

nullable_i32 : Str -> SqlDecode (Nullable I32) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_i32 = nullable_int_decoder Num.toI32Checked

nullable_i16 : Str -> SqlDecode (Nullable I16) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_i16 = nullable_int_decoder Num.toI16Checked

nullable_i8 : Str -> SqlDecode (Nullable I8) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_i8 = nullable_int_decoder Num.toI8Checked

nullable_u64 : Str -> SqlDecode (Nullable U64) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u64 = nullable_int_decoder Num.toU64Checked

nullable_u32 : Str -> SqlDecode (Nullable U32) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u32 = nullable_int_decoder Num.toU32Checked

nullable_u16 : Str -> SqlDecode (Nullable U16) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u16 = nullable_int_decoder Num.toU16Checked

nullable_u8 : Str -> SqlDecode (Nullable U8) [FailedToDecodeInteger [OutOfBounds]]UnexpectedTypeErr
nullable_u8 = nullable_int_decoder Num.toU8Checked

nullable_f64 : Str -> SqlDecode (Nullable F64) [FailedToDecodeReal []]UnexpectedTypeErr
nullable_f64 = nullable_real_decoder Ok

nullable_f32 : Str -> SqlDecode (Nullable F32) [FailedToDecodeReal []]UnexpectedTypeErr
nullable_f32 = nullable_real_decoder (\x -> Num.toF32 x |> Ok)

# TODO: Mising Num.toDec and Num.toDecChecked
# nullable_dec = nullable_real_decoder Ok

internal_to_external_error : InternalSqlite.SqliteError -> Error
internal_to_external_error = \{ code, message } ->
    SqlError (code_from_i64 code) message

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
