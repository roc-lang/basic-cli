import IOErr
import InternalHttp
import InternalSqlite
import Resource

## Declare the hosted effects and ABI-safe data exchanged with the native host.
Host :: [].{
	NativeOsStr : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	NativePath : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

	Cmd : {
		args : List(NativeOsStr),
		clear_envs : Bool,
		cwd : List(NativeOsStr),
		stdin_mode : U8,
		stdout_mode : U8,
		stderr_mode : U8,
		stdin_bytes : List(U8),
		timeout_ms : U64,
		output_limit : U64,
		pending_limit : U64,
		manage_tree : Bool,
		merge_stderr : Bool,
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

	PathType : [File, Dir, SymLink, Other]

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
	file_append_bytes! : NativePath, List(U8) => Try({}, [FileErr(IOErr)])
	file_append_utf8! : NativePath, Str => Try({}, [FileErr(IOErr)])
	file_open_reader! : NativePath, U64 => Try(Resource.FileReader, [FileErr(IOErr)])
	file_read_line! : Resource.FileReader => Try(List(U8), [EndOfInput, FileErr(IOErr)])
	file_read_until! : Resource.FileReader, U8 => Try(List(U8), [EndOfInput, FileErr(IOErr)])
	file_delete! : NativePath => Try({}, [FileErr(IOErr)])
	file_size_in_bytes! : NativePath => Try(U64, [FileErr(IOErr)])
	file_is_executable! : NativePath => Try(Bool, [FileErr(IOErr)])
	file_is_readable! : NativePath => Try(Bool, [FileErr(IOErr)])
	file_is_writable! : NativePath => Try(Bool, [FileErr(IOErr)])
	file_time_accessed! : NativePath => Try(I128, [FileErr(IOErr)])
	file_time_modified! : NativePath => Try(I128, [FileErr(IOErr)])
	file_time_created! : NativePath => Try(I128, [FileErr(IOErr)])

	http_send_request! : InternalHttp.RequestToAndFromHost => Try(InternalHttp.ResponseToAndFromHost, InternalHttp.TransportErr)

	locale_get! : () => Try(Str, [NotAvailable])
	locale_all! : () => List(Str)

	path_type! : NativePath => Try(PathType, IOErr)

	random_seed_u64! : () => Try(U64, [RandomErr(IOErr)])
	random_seed_u32! : () => Try(U32, [RandomErr(IOErr)])

	sleep_nanos! : U64 => {}

	sqlite_prepare! : NativePath, Str => Try(Resource.SqliteStmt, InternalSqlite.SqliteError)
	sqlite_bind! : Resource.SqliteStmt, List(InternalSqlite.SqliteBindings) => Try({}, InternalSqlite.SqliteError)
	sqlite_columns! : Resource.SqliteStmt => List(Str)
	sqlite_column_value! : Resource.SqliteStmt, U64 => Try(InternalSqlite.SqliteValue, InternalSqlite.SqliteError)
	sqlite_step! : Resource.SqliteStmt => Try(Bool, InternalSqlite.SqliteError)
	sqlite_reset! : Resource.SqliteStmt => Try({}, InternalSqlite.SqliteError)

	stderr_line! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write_bytes! : List(U8) => Try({}, [StderrErr(IOErr)])

	stdin_line! : () => Try(List(U8), [EndOfInput, StdinErr(IOErr)])
	stdin_bytes! : () => Try(List(U8), [EndOfInput, StdinErr(IOErr)])
	stdin_read_to_end! : () => Try(List(U8), [StdinErr(IOErr)])

	stdout_line! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr)])

	tcp_connect! : Str, U16, U64 => Try(Resource.TcpStream, Str)
	tcp_read_up_to! : Resource.TcpStream, U64, U64 => Try(List(U8), Str)
	tcp_read_exactly! : Resource.TcpStream, U64, U64 => Try(List(U8), Str)
	tcp_read_until! : Resource.TcpStream, U8, U64, U64 => Try(List(U8), Str)
	tcp_write! : Resource.TcpStream, List(U8), U64 => Try({}, Str)

	tty_enable_raw_mode! : () => Try({}, IOErr)
	tty_disable_raw_mode! : () => Try({}, IOErr)

	# The reading is signed nanoseconds since the Unix epoch, negative before
	# 1970. It crosses inside a `Try` because a bare 128-bit integer return is not
	# known to cross correctly on x86_64-windows with every compiler backend; a
	# `Try` result is returned through memory on every target. The host reports
	# `ClockOutOfRange` only for a reading that does not fit in an `I128`.
	utc_now! : () => Try(I128, [ClockOutOfRange])

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

	CopyOptions : { symlinks : [Follow, Preserve], destination : [RequireNew, Merge] }
	CopyFailure : { operation : Str, source : NativePath, destination : NativePath, error : IOErr }
	path_copy! : NativePath, NativePath => Try({}, CopyFailure)
	path_copy_dir! : NativePath, NativePath, CopyOptions => Try({}, CopyFailure)
	path_absolute! : NativePath => Try(NativePath, IOErr)
	path_canonicalize! : NativePath => Try(NativePath, IOErr)
	env_create_temp_dir! : NativePath, Str => Try(NativePath, IOErr)
	monotonic_now! : () => U64

	CmdRunResult : { exit_code : I32, signal : I32, stdout_bytes : List(U8), stderr_bytes : List(U8), failure : U8 }
	ChildEvent : { stream : U8, bytes : List(U8) }
	cmd_spawn! : Cmd => Try(Resource.Child, IOErr)
	cmd_run! : Cmd => Try(CmdRunResult, IOErr)
	child_pid! : Resource.Child => Try(U32, IOErr)
	child_wait! : Resource.Child => Try(CmdRunResult, IOErr)
	child_try_wait! : Resource.Child => Try(List(CmdRunResult), IOErr)
	child_kill! : Resource.Child => Try({}, IOErr)
	child_close! : Resource.Child => Try({}, IOErr)
	child_close_stdin! : Resource.Child => Try({}, IOErr)
	child_write! : Resource.Child, List(U8), U64 => Try({}, IOErr)
	child_read! : Resource.Child, U64, U64 => Try(ChildEvent, IOErr)

	tcp_listen! : Str, U16, U64 => Try(Resource.TcpListener, Str)
	tcp_local_port! : Resource.TcpListener => Try(U16, Str)
	tcp_accept! : Resource.TcpListener, U64 => Try(Resource.TcpStream, Str)
	tcp_listener_close! : Resource.TcpListener => Try({}, Str)

	env_program_name! : () => Try(NativeOsStr, [ProgramNameUnavailable])

	file_read_up_to! : Resource.FileReader, U64 => Try(List(U8), [EndOfInput, FileErr(IOErr)])
	file_read_exactly! : Resource.FileReader, U64 => Try(List(U8), [FileErr(IOErr), UnexpectedEndOfInput])
	file_reader_position! : Resource.FileReader => Try(U64, [FileErr(IOErr)])
	file_reader_seek! : Resource.FileReader, [Start(U64), Current(I64), End(I64)] => Try(U64, [FileErr(IOErr)])
}
