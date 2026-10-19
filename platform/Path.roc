import IOErr
import Host
import InternalUtf16
import OsStr
import Utc

path_type_from_host : Host.PathType -> [IsFile, IsDir, IsSymLink, IsOther]
path_type_from_host = |path_type|
	match path_type {
		File => IsFile
		Dir => IsDir
		SymLink => IsSymLink
		Other => IsOther
	}

## Construct and operate on byte-preserving paths. Native Unix
## bytes and Windows UTF-16 units are preserved across host effects; use
## `display` only when a lossy human-readable representation is appropriate.
##
## Quoted literals create UTF-8 paths, and `join` appends one path component:
##
## ```roc
## Path.create_all!("config")?
## config_file = Path.join("config", "app.json")
## Path.write_utf8!(config_file, "{}")?
## ```
Path := [
	Utf8(Str),
	UnixBytes(List(U8)),
	WindowsU16s(List(U16)),
].{

	## Create a path from an OS string value, preserving raw OS units.
	from_os_str : OsStr -> Path
	from_os_str = |os_str| from_raw(OsStr.to_raw(os_str))

	## Convert a path to an OS string value, preserving raw OS units.
	to_os_str : Path -> OsStr
	to_os_str = |path| OsStr.from_raw(to_raw(path))

	## Returns `True` if the path exists on disk and is pointing at a regular file.
	##
	## This function does not traverse symbolic links; symbolic links (including
	## broken ones) return `False`.
	## Sockets, FIFOs, devices, and other special filesystem objects also return `False`.
	is_file! : Path => Try(Bool, [PathErr(IOErr, Path)])
	is_file! = |path|
		match type!(path) {
			Ok(IsFile) => Ok(True)
			Ok(_) => Ok(False)
			Err(PathErr(NotFound, _)) => Ok(False)
			Err(err) => Err(err)
		}

	## Returns `True` if the path exists on disk and is pointing at a directory.
	##
	## This function does not traverse symbolic links; symbolic links (including
	## broken ones) return `False`.
	## Sockets, FIFOs, devices, and other special filesystem objects also return `False`.
	is_dir! : Path => Try(Bool, [PathErr(IOErr, Path)])
	is_dir! = |path|
		match type!(path) {
			Ok(IsDir) => Ok(True)
			Ok(_) => Ok(False)
			Err(PathErr(NotFound, _)) => Ok(False)
			Err(err) => Err(err)
		}

	## Returns `True` if the path exists on disk and is pointing at a symbolic link.
	##
	## This function will not traverse symbolic links - it checks whether the path
	## itself is a symlink.
	## Sockets, FIFOs, devices, and other special filesystem objects return `False`.
	is_sym_link! : Path => Try(Bool, [PathErr(IOErr, Path)])
	is_sym_link! = |path|
		match type!(path) {
			Ok(IsSymLink) => Ok(True)
			Ok(_) => Ok(False)
			Err(PathErr(NotFound, _)) => Ok(False)
			Err(err) => Err(err)
		}

	## Returns `True` if the path exists on disk.
	exists! : Path => Try(Bool, [PathErr(IOErr, Path)])
	exists! = |path|
		match type!(path) {
			Ok(_) => Ok(True)
			Err(PathErr(NotFound, _)) => Ok(False)
			Err(err) => Err(err)
		}

	## Return the type of the path if the path exists on disk.
	##
	## `IsOther` represents sockets, FIFOs, block and character devices, and any
	## platform-specific object that is not a regular file, directory, or symbolic
	## link. On Windows this includes unrecognized reparse-point types.
	type! : Path => Try([IsFile, IsDir, IsSymLink, IsOther], [PathErr(IOErr, Path)])
	type! = |path| {
		Host.path_type!(to_raw(path))
			.map_err(|err| PathErr(err, path))
			.map_ok(path_type_from_host)
	}

	## Make a path absolute without requiring it to exist. This does not resolve symlinks.
	absolute! : Path => Try(Path, [PathErr(IOErr, Path)])
	absolute! = |path| Host.path_absolute!(to_raw(path)).map_ok(from_raw).map_err(|err| PathErr(err, path))

	## Resolve an existing path, including symbolic links, to its absolute native path.
	canonicalize! : Path => Try(Path, [PathErr(IOErr, Path)])
	canonicalize! = |path| Host.path_canonicalize!(to_raw(path)).map_ok(from_raw).map_err(|err| PathErr(err, path))

	## Replace discretionary access grants on a regular-file target, preserving
	## ownership and contents. Symbolic links are followed. OwnerOnly grants
	## owner read/write; PublicRead additionally grants everyone read. Neither
	## grants execute. Existing handles and privileged OS access are unaffected.
	## On macOS the target must currently be readable to open a handle for
	## replacing its ACL. On Linux repairing an unreadable file requires
	## /proc/self/fd.
	set_permissions! : Path, [OwnerOnly, PublicRead] => Try({}, [PathErr(IOErr, Path)])
	set_permissions! = |path, permissions|
		Host.path_set_permissions!(to_raw(path), permissions).map_err(|err| PathErr(err, path))

	## Create a new symbolic link. A relative target is stored unchanged and
	## resolves from the link's parent directory. The declared target kind must
	## match the eventual target; dangling targets are allowed. Windows requires
	## Developer Mode or permission to create symbolic links.
	symlink! : Path, Path, [File, Directory] => Try({}, [PathErr(IOErr, Path)])
	symlink! = |target, link, kind|
		Host.path_symlink!(to_raw(target), to_raw(link), kind).map_err(|err| PathErr(err, link))

	## Read the stored target without resolving it or converting native units.
	read_link! : Path => Try(Path, [PathErr(IOErr, Path)])
	read_link! = |path|
		Host.path_read_link!(to_raw(path)).map_ok(from_raw).map_err(|err| PathErr(err, path))

	## Copy a regular file and its permissions, replacing the destination file.
	## Rejects same-file copies (including hard-link aliases) and special files.
	copy! : Path, Path => Try({}, [CopyErr({ operation : Str, source : Path, destination : Path, error : IOErr })])
	copy! = |source, destination|
		Host.path_copy!(to_raw(source), to_raw(destination)).map_err(copy_error)

	## Copy a directory tree into a new destination, following symbolic links.
	## Missing destination parent directories are created.
	## Permissions are preserved; timestamps, ownership, ACLs and other metadata are not.
	## Errors may leave a partial destination. Cycles and overlapping source/destination trees are rejected.
	copy_dir! : Path, Path => Try({}, [CopyErr({ operation : Str, source : Path, destination : Path, error : IOErr })])
	copy_dir! = |source, destination| copy_dir_with!(source, destination, { symlinks: Follow, destination: RequireNew })

	## Choose whether to preserve links and whether to merge an existing destination tree.
	## Merge replaces regular files. Existing destination directory symlinks are rejected.
	copy_dir_with! : Path, Path, { symlinks : [Follow, Preserve], destination : [RequireNew, Merge] } => Try({}, [CopyErr({ operation : Str, source : Path, destination : Path, error : IOErr })])
	copy_dir_with! = |source, destination, options|
		Host.path_copy_dir!(to_raw(source), to_raw(destination), options).map_err(copy_error)

	## Read all bytes from a file at this path.
	read_bytes! : Path => Try(List(U8), [PathErr(IOErr, Path)])
	read_bytes! = |path| map_file_result(Host.file_read_bytes!(to_raw(path)), path)

	## Write bytes to a file at this path, replacing any existing contents.
	write_bytes! : Path, List(U8) => Try({}, [PathErr(IOErr, Path)])
	write_bytes! = |path, bytes| map_file_result(Host.file_write_bytes!(to_raw(path), bytes), path)

	## Read a UTF-8 file at this path.
	read_utf8! : Path => Try(Str, [PathErr(IOErr, Path)])
	read_utf8! = |path| map_file_result(Host.file_read_utf8!(to_raw(path)), path)

	## Write a UTF-8 file at this path, replacing any existing contents.
	write_utf8! : Path, Str => Try({}, [PathErr(IOErr, Path)])
	write_utf8! = |path, content| map_file_result(Host.file_write_utf8!(to_raw(path), content), path)

	## Append bytes to the end of the file at this path, creating the file if it
	## does not exist. Missing parent directories are not created.
	##
	## Existing contents are never truncated or overwritten: the file is opened in
	## append mode, so the operating system places the bytes at the current end of
	## the file even when other writers are appending to it. The bytes are handed
	## to the operating system in one write, which keeps appends from concurrent
	## writers from interleaving in the common case, but this is not guaranteed for
	## large contents or on network filesystems.
	##
	## The append is not atomic or durable: a failure mid-write can leave part of
	## the bytes appended, and nothing is flushed to the storage device before
	## this returns.
	append_bytes! : Path, List(U8) => Try({}, [PathErr(IOErr, Path)])
	append_bytes! = |path, bytes| map_file_result(Host.file_append_bytes!(to_raw(path), bytes), path)

	## Append UTF-8 text to the end of the file at this path, creating the file if
	## it does not exist. No newline is added.
	##
	## ```roc
	## Path.append_utf8!("events.log", "started\n")?
	## ```
	##
	## This has the same creation, concurrency and failure behavior as
	## [append_bytes!].
	append_utf8! : Path, Str => Try({}, [PathErr(IOErr, Path)])
	append_utf8! = |path, content| map_file_result(Host.file_append_utf8!(to_raw(path), content), path)

	## Replace every occurrence of `pattern` with `replacement` in the UTF-8 file
	## at this path.
	##
	## This reads the whole file, substitutes, and writes it back, so it is not
	## atomic: a failure mid-write can leave the file partially written, exactly
	## as a bare [write_utf8!] would.
	replace_utf8! : Path, Str, Str => Try({}, [PathErr(IOErr, Path)])
	replace_utf8! = |path, pattern, replacement| {
		content = read_utf8!(path)?
		write_utf8!(path, Str.replace_each(content, pattern, replacement))
	}

	## Delete a file at this path.
	delete! : Path => Try({}, [PathErr(IOErr, Path)])
	delete! = |path| map_file_result(Host.file_delete!(to_raw(path)), path)

	## Return the size of the file at this path in bytes.
	size_in_bytes! : Path => Try(U64, [PathErr(IOErr, Path)])
	size_in_bytes! = |path| map_file_result(Host.file_size_in_bytes!(to_raw(path)), path)

	## Check whether the file at this path has any executable bit set.
	is_executable! : Path => Try(Bool, [PathErr(IOErr, Path)])
	is_executable! = |path| map_file_result(Host.file_is_executable!(to_raw(path)), path)

	## Check whether the file at this path has a readable owner permission bit set.
	is_readable! : Path => Try(Bool, [PathErr(IOErr, Path)])
	is_readable! = |path| map_file_result(Host.file_is_readable!(to_raw(path)), path)

	## Check whether the file at this path has a writable owner permission bit set.
	is_writable! : Path => Try(Bool, [PathErr(IOErr, Path)])
	is_writable! = |path| map_file_result(Host.file_is_writable!(to_raw(path)), path)

	## Return when the file at this path was last accessed.
	##
	## Times before 1970 are returned as negative instants, not errors.
	time_accessed! : Path => Try(Utc, [PathErr(IOErr, Path)])
	time_accessed! = |path|
		map_file_result(Host.file_time_accessed!(to_raw(path)), path).map_ok(Utc.from_nanos_since_epoch)

	## Return when the file at this path was last modified.
	##
	## Times before 1970 are returned as negative instants, not errors.
	##
	## ```roc
	## stale = Utc.now!().since(path.time_modified!()?) > Duration.minutes(5)
	## ```
	time_modified! : Path => Try(Utc, [PathErr(IOErr, Path)])
	time_modified! = |path|
		map_file_result(Host.file_time_modified!(to_raw(path)), path).map_ok(Utc.from_nanos_since_epoch)

	## Return when the file at this path was created.
	##
	## Times before 1970 are returned as negative instants, not errors. Fails
	## with `Unsupported` where the filesystem does not record a creation time.
	time_created! : Path => Try(Utc, [PathErr(IOErr, Path)])
	time_created! = |path|
		map_file_result(Host.file_time_created!(to_raw(path)), path).map_ok(Utc.from_nanos_since_epoch)

	## Create a hard link at `link` pointing to `original`.
	##
	## Errors report `original`, which is what a missing-file failure refers to.
	## Some failures concern `link` instead, such as `AlreadyExists`.
	hard_link! : Path, Path => Try({}, [PathErr(IOErr, Path)])
	hard_link! = |original, link|
		map_file_result(Host.file_hard_link!(to_raw(original), to_raw(link)), original)

	## Rename a file from `from` to `to`.
	##
	## Errors report `from`; a failure may still concern `to`, such as its
	## parent directory not existing.
	rename! : Path, Path => Try({}, [PathErr(IOErr, Path)])
	rename! = |from, to|
		map_file_result(Host.file_rename!(to_raw(from), to_raw(to)), from)

	## Create a directory at this path.
	create_dir! : Path => Try({}, [PathErr(IOErr, Path)])
	create_dir! = |path| map_dir_result(Host.dir_create!(to_raw(path)), path)

	## Create a directory and any missing parent directories at this path.
	create_all! : Path => Try({}, [PathErr(IOErr, Path)])
	create_all! = |path| map_dir_result(Host.dir_create_all!(to_raw(path)), path)

	## Delete an empty directory at this path.
	delete_empty! : Path => Try({}, [PathErr(IOErr, Path)])
	delete_empty! = |path| map_dir_result(Host.dir_delete_empty!(to_raw(path)), path)

	## Delete a directory and all contents at this path.
	delete_all! : Path => Try({}, [PathErr(IOErr, Path)])
	delete_all! = |path| map_dir_result(Host.dir_delete_all!(to_raw(path)), path)

	## List the entries in the directory at this path.
	##
	## The result is all-or-nothing: if any entry cannot be read while the
	## directory is being listed, an error is returned instead of a partial list.
	list! : Path => Try(List(Path), [PathErr(IOErr, Path)])
	list! = |path|
		match Host.dir_list!(to_raw(path)) {
			Ok(paths) => Ok(paths.map(from_raw))
			Err(DirErr(err)) => Err(PathErr(err, path))
		}

	## Create a UTF-8 path from a dynamic `Str`. String literals can be used
	## directly wherever a `Path` is expected.
	utf8 : Str -> Path
	utf8 = |str| Utf8(str)

	## Create a UTF-8 text path from a quoted literal.
	from_quote : Str -> Try(Path, [BadQuotedBytes(Str)])
	from_quote = |str| Ok(Utf8(str))

	## Create a UTF-8 path from an interpolated string literal.
	## This performs textual concatenation; use [join] for path-component joining.
	from_interpolation : List(Str) -> Try((List(Str) -> Path), [InvalidInterpolation(Str)])
	from_interpolation = |segments|
		Str.from_interpolation(segments).map_ok(|assemble| |values| Utf8(assemble(values)))

	## Parse and encode every path representation as a lossless tagged value.
	parser_for : _
	encoder_for : _

	## Create a Unix path from a Roc string by storing its UTF-8 bytes.
	unix : Str -> Path
	unix = |str| UnixBytes(Str.to_utf8(str))

	## Create a Unix path from raw bytes without validating UTF-8.
	unix_bytes : List(U8) -> Path
	unix_bytes = |bytes| UnixBytes(bytes)

	## Create a Windows path from a Roc string by storing its UTF-16 code units.
	windows : Str -> Path
	windows = |str| WindowsU16s(InternalUtf16.from_str(str))

	## Create a Windows path from raw UTF-16 code units.
	windows_u16s : List(U16) -> Path
	windows_u16s = |list| WindowsU16s(list)

	## Convert a path to a string if its raw representation is valid text.
	to_str : Path -> Try(Str, [InvalidStr(U64)])
	to_str = |path|
		match path {
			Utf8(str) => Ok(str)

			UnixBytes(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Ok(str)
					Err(BadUtf8({ index, problem: _ })) => Err(InvalidStr(index))
				}

			WindowsU16s(u16s) => InternalUtf16.to_str(u16s)
		}

	## Convert a path to a best-effort display string, replacing invalid text with
	## U+FFFD. This representation is lossy and must not be used for roundtripping.
	display : Path -> Str
	display = |path|
		match path {
			Utf8(str) => str
			UnixBytes(bytes) => Str.from_utf8_lossy(bytes)
			WindowsU16s(u16s) => Str.from_utf8_lossy(InternalUtf16.to_utf8_lossy(u16s))
		}

	## Render a path for debugging without losing raw OS units.
	to_inspect : Path -> Str
	to_inspect = |path|
		match path {
			Utf8(str) => "Path.utf8(${Json.to_str(str)})"
			UnixBytes(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => "Path.unix(${Json.to_str(str)})"
					Err(_) => "Path.unix_bytes(${Str.inspect(bytes)})"
				}
			WindowsU16s(u16s) =>
				match InternalUtf16.to_str(u16s) {
					Ok(str) => "Path.windows(${Json.to_str(str)})"
					Err(_) => "Path.windows_u16s(${Str.inspect(u16s)})"
				}
		}

	## Compare paths by content, whichever representation holds it.
	##
	## A string literal is stored as UTF-8, while the operating system hands
	## back native units, so `Path.list!("src")?.contains("src/main.roc")`
	## compares text with native units. The rules are those of
	## [`OsStr.is_eq`](OsStr#is_eq): valid Unicode is equal when it is the same
	## text, and invalid native units equal only identical units of the same kind.
	##
	## Paths are not normalized. `a/b` and `a\b`, `./a` and `a`, and names that
	## differ in case or Unicode normal form are all unequal, even where the
	## file system would treat them as one file.
	is_eq : Path, Path -> Bool
	is_eq = |left, right| to_os_str(left) == to_os_str(right)

	## Hash paths consistently with [is_eq].
	to_hash : Path, Hasher -> Hasher
	to_hash = |path, hasher| to_os_str(path).to_hash(hasher)

	## Returns everything after the last directory separator.
	filename : Path -> Try(Path, [IsDirPath, EndsInDots])
	filename = |path|
		match path {
			Utf8(str) => {
				bytes = Str.to_utf8(str)

				if ends_with_u8(bytes, '/') {
					Err(IsDirPath)
				} else if ends_with_two_u8(bytes, '.', '.') {
					Err(EndsInDots)
				} else {
					match List.find_last_index(bytes, |byte| byte == '/') {
						Ok(last_sep_index) => Ok(Utf8(str_from_valid_utf8(after_index_u8(bytes, last_sep_index))))
						Err(NotFound) => Ok(path)
					}
				}
			}

			UnixBytes(bytes) =>
				if ends_with_u8(bytes, '/') {
					Err(IsDirPath)
				} else if ends_with_two_u8(bytes, '.', '.') {
					Err(EndsInDots)
				} else {
					match List.find_last_index(bytes, |byte| byte == '/') {
						Ok(last_sep_index) => Ok(UnixBytes(after_index_u8(bytes, last_sep_index)))
						Err(NotFound) => Ok(path)
					}
				}

			WindowsU16s(u16s) =>
				if ends_with_u16(u16s, '/') or ends_with_u16(u16s, '\\') {
					Err(IsDirPath)
				} else if ends_with_two_u16(u16s, '.', '.') {
					Err(EndsInDots)
				} else {
					match List.find_last_index(u16s, |u16| u16 == '/' or u16 == '\\') {
						Ok(last_sep_index) => Ok(WindowsU16s(after_index_u16(u16s, last_sep_index)))
						Err(NotFound) => Ok(path)
					}
				}
		}

	## Returns everything after the first dot in the filename that is not a
	## leading dot: `txt` for `notes.txt`, `tar.gz` for `archive.tar.gz`, and
	## nothing for `.gitignore`.
	ext : Path -> Try(Path, [IsDirPath, EndsInDots])
	ext = |path|
		match filename(path) {
			Err(err) => Err(err)
			Ok(Utf8(str)) => Ok(Utf8(str_from_valid_utf8(ext_units_u8(Str.to_utf8(str)))))
			Ok(UnixBytes(bytes)) => Ok(UnixBytes(ext_units_u8(bytes)))
			Ok(WindowsU16s(u16s)) => Ok(WindowsU16s(ext_units_u16(u16s)))
		}

	## Adds a separator and a string component to the path.
	join : Path, Str -> Path
	join = |path, str|
		match path {
			Utf8(path_str) => Utf8(path_str.concat("/").concat(str))
			UnixBytes(bytes) => UnixBytes(bytes.append('/').concat(Str.to_utf8(str)))
			WindowsU16s(u16s) => WindowsU16s(u16s.append('\\').concat(InternalUtf16.from_str(str)))
		}

	## Expose the raw OS-specific representation.
	to_raw : Path -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	to_raw = |path|
		match path {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => UnixBytes(bytes)
			WindowsU16s(u16s) => WindowsU16s(u16s)
		}

	## Build a path from the raw OS-specific representation.
	from_raw : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))] -> Path
	from_raw = |raw|
		match raw {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => UnixBytes(bytes)
			WindowsU16s(u16s) => WindowsU16s(u16s)
		}
}

