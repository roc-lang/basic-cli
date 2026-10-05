## Define the host-ABI types shared by SQLite effects and the public module.
## These records map directly to the generated Rust glue types.
InternalSqlite :: [].{
	SqliteError : {
		code : I64,
		message : Str,
	}

	SqliteValue : [
		Null,
		Real(F64),
		Integer(I64),
		String(Str),
		Bytes(List(U8)),
	]

	SqliteState : [
		Row,
		Done,
	]

	SqliteBindings : {
		name : Str,
		value : SqliteValue,
	}
}
