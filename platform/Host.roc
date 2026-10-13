import IOErr
import InternalHttp
import InternalSqlite
import Resource

## Declare the hosted effects and ABI-safe data exchanged with the native host.
Host :: [].{
	NativeOsStr : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	NativePath : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]

	# A command whose streams, deadline and limits are already resolved: `Cmd.roc`
	# applies the defaults of the entry point before the command crosses.
	Cmd : {
		args : List(NativeOsStr),
		clear_envs : Bool,
		cwd : [Inherit, Dir(NativePath)],
		stdin : [Inherit, Null, Bytes(List(U8)), Pipe],
		stdout : [Inherit, Null, Capture, Tee, Pipe],
		stderr : [Inherit, Null, Capture, Tee, Pipe, MergeWithStdout],
		timeout : [NoTimeout, AfterNanos(U64)],
		output_limit : [NoLimit, MaxBytes(U64)],
		pending_limit : U64,
		manage_tree : Bool,
		envs : List(NativeOsStr),
		program : NativeOsStr,
	}

	PathType : [File, Dir, SymLink, Other]

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

	sqlite_open! : NativePath, [ReadWriteCreate, ReadWrite, ReadOnly], U64 => Try(Resource.SqliteDb, InternalSqlite.Failure)
	sqlite_close! : Resource.SqliteDb => Try({}, InternalSqlite.Failure)
	sqlite_execute! : Resource.SqliteDb, Str, List(InternalSqlite.Value) => Try({}, InternalSqlite.Problem)
	sqlite_execute_script! : Resource.SqliteDb, Str => Try({}, InternalSqlite.Problem)
	sqlite_query! : Resource.SqliteDb, Str, List(InternalSqlite.Value) => Try(Resource.SqliteRows, InternalSqlite.Problem)
	sqlite_columns! : Resource.SqliteRows => List(Str)
	sqlite_next! : Resource.SqliteRows => Try(List(InternalSqlite.Cell), [Done, Closed, Failed(InternalSqlite.Failure)])

	stderr_line! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write! : Str => Try({}, [StderrErr(IOErr)])
	stderr_write_bytes! : List(U8) => Try({}, [StderrErr(IOErr)])

	stdin_line! : () => Try(List(U8), [EndOfInput, StdinErr(IOErr)])
	stdin_bytes! : () => Try(List(U8), [EndOfInput, StdinErr(IOErr)])
	stdin_read_to_end! : () => Try(List(U8), [StdinErr(IOErr)])

	stdout_line! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write! : Str => Try({}, [StdoutErr(IOErr)])
	stdout_write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr)])

	# Tcp timeouts cross as nanoseconds. A connection's I/O timeout and line
	# limit live in `Tcp.Connection` and are passed with each read or write.
	tcp_connect! : Str, U16, U64 => Try(Resource.TcpConnection, [TcpErr(IOErr)])
	tcp_read_up_to! : Resource.TcpConnection, U64, U64 => Try(List(U8), [EndOfInput, TcpErr(IOErr)])
	tcp_read_exactly! : Resource.TcpConnection, U64, U64 => Try(List(U8), [TcpErr(IOErr), UnexpectedEndOfInput])
	tcp_read_until! : Resource.TcpConnection, U8, U64, U64 => Try(List(U8), [EndOfInput, ReadLimitExceeded(U64), TcpErr(IOErr)])
	tcp_read_line! : Resource.TcpConnection, U64, U64 => Try(List(U8), [EndOfInput, ReadLimitExceeded(U64), TcpErr(IOErr)])
	tcp_write! : Resource.TcpConnection, List(U8), U64 => Try({}, [TcpErr(IOErr)])

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

	CmdPartialOutput : { stdout_bytes : List(U8), stderr_bytes : List(U8) }
	CmdOutput : { status : [Exited(I32), Signaled(I32)], stdout_bytes : List(U8), stderr_bytes : List(U8) }
	CmdErr : [StartFailed(IOErr), TimedOut(CmdPartialOutput), OutputLimitExceeded(CmdPartialOutput), IOErr(IOErr)]
	cmd_spawn! : Cmd => Try(Resource.Child, CmdErr)
	cmd_run! : Cmd => Try(CmdOutput, CmdErr)
	child_pid! : Resource.Child => U32
	child_wait! : Resource.Child => Try(CmdOutput, [Closed, CmdErr(CmdErr)])
	child_poll! : Resource.Child => Try([Running, Finished(CmdOutput)], [Closed, CmdErr(CmdErr)])
	child_kill! : Resource.Child => Try({}, [Closed, CmdErr(CmdErr)])
	child_close! : Resource.Child => Try({}, CmdErr)
	child_close_stdin! : Resource.Child => Try({}, [Closed, CmdErr(CmdErr)])
	# The waits are in nanoseconds; zero makes one attempt that does not wait.
	child_write! : Resource.Child, List(U8), U64 => Try({}, [Closed, CmdErr(CmdErr)])
	child_read! : Resource.Child, U64 => Try([Stdout(List(U8)), Stderr(List(U8))], [EndOfInput, Closed, CmdErr(CmdErr)])

	tcp_listen! : Str, U16, U64 => Try(Resource.TcpListener, [TcpErr(IOErr)])
	tcp_local_port! : Resource.TcpListener => Try(U16, [Closed, TcpErr(IOErr)])
	tcp_accept! : Resource.TcpListener, [NoTimeout, After(U64)] => Try(Resource.TcpConnection, [Closed, TcpErr(IOErr)])
	tcp_listener_close! : Resource.TcpListener => Try({}, [TcpErr(IOErr)])

	env_program_name! : () => Try(NativeOsStr, [ProgramNameUnavailable])

	file_read_up_to! : Resource.FileReader, U64 => Try(List(U8), [EndOfInput, FileErr(IOErr)])
	file_read_exactly! : Resource.FileReader, U64 => Try(List(U8), [FileErr(IOErr), UnexpectedEndOfInput])
	file_reader_position! : Resource.FileReader => Try(U64, [FileErr(IOErr)])
	file_reader_seek! : Resource.FileReader, [Start(U64), Current(I64), End(I64)] => Try(U64, [FileErr(IOErr)])

	file_open_writer! : NativePath, [Truncate, Append, RequireNew] => Try(Resource.FileWriter, [FileErr(IOErr)])
	file_writer_write_bytes! : Resource.FileWriter, List(U8) => Try({}, [FileErr(IOErr)])
	file_writer_write_utf8! : Resource.FileWriter, Str => Try({}, [FileErr(IOErr)])
	file_writer_flush! : Resource.FileWriter => Try({}, [FileErr(IOErr)])

	# `http_send_streaming!` returns once the status and headers have arrived;
	# the second argument is the idle timeout in nanoseconds. `http_read_body!`
	# reads from the one cursor the response's streams share: `Chunk` is the
	# next non-empty chunk of at most 64 KiB, `ToEnd(max)` is everything unread,
	# or `ReadLimitExceeded` once more than `max` bytes of it have arrived.
	http_send_streaming! : InternalHttp.RequestToAndFromHost, [NoTimeout, After(U64)] => Try(InternalHttp.StreamingResponseFromHost, InternalHttp.TransportErr)
	http_read_body! : Resource.HttpResponse, [Chunk, ToEnd(U64)] => Try(List(U8), [EndOfBody, ReadLimitExceeded, HttpErr(InternalHttp.TransportErr)])
}