map_file_result : Try(a, [FileErr(IOErr)]), Path -> Try(a, [PathErr(IOErr, Path)])
map_file_result = |result, path|
	match result {
		Ok(value) => Ok(value)
		Err(FileErr(err)) => Err(PathErr(err, path))
	}

map_dir_result : Try(a, [DirErr(IOErr)]), Path -> Try(a, [PathErr(IOErr, Path)])
map_dir_result = |result, path|
	match result {
		Ok(value) => Ok(value)
		Err(DirErr(err)) => Err(PathErr(err, path))
	}

str_from_valid_utf8 : List(U8) -> Str
str_from_valid_utf8 = |bytes|
	match Str.from_utf8(bytes) {
		Ok(str) => str
		Err(_) => {
			crash "A valid UTF-8 path contained invalid UTF-8 after ASCII path slicing."
		}
	}

ends_with_u8 : List(U8), U8 -> Bool
ends_with_u8 = |list, suffix|
	match list {
		[.., last] => last == suffix
		[] => False
	}

ends_with_u16 : List(U16), U16 -> Bool
ends_with_u16 = |list, suffix|
	match list {
		[.., last] => last == suffix
		[] => False
	}

ends_with_two_u8 : List(U8), U8, U8 -> Bool
ends_with_two_u8 = |list, first_suffix, second_suffix|
	match list {
		[.., first, second] => first == first_suffix and second == second_suffix
		_ => False
	}

