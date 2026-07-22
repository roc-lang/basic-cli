## A native command-line platform with filesystem, process, network, terminal,
## SQLite, environment, random, and UTC effects.
platform ""
	requires {
		main! : List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) => Try({}, [Exit(I32), ..])
	}
	exposes [Cmd, Env, File, Http, IOErr, Locale, OsStr, Path, Random, Sleep, Sqlite, Stdin, Stdout, Stderr, Tcp, Tty, Url, Utc]
	packages {
		# HTTP data types (Method, Request, Response) come from the shared
		# roc-lang/http package so apps and other packages using it see the same
		# nominal types. The platform supplies only the effectful `Http.send!`.
		http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	}
	provides { "roc_main": main_for_host! }
	hosted {
		"hosted_cmd_host_exec_exit_code": Host.cmd_exec_exit_code!,
		"hosted_cmd_host_exec_output": Host.cmd_exec_output!,
		"hosted_dir_create": Host.dir_create!,
		"hosted_dir_create_all": Host.dir_create_all!,
		"hosted_dir_delete_all": Host.dir_delete_all!,
		"hosted_dir_delete_empty": Host.dir_delete_empty!,
		"hosted_dir_list": Host.dir_list!,
		"hosted_env_cwd": Host.env_cwd!,
		"hosted_env_exe_path": Host.env_exe_path!,
		"hosted_env_temp_dir": Host.env_temp_dir!,
		"hosted_env_var": Host.env_var!,
		"hosted_file_delete": Host.file_delete!,
		"hosted_file_is_executable": Host.file_is_executable!,
		"hosted_file_is_readable": Host.file_is_readable!,
		"hosted_file_is_writable": Host.file_is_writable!,
		"hosted_file_read_bytes": Host.file_read_bytes!,
		"hosted_file_read_utf8": Host.file_read_utf8!,
		"hosted_file_open_reader": Host.file_open_reader!,
		"hosted_file_read_line": Host.file_read_line!,
		"hosted_file_size_in_bytes": Host.file_size_in_bytes!,
		"hosted_file_time_accessed": Host.file_time_accessed!,
		"hosted_file_time_created": Host.file_time_created!,
		"hosted_file_time_modified": Host.file_time_modified!,
		"hosted_file_write_bytes": Host.file_write_bytes!,
		"hosted_file_write_utf8": Host.file_write_utf8!,
		"hosted_locale_all": Host.locale_all!,
		"hosted_locale_get": Host.locale_get!,
		"hosted_path_type": Host.path_type!,
		"hosted_random_seed_u32": Host.random_seed_u32!,
		"hosted_random_seed_u64": Host.random_seed_u64!,
		"hosted_sleep_millis": Host.sleep_millis!,
		"hosted_stderr_line": Host.stderr_line!,
		"hosted_stderr_write": Host.stderr_write!,
		"hosted_stderr_write_bytes": Host.stderr_write_bytes!,
		"hosted_stdin_bytes": Host.stdin_bytes!,
		"hosted_stdin_line": Host.stdin_line!,
		"hosted_stdin_read_to_end": Host.stdin_read_to_end!,
		"hosted_stdout_line": Host.stdout_line!,
		"hosted_stdout_write": Host.stdout_write!,
		"hosted_stdout_write_bytes": Host.stdout_write_bytes!,
		"hosted_tty_disable_raw_mode": Host.tty_disable_raw_mode!,
		"hosted_tty_enable_raw_mode": Host.tty_enable_raw_mode!,
		"hosted_utc_now": Host.utc_now!,
		# New file hosted functions are kept at the end so adding them does not
		# renumber the generated glue types for existing modules.
		"hosted_file_hard_link": Host.file_hard_link!,
		"hosted_file_rename": Host.file_rename!,
		# SQLite hosted functions are kept at the end so adding them does not
		# renumber the generated glue types for the modules declared above.
		"hosted_sqlite_prepare": Host.sqlite_prepare!,
		"hosted_sqlite_bind": Host.sqlite_bind!,
		"hosted_sqlite_columns": Host.sqlite_columns!,
		"hosted_sqlite_column_value": Host.sqlite_column_value!,
		"hosted_sqlite_step": Host.sqlite_step!,
		"hosted_sqlite_reset": Host.sqlite_reset!,
		# TCP hosted functions are likewise kept at the end to avoid renumbering.
		"hosted_tcp_connect": Host.tcp_connect!,
		"hosted_tcp_read_up_to": Host.tcp_read_up_to!,
		"hosted_tcp_read_exactly": Host.tcp_read_exactly!,
		"hosted_tcp_read_until": Host.tcp_read_until!,
		"hosted_tcp_write": Host.tcp_write!,
		# HTTP is likewise kept at the end to avoid renumbering glue types.
		"hosted_http_send_request": Host.http_send_request!,
		# Environment additions are appended to preserve existing hosted ABI numbering.
		"hosted_env_platform": Host.env_platform!,
		"hosted_env_dict": Host.env_dict!,
		"hosted_env_set_cwd": Host.env_set_cwd!,
	}
	targets: {
		inputs_dir: "targets/",
		x64mac: { inputs: ["libhost.a", app] },
		arm64mac: { inputs: ["libhost.a", app] },
		x64win: { inputs: ["host.lib", "advapi32.lib", "bcrypt.lib", "crypt32.lib", "dbghelp.lib", "iphlpapi.lib", "kernel32.lib", "ncrypt.lib", "ntdll.lib", "ole32.lib", "secur32.lib", "shell32.lib", "user32.lib", "userenv.lib", "ws2_32.lib", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
		arm64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a"] },
	}

import Cmd
import Env
import File
import Host
import Http
import IOErr
import InternalSqlite
import Locale
import OsStr
import Path
import Random
import Sleep
import Sqlite
import Stdin
import Stdout
import Stderr
import Tcp
import Tty
import Url
import Utc

main_for_host! : List(OsStr.OsStr) => I32
main_for_host! = |args|
	match main!(args) {
		Ok({}) => 0
		Err(Exit(code)) => code
		Err(other) => {
			Stderr.line!("Program exited with error: ${Str.inspect(other)}") ?? {}
			1
		}
	}
