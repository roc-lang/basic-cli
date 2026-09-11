import Host
import IOErr exposing [IOErr]
import OsStr exposing [OsStr]
import Path

## Read and modify the process environment without losing native OS strings.
##
## Variable names and values use [`OsStr`](OsStr) because Unix environment data
## is not required to be UTF-8. Use [`var_str!`](#var_str!) when an application
## specifically requires text. Paths use basic-cli's byte-preserving `Path` type.
##
## ```roc
## path_value = Env.var_str!("PATH")?
## Stdout.line!("PATH: ${path_value}")?
## ```
Env :: [].{

	## Report the architecture and operating system for which the host was built.
	platform! : () => {
		arch : [X86, X64, ARM, AARCH64, OTHER(Str)],
		os : [LINUX, MACOS, WINDOWS, OTHER(Str)],
	}
	platform! = || Host.env_platform!()

	## Return all environment variables as native name/value pairs.
	##
	## Native non-Unicode values are preserved. Iteration order is unspecified
	## and may differ between calls or operating systems.
	dict! : () => List((OsStr, OsStr))
	dict! = ||
		List.map(Host.env_dict!(), |(name, value)| (OsStr.from_raw(name), OsStr.from_raw(value)))

	## Reads the given environment variable.
	##
	## Returns `Err(VarNotFound(name))` if the variable is not set.
	var! : OsStr => Try(OsStr, [VarNotFound(OsStr), EnvErr(IOErr), ..])
	var! = |name|
		match Host.env_var!(OsStr.to_raw(name)) {
			Ok(raw) => Ok(OsStr.from_raw(raw))
			Err(VarNotFound(raw_name)) => Err(VarNotFound(OsStr.from_raw(raw_name)))
			Err(EnvErr(err)) => Err(EnvErr(err))
		}

	## Reads the given environment variable as a string if its native value is valid text.
	var_str! : OsStr => Try(Str, [VarNotFound(OsStr), EnvErr(IOErr), InvalidStr(U64), ..])
	var_str! = |name|
		match var!(name) {
			Ok(value) =>
				match OsStr.to_str_try(value) {
					Ok(str) => Ok(str)
					Err(InvalidStr(index)) => Err(InvalidStr(index))
				}
			Err(VarNotFound(raw_name)) => Err(VarNotFound(raw_name))
			Err(EnvErr(err)) => Err(EnvErr(err))
		}

	## Reads the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
	## from the environment.
	##
	## Returns `Err(CwdUnavailable)` if the cwd cannot be determined.
	cwd! : () => Try(Path.Path, [CwdUnavailable, ..])
	cwd! = ||
		match Host.env_cwd!() {
			Ok(raw) => Ok(Path.from_raw(raw))
			Err(CwdUnavailable) => Err(CwdUnavailable)
		}

	## Change the process current working directory.
	##
	## Returns `Err(InvalidCwd(err))` when the path cannot be used as a working
	## directory. The process-wide change remains in effect until changed again.
	set_cwd! : Path.Path => Try({}, [InvalidCwd(IOErr), ..])
	set_cwd! = |path|
		Host.env_set_cwd!(Path.to_raw(path))
			.map_err(|err| InvalidCwd(err))

	## Gets the path to the currently-running executable.
	##
	## Returns `Err(ExePathUnavailable)` if the path cannot be determined.
	exe_path! : () => Try(Path.Path, [ExePathUnavailable, ..])
	exe_path! = ||
		match Host.env_exe_path!() {
			Ok(raw) => Ok(Path.from_raw(raw))
			Err(ExePathUnavailable) => Err(ExePathUnavailable)
		}

	## Gets the program name supplied by the process launcher as its first argument.
	##
	## This is conventionally the executable name or path, but launchers may supply
	## another value. Unlike [`exe_path!`](#exe_path!), it is returned as an
	## [`OsStr`](OsStr), preserving the value exactly without treating it as a path.
	## Returns `Err(ProgramNameUnavailable)` if the launcher supplied no first argument.
	program_name! : () => Try(OsStr, [ProgramNameUnavailable, ..])
	program_name! = ||
		match Host.env_program_name!() {
			Ok(raw) => Ok(OsStr.from_raw(raw))
			Err(ProgramNameUnavailable) => Err(ProgramNameUnavailable)
		}

	## Atomically create a private directory in the system temporary directory.
	## The caller owns cleanup. Unix directories have mode 0700.
	create_temp_dir! : () => Try(Path.Path, [TempDirErr(IOErr), ..])
	create_temp_dir! = || create_temp_dir_with_prefix!("roc-")

	## Create a private temporary directory with a filename prefix.
	create_temp_dir_with_prefix! : Str => Try(Path.Path, [TempDirErr(IOErr), ..])
	create_temp_dir_with_prefix! = |prefix| create_temp_dir_in!(temp_dir!(), prefix)

	## Create a private temporary directory under an existing parent directory.
	## Prefixes cannot contain separators, colons, NUL, or be `.` or `..`.
	create_temp_dir_in! : Path.Path, Str => Try(Path.Path, [TempDirErr(IOErr), ..])
	create_temp_dir_in! = |parent, prefix|
		Host.env_create_temp_dir!(Path.to_raw(parent), prefix).map_ok(Path.from_raw).map_err(|err| TempDirErr(err))

	## Run a callback with a private directory and delete the directory afterward.
	## Cleanup is attempted after callback success and failure. If both fail, both errors are returned.
	##
	## ```roc
	## Env.with_temp_dir!(|directory| {
	## 	file = Path.join(directory, "result.txt")
	## 	Path.write_utf8!(file, "temporary data")?
	## 	Path.read_utf8!(file)
	## })?
	## ```
	with_temp_dir! : (Path.Path => Try(a, err)) => Try(a, [TempDirErr(IOErr), CallbackErr(err), CleanupErr(IOErr, Path.Path), CallbackAndCleanupErr(err, IOErr, Path.Path), ..])
	with_temp_dir! = |callback!| {
		path = create_temp_dir!()?
		result = callback!(path)
		cleanup = Path.delete_all!(path)
		match (result, cleanup) {
			(Ok(value), Ok(_)) => Ok(value)
			(Err(err), Ok(_)) => Err(CallbackErr(err))
			(Ok(_), Err(PathErr(err, failed_path))) => Err(CleanupErr(err, failed_path))
			(Err(callback_err), Err(PathErr(err, failed_path))) => Err(CallbackAndCleanupErr(callback_err, err, failed_path))
		}
	}

	## Gets the default directory for temporary files.
	temp_dir! : () => Path.Path
	temp_dir! = || Path.from_raw(Host.env_temp_dir!())
}