ends_with_two_u16 : List(U16), U16, U16 -> Bool
ends_with_two_u16 = |list, first_suffix, second_suffix|
	match list {
		[.., first, second] => first == first_suffix and second == second_suffix
		_ => False
	}

after_index_u8 : List(U8), U64 -> List(U8)
after_index_u8 = |list, index| {
	start = index + 1
	List.sublist(list, { start, len: List.len(list) - start })
}

after_index_u16 : List(U16), U64 -> List(U16)
after_index_u16 = |list, index| {
	start = index + 1
	List.sublist(list, { start, len: List.len(list) - start })
}

ext_units_u8 : List(U8) -> List(U8)
ext_units_u8 = |units|
	match List.find_first_index(units, |unit| unit == '.') {
		Err(NotFound) => []
		Ok(0) => {
			rest = List.drop_first(units, 1)

			match List.find_first_index(rest, |unit| unit == '.') {
				Err(NotFound) => []
				Ok(dot_index) => after_index_u8(rest, dot_index)
			}
		}
		Ok(dot_index) => after_index_u8(units, dot_index)
	}

ext_units_u16 : List(U16) -> List(U16)
ext_units_u16 = |units|
	match List.find_first_index(units, |unit| unit == '.') {
		Err(NotFound) => []
		Ok(0) => {
			rest = List.drop_first(units, 1)

			match List.find_first_index(rest, |unit| unit == '.') {
				Err(NotFound) => []
				Ok(dot_index) => after_index_u16(rest, dot_index)
			}
		}
		Ok(dot_index) => after_index_u16(units, dot_index)
	}

