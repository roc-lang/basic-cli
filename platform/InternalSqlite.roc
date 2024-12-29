module [
    SqliteError,
    SqliteValue,
    SqliteState,
    SqliteBindings,
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
