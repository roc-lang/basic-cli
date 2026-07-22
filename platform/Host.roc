import IOErr exposing [IOErr]
import InternalHttp
import InternalSqlite

## Declare the hosted effects and ABI-safe data exchanged with the native host.
Host :: [].{
	NativeOsStr : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	NativePath : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

	Cmd : {
		args : List(NativeOsStr),
		clear_envs : Bool,
		envs : List(NativeOsStr),
		program : NativeOsStr,
	}

	CmdOutputSuccess : {
		stderr_bytes : List(U8),
		stdout_bytes : List(U8),
	}

	CmdOutputFailure : {
		stderr_bytes : List(U8),
		stdout_bytes : List(U8),
		exit_code : I32,
	}

	FileReader :: Box(U64)

	PathType : [File, Dir, SymLink, Other]

	SqliteStmt :: Box(U64)

	TcpStream :: Box(U64)

	cmd_exec_exit_code! : Cmd => Try(I32, IOErr)
	cmd_exec_output! : Cmd => Try(CmdOutputSuccess, [NonZeroExitCode(CmdOutputFailure), FailedToGetExitCode(IOErr)])

	dir_create! : NativePath => Try({}, [DirErr(IOErr)])
	dir_create_all! : NativePath => Try({}, [DirErr(IOErr)])
	dir_delete_empty! : NativePath => Try({}, [DirErr(IOErr)])
	dir_delete_all! : NativePath => Try({}, [DirErr(IOErr)])
	dir_list! : NativePath => Try(List(NativePath), [DirErr(IOErr)])

	env_var! : NativeOsStr => Try(NativeOsStr, [VarNotFound(NativeOsStr), EnvErr(IOErr)])
	env_cwd! : () => Try(NativePath, [CwdUnavailable])
	env_exe_path! : () => Try(NativePath, [ExePathUnavailable])
	env_temp_dir! : () => NativePath

	file_read_bytes! : NativePath => Try(List(U8), [FileErr(IOErr)])
	file_write_bytes! : NativePath, List(U8) => Try({}, [FileErr(IOErr)])
	file_read_utf8! : NativePath => Try(Str, [FileErr(IOErr)])
	file_write_utf8! : NativePath, Str => Try({}, [FileErr(IOErr)])
	file_open_reader! : NativePath, U64 => Try(FileReader, [FileErr(IOErr)])
	file_read_line! : FileReader => Try(List(U8), [FileErr(IOErr)])
	file_delete! : NativePath => Try({}, [FileErr(IOErr)])
	file_size_in_bytes! : NativePath => Try(U64, [FileErr(IOErr)])
	file_is_executable! : NativePath => Try(Bool, [FileErr(IOErr)])
	file_is_readable! : NativePath => Try(Bool, [FileErr(IOErr)])
	file_is_writable! : NativePath => Try(Bool, [FileErr(IOErr)])
	file_time_accessed! : NativePath => Try(U128, [FileErr(IOErr)])
	file_time_modified! : NativePath => Try(U128, [FileErr(IOErr)])
	file_time_created! : NativePath => Try(U128, [FileErr(IOErr)])

	http_send_request! : InternalHttp.RequestToAndFromHost => Try(InternalHttp.ResponseToAndFromHost, InternalHttp.TransportErr)

	locale_get! : () => Try(Str, [NotAvailable])
	locale_all! : () => List(Str)

	path_type! : NativePath => Try(PathType, IOErr)

	random_seed_u64! : () => Try(U64, [RandomErr(IOErr)])
	random_seed_u32! : () => Try(U32, [RandomErr(IOErr)])

	sleep_millis! : U64 => {}

	sqlite_prepare! : NativePath, Str => Try(SqliteStmt, InternalSqlite.SqliteError)
	sqlite_bind! : SqliteStmt, List(InternalSqlite.SqliteBindings) => Try({}, InternalSqlite.SqliteError)
	sqlite_columns! : SqliteStmt => List(Str)
	sqlite_column_value! : SqliteStmt, U64 => Try(InternalSqlite.SqliteValue, InternalSqlite.SqliteError)
	sqlite_step! : SqliteStmt => Try(Bool, InternalSqlite.SqliteError)
	sqlite_reset! : SqliteStmt => Try({}, InternalSqlite.SqliteError)

	stderr_line! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write_bytes! : List(U8) => Try({}, [StderrErr(IOErr)])

	stdin_line! : () => Try(Str, [EndOfFile, StdinErr(IOErr)])
	stdin_bytes! : () => Try(List(U8), [EndOfFile, StdinErr(IOErr)])
	stdin_read_to_end! : () => Try(List(U8), [StdinErr(IOErr)])

	stdout_line! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr)])

	tcp_connect! : Str, U16 => Try(TcpStream, Str)
	tcp_read_up_to! : TcpStream, U64 => Try(List(U8), Str)
	tcp_read_exactly! : TcpStream, U64 => Try(List(U8), Str)
	tcp_read_until! : TcpStream, U8 => Try(List(U8), Str)
	tcp_write! : TcpStream, List(U8) => Try({}, Str)

	tty_enable_raw_mode! : () => {}
	tty_disable_raw_mode! : () => {}

	# TODO(https://github.com/roc-lang/roc/issues/10163): revert to a bare U128
	# return once the compiler emits the clang/Rust u128 return convention on
	# x86_64-windows; bare U128 returns are currently misread there, while
	# Try-wrapped results cross the boundary correctly on every target.
	utc_now! : () => Try(U128, [ClockBeforeEpoch])

	# New hosted functions are kept at the end to avoid renumbering existing
	# generated glue more than necessary.
	file_hard_link! : NativePath, NativePath => Try({}, [FileErr(IOErr)])
	file_rename! : NativePath, NativePath => Try({}, [FileErr(IOErr)])
	env_platform! : () => {
		arch : [X86, X64, ARM, AARCH64, OTHER(Str)],
		os : [LINUX, MACOS, WINDOWS, OTHER(Str)],
	}
	env_dict! : () => List((NativeOsStr, NativeOsStr))
	env_set_cwd! : NativePath => Try({}, IOErr)
	# Timeout-aware TCP functions are appended to preserve existing hosted ABI numbering.
	tcp_connect_with_timeout! : Str, U16, U64 => Try(TcpStream, Str)
	tcp_read_up_to_with_timeout! : TcpStream, U64, U64 => Try(List(U8), Str)
	tcp_read_exactly_with_timeout! : TcpStream, U64, U64 => Try(List(U8), Str)
	tcp_read_until_bounded! : TcpStream, U8, U64 => Try(List(U8), Str)
	tcp_read_until_with_timeout! : TcpStream, U8, U64, U64 => Try(List(U8), Str)
	tcp_write_with_timeout! : TcpStream, List(U8), U64 => Try({}, Str)
}