quoted_literal_path : Path
quoted_literal_path = "config.txt"

path_identity : Path -> Path
path_identity = |path| path

## Constructors preserve Unix, Windows, and UTF-8 path representations.
expect Path.to_raw(Path.unix("abc")) == UnixBytes([97, 98, 99])
expect Path.to_raw(Path.unix_bytes([97, 98, 99])) == UnixBytes([97, 98, 99])
expect Path.to_raw(Path.windows("abc")) == WindowsU16s([97, 98, 99])
expect Path.to_raw(Path.windows_u16s([97, 98, 99])) == WindowsU16s([97, 98, 99])
expect Path.to_raw(Path.utf8("abc")) == Utf8("abc")

## Quoted literals dispatch to UTF-8 paths through `from_quote`.
expect Path.from_quote("config.txt").map_ok(Path.to_raw) == Ok(Utf8("config.txt"))
expect Path.to_raw(quoted_literal_path) == Utf8("config.txt")
expect Path.to_raw(path_identity("nested/config.txt")) == Utf8("nested/config.txt")

## Interpolation creates a UTF-8 representation.
expect {
	directory = "config"
	path : Path
	path = "${directory}/app.toml"
	Path.to_raw(path) == Utf8("config/app.toml")
}

## Raw conversion roundtrips every representation without validating raw OS data.
expect Path.to_raw(Path.unix_bytes([97, 255, 98])) == UnixBytes([97, 255, 98])
expect Path.to_raw(Path.windows_u16s([0xD800, 97])) == WindowsU16s([0xD800, 97])
expect Path.to_raw(Path.utf8("abc")) == Utf8("abc")
expect Path.to_raw(Path.from_raw(UnixBytes([97, 255, 98]))) == UnixBytes([97, 255, 98])
expect Path.to_raw(Path.from_raw(WindowsU16s([97, 98, 99]))) == WindowsU16s([97, 98, 99])
expect Path.to_raw(Path.from_raw(Utf8("abc"))) == Utf8("abc")

