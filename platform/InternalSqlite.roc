## Define the host-ABI types shared by SQLite effects and the public module.
## These types map directly to the generated Rust glue types.
InternalSqlite :: [].{

	## A value bound to a statement parameter.
	Value : [
		Null,
		Real(F64),
		Integer(I64),
		String(Str),
		Bytes(List(U8)),
	]

	## A value read from a result column. Text crosses as the bytes SQLite
	## stores, so that the public module can report text that is not UTF-8.
	Cell : [
		Null,
		Real(F64),
		Integer(I64),
		Text(List(U8)),
		Bytes(List(U8)),
	]

	## An error reported by SQLite: its extended result code and message.
	Failure : {
		extended_code : I64,
		message : Str,
	}

	## Why a statement was not run.
	Problem : [
		Interrupted,
		Failed(Failure),
		Closed,
		WrongParamCount({ expected : U64, given : U64 }),
		ReturnsRows,
		MultipleStatements,
	]
}