## `to_str` succeeds for valid text and reports the first invalid raw unit.
expect Path.to_str(Path.unix("abc")) == Ok("abc")
expect Path.to_str(Path.unix_bytes([97, 255, 98])) == Err(InvalidStr(1))
expect Path.to_str(Path.windows("abc")) == Ok("abc")
expect Path.to_str(Path.windows_u16s([0xD800])) == Err(InvalidStr(0))
expect Path.to_str(Path.utf8("abc")) == Ok("abc")
expect Path.to_str(Path.windows_u16s([0xD83D, 0xDC26])) == Ok(Str.from_utf8_lossy([0xF0, 0x9F, 0x90, 0xA6]))

## `display` preserves valid text and replaces invalid raw units.
expect Path.display(Path.unix("abc")) == "abc"
expect Path.display(Path.unix_bytes([97, 255, 98])) == Str.from_utf8_lossy([97, 255, 98])
expect Path.display(Path.windows("abc")) == "abc"
expect Path.display(Path.windows_u16s([0xD800, 97])) == Str.from_utf8_lossy([0xEF, 0xBF, 0xBD, 97])
expect Path.display(Path.utf8("abc")) == "abc"

## Inspection identifies the representation and preserves invalid raw units.
expect Str.inspect(Path.utf8("a\nb")) == "Path.utf8(\"a\\nb\")"
expect Str.inspect(Path.unix("abc")) == "Path.unix(\"abc\")"
expect Str.inspect(Path.unix_bytes([97, 255, 98])) == "Path.unix_bytes([97, 255, 98])"
expect Str.inspect(Path.windows("abc")) == "Path.windows(\"abc\")"
expect Str.inspect(Path.windows_u16s([0xD800, 97])) == "Path.windows_u16s([55296, 97])"

## Equality follows the content, not the representation that holds it.
expect Path.utf8("abc") == Path.unix("abc")
expect Path.unix("abc") == Path.utf8("abc")
expect Path.utf8("abc") == Path.windows("abc")
expect Path.windows("abc") == Path.utf8("abc")
expect Path.unix("abc") == Path.windows("abc")
expect Path.windows("abc") == Path.unix("abc")

## The same representation still compares its units.
expect Path.utf8("abc") == Path.utf8("abc")
expect Path.unix("abc") == Path.unix_bytes([97, 98, 99])
expect Path.windows("abc") == Path.windows_u16s([97, 98, 99])
expect Path.utf8("abc") != Path.utf8("abd")
expect Path.unix("abc") != Path.unix("abd")
expect Path.windows("abc") != Path.windows("abd")

## Different text is unequal in every pairing, including a prefix.
expect Path.utf8("abc") != Path.unix("abd")
expect Path.utf8("abc") != Path.windows("abd")
expect Path.unix("abc") != Path.windows("abd")
expect Path.utf8("abc") != Path.unix("ab")
expect Path.windows("ab") != Path.utf8("abc")
expect Path.unix("ab") != Path.windows("abc")
expect Path.utf8("") == Path.unix_bytes([])
expect Path.utf8("") == Path.windows_u16s([])
expect Path.unix_bytes([]) == Path.windows_u16s([])

## A literal equals the native value the operating system returns for that text.
expect {
	literal : Path
	literal = "--verbose"
	literal == Path.unix("--verbose") and literal == Path.windows("--verbose")
}

## Text outside ASCII compares by code point: two, three and four byte UTF-8
## sequences against one UTF-16 unit or a surrogate pair.
expect Path.utf8("é€") == Path.unix_bytes([0xC3, 0xA9, 0xE2, 0x82, 0xAC])
expect Path.utf8("é€") == Path.windows_u16s([0xE9, 0x20AC])
expect Path.unix_bytes([0xC3, 0xA9, 0xE2, 0x82, 0xAC]) == Path.windows_u16s([0xE9, 0x20AC])
expect Path.utf8("🐦") == Path.unix_bytes([0xF0, 0x9F, 0x90, 0xA6])
expect Path.utf8("🐦") == Path.windows_u16s([0xD83D, 0xDC26])
expect Path.unix_bytes([0xF0, 0x9F, 0x90, 0xA6]) == Path.windows_u16s([0xD83D, 0xDC26])
expect Path.windows_u16s([0xD83D, 0xDC26]) == Path.unix_bytes([0xF0, 0x9F, 0x90, 0xA6])
expect Path.utf8("🐦") != Path.windows_u16s([0xD83D, 0xDC27])

## Invalid UTF-8 equals only the identical bytes. It is not the text `display`
## shows for it, and not UTF-16 units with the same numbers.
expect Path.unix_bytes([97, 255]) == Path.unix_bytes([97, 255])
expect Path.unix_bytes([97, 255]) != Path.unix_bytes([97, 254])
expect Path.unix_bytes([97, 255]) != Path.utf8(Path.display(Path.unix_bytes([97, 255])))
expect Path.utf8("a") != Path.unix_bytes([97, 255])
expect Path.unix_bytes([97, 255]) != Path.windows_u16s([97, 255])
expect Path.windows_u16s([97, 255]) != Path.unix_bytes([97, 255])

## An unpaired surrogate equals only the identical units. It is not the text
## `display` shows for it, and not the bytes a lenient encoder would write.
expect Path.windows_u16s([0xD800, 97]) == Path.windows_u16s([0xD800, 97])
expect Path.windows_u16s([0xD800, 97]) != Path.windows_u16s([0xD801, 97])
expect Path.windows_u16s([0xD800, 97]) != Path.utf8(Path.display(Path.windows_u16s([0xD800, 97])))
expect Path.utf8("a") != Path.windows_u16s([0xD800, 97])
expect Path.windows_u16s([0xD800, 97]) != Path.unix_bytes([0xEF, 0xBF, 0xBD, 97])
expect Path.windows_u16s([0xD800, 97]) != Path.unix_bytes([0xED, 0xA0, 0x80, 97])
expect Path.unix_bytes([0xED, 0xA0, 0x80, 97]) != Path.windows_u16s([0xD800, 97])

## Invalid values of different kinds are never equal.
expect Path.unix_bytes([255]) != Path.windows_u16s([0xD800])
expect Path.windows_u16s([0xDC00]) != Path.unix_bytes([0xDC])

## Nothing is normalized: case, Unicode normal forms and separators differ.
expect Path.utf8("Abc") != Path.unix("abc")
expect Path.utf8("é") != Path.unix("e\u(0301)")
expect Path.utf8("a/b") != Path.windows("a\\b")
expect Path.utf8("./a") != Path.unix("a")
expect Path.utf8("a/") != Path.unix("a")

## Equality is transitive across all three representations, and unequal
## values stay unequal through a third.
expect {
	text = Path.utf8("naïve 🐦")
	bytes = Path.unix("naïve 🐦")
	units = Path.windows("naïve 🐦")
	text == bytes and bytes == units and text == units and units == text and units == bytes and bytes == text
}

expect {
	bytes = Path.unix_bytes([97, 255])
	units = Path.windows_u16s([97, 255])
	text = Path.utf8("aÿ")
	# The units are valid text; the bytes are not, so they equal neither.
	units == text and bytes != units and bytes != text
}

## Inspection still shows the representation of values that are equal.
expect Path.utf8("abc") == Path.unix("abc") and Str.inspect(Path.utf8("abc")) != Str.inspect(Path.unix("abc"))
expect Str.inspect(Path.windows("abc")) == "Path.windows(\"abc\")"

## Hashing agrees with equality, so `Dict`, `Set` and `List.contains` find a
## value through any representation.
expect Dict.single(Path.unix("HOME"), "found").get(Path.utf8("HOME")) == Ok("found")
expect Dict.single(Path.windows("HOME"), "found").get(Path.utf8("HOME")) == Ok("found")
expect Dict.single(Path.utf8("HOME"), "found").get(Path.unix("HOME")) == Ok("found")
expect Dict.single(Path.utf8("HOME"), "found").get(Path.windows("HOME")) == Ok("found")
expect Dict.single(Path.unix("HOME"), "found").get(Path.windows("HOME")) == Ok("found")
expect Dict.single(Path.windows("HOME"), "found").get(Path.unix("HOME")) == Ok("found")
expect Dict.single(Path.windows("🐦"), "found").get(Path.unix_bytes([0xF0, 0x9F, 0x90, 0xA6])) == Ok("found")
expect Dict.single(Path.unix("HOME"), "found").get(Path.utf8("home")) == Err(KeyNotFound)

expect {
	literal : Path
	literal = "HOME"
	Dict.from_list([(Path.unix("PATH"), 1), (Path.unix("HOME"), 2)]).get(literal) == Ok(2)
}

expect [Path.unix("--quiet"), Path.unix("--verbose")].contains("--verbose")
expect [Path.windows("--quiet"), Path.windows("--verbose")].contains("--verbose")
expect Bool.not([Path.unix("--quiet")].contains("--verbose"))

## Values equal across representations collapse to one `Set` or `Dict` key.
expect Set.from_list([Path.utf8("abc"), Path.unix("abc"), Path.windows("abc")]).len() == 1
expect Set.from_list([Path.utf8("abc"), Path.unix("abc"), Path.windows("abd")]).len() == 2
expect Set.from_list([Path.unix("abc")]).contains(Path.windows("abc"))
expect Dict.from_list([(Path.utf8("k"), 1), (Path.unix("k"), 2), (Path.windows("k"), 3)]).len() == 1

## Invalid native units are still usable keys, and stay apart from text and
## from each other.
expect Dict.single(Path.unix_bytes([97, 255]), "found").get(Path.unix_bytes([97, 255])) == Ok("found")
expect Dict.single(Path.windows_u16s([0xD800, 97]), "found").get(Path.windows_u16s([0xD800, 97])) == Ok("found")
expect Dict.single(Path.unix_bytes([97, 255]), "found").get(Path.windows_u16s([97, 255])) == Err(KeyNotFound)
expect Dict.single(Path.windows_u16s([0xD800, 97]), "found").get(Path.utf8(Path.display(Path.windows_u16s([0xD800, 97])))) == Err(KeyNotFound)
expect Set.from_list([Path.unix_bytes([97, 255]), Path.windows_u16s([97, 255]), Path.utf8("aÿ")]).len() == 2

## A listed entry is found by the literal naming it.
expect [Path.unix("src/lib.roc"), Path.unix("src/main.roc")].contains("src/main.roc")

## A path and the OS string it converts to hash alike, as they compare alike.
expect Path.to_os_str(Path.unix("abc")) == OsStr.utf8("abc")

## Generic codecs roundtrip non-text representations without loss.
expect {
	original = Path.windows_u16s([0xD800, 97])
	decoded : Try(Path, _)
	decoded = Json.parse(Json.to_str(original))
	decoded == Ok(original)
}

expect {
	original = Path.unix_bytes([97, 255])
	decoded : Try(Path, _)
	decoded = Json.parse(Json.to_str(original))
	decoded == Ok(original)
}

expect Json.to_str(Path.utf8("a.txt")) == Json.to_str(OsStr.utf8("a.txt"))

## `filename` returns everything after the last separator.
expect Path.filename(Path.unix("foo/bar.txt")) == Ok(Path.unix("bar.txt"))
expect Path.filename(Path.unix("foo/bar")) == Ok(Path.unix("bar"))
expect Path.filename(Path.unix("foo")) == Ok(Path.unix("foo"))
expect Path.filename(Path.unix("")) == Ok(Path.unix(""))
expect Path.filename(Path.windows("foo\\bar.txt")) == Ok(Path.windows("bar.txt"))
expect Path.filename(Path.windows("foo/bar.txt")) == Ok(Path.windows("bar.txt"))
expect Path.filename(Path.windows("foo")) == Ok(Path.windows("foo"))
expect Path.filename(Path.windows("")) == Ok(Path.windows(""))
expect Path.filename(Path.utf8("foo/bar.txt")) == Ok(Path.utf8("bar.txt"))
expect Path.filename(Path.utf8("foo")) == Ok(Path.utf8("foo"))
expect Path.filename(Path.utf8("")) == Ok(Path.utf8(""))

## `filename` rejects directory paths and filenames ending in two dots.
expect Path.filename(Path.unix("foo/bar/")) == Err(IsDirPath)
expect Path.filename(Path.unix("foo/bar..")) == Err(EndsInDots)
expect Path.filename(Path.windows("foo\\bar\\")) == Err(IsDirPath)
expect Path.filename(Path.windows("foo/bar..")) == Err(EndsInDots)
expect Path.filename(Path.utf8("foo/bar/")) == Err(IsDirPath)
expect Path.filename(Path.utf8("foo/bar..")) == Err(EndsInDots)

## `ext` returns everything after the first dot that is not a leading dot.
expect Path.ext(Path.unix("foo/bar.txt")) == Ok(Path.unix("txt"))
expect Path.ext(Path.unix("foo/bar.")) == Ok(Path.unix(""))
expect Path.ext(Path.unix("foo/.bar.txt")) == Ok(Path.unix("txt"))
expect Path.ext(Path.unix("foo/bar")) == Ok(Path.unix(""))
expect Path.ext(Path.unix("foo/.bar")) == Ok(Path.unix(""))
expect Path.ext(Path.unix("foo/bar.baz.txt")) == Ok(Path.unix("baz.txt"))
expect Path.ext(Path.unix("foo/.bar.baz.txt")) == Ok(Path.unix("baz.txt"))
expect Path.ext(Path.unix("")) == Ok(Path.unix(""))
expect Path.ext(Path.windows("foo\\bar.txt")) == Ok(Path.windows("txt"))
expect Path.ext(Path.windows("foo\\bar")) == Ok(Path.windows(""))
expect Path.ext(Path.windows("")) == Ok(Path.windows(""))
expect Path.ext(Path.utf8("foo/bar.txt")) == Ok(Path.utf8("txt"))
expect Path.ext(Path.utf8("foo/.bar")) == Ok(Path.utf8(""))
expect Path.ext(Path.utf8("foo/bar.baz.txt")) == Ok(Path.utf8("baz.txt"))
expect Path.ext(Path.utf8("")) == Ok(Path.utf8(""))

## `ext` forwards filename errors for directory paths and dot endings.
expect Path.ext(Path.unix("foo/bar/")) == Err(IsDirPath)
expect Path.ext(Path.unix("foo/bar..")) == Err(EndsInDots)
expect Path.ext(Path.windows("foo\\bar\\")) == Err(IsDirPath)
expect Path.ext(Path.windows("foo\\bar..")) == Err(EndsInDots)
expect Path.ext(Path.utf8("foo/bar/")) == Err(IsDirPath)
expect Path.ext(Path.utf8("foo/bar..")) == Err(EndsInDots)

## Host path types map exhaustively to the public API.
expect path_type_from_host(File) == IsFile

expect path_type_from_host(Dir) == IsDir

expect path_type_from_host(SymLink) == IsSymLink

expect path_type_from_host(Other) == IsOther

## `join` appends a representation-specific separator and text component.
expect Path.join(Path.unix("foo"), "bar") == Path.unix("foo/bar")
expect Path.join(Path.windows("foo"), "bar") == Path.windows("foo\\bar")
expect Path.join(Path.utf8("foo"), "bar") == Path.utf8("foo/bar")

## `filename`, `ext` and `join` answer in the representation they were given.
expect Path.filename(Path.unix("a/b.c")).map_ok(Path.to_raw) == Ok(UnixBytes([98, 46, 99]))
expect Path.filename(Path.windows("a\\b.c")).map_ok(Path.to_raw) == Ok(WindowsU16s([98, 46, 99]))
expect Path.filename(Path.utf8("a/b.c")).map_ok(Path.to_raw) == Ok(Utf8("b.c"))
expect Path.ext(Path.unix("a/b.c")).map_ok(Path.to_raw) == Ok(UnixBytes([99]))
expect Path.ext(Path.windows("a\\b.c")).map_ok(Path.to_raw) == Ok(WindowsU16s([99]))
expect Path.ext(Path.utf8("a/b.c")).map_ok(Path.to_raw) == Ok(Utf8("c"))
expect Path.to_raw(Path.join(Path.unix("a"), "b")) == UnixBytes([97, 47, 98])
expect Path.to_raw(Path.join(Path.windows("a"), "b")) == WindowsU16s([97, 92, 98])
expect Path.to_raw(Path.join(Path.utf8("a"), "b")) == Utf8("a/b")

## Errors carry the path they were about, and successes pass through untouched.
expect {
	result : Try({}, [PathErr(IOErr, Path)])
	result = map_file_result(Err(FileErr(NotFound)), Path.utf8("a.txt"))
	match result {
		Err(PathErr(NotFound, path)) => path == Path.utf8("a.txt")
		_ => False
	}
}

expect {
	result : Try({}, [PathErr(IOErr, Path)])
	result = map_dir_result(Err(DirErr(NotADirectory)), Path.unix_bytes([0x2F, 0xFF]))
	match result {
		# Raw non-UTF-8 bytes survive the trip through the error.
		Err(PathErr(NotADirectory, path)) => path == Path.unix_bytes([0x2F, 0xFF])
		_ => False
	}
}

expect {
	result : Try(U64, [PathErr(IOErr, Path)])
	result = map_file_result(Ok(42), Path.utf8("a.txt"))
	match result {
		Ok(value) => value == 42
		Err(_) => False
	}
}

copy_error : Host.CopyFailure -> [CopyErr({ operation : Str, source : Path, destination : Path, error : IOErr })]
copy_error = |failure| CopyErr({ operation: failure.operation, source: Path.from_raw(failure.source), destination: Path.from_raw(failure.destination), error: failure.error })
