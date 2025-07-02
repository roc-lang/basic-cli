module [
    Path,
    IOErr,
    display,
    from_str,
    from_bytes,
    with_extension,
    is_dir!,
    is_file!,
    is_sym_link!,
    exists!,
    type!,
    write_utf8!,
    write_bytes!,
    write!,
    read_utf8!,
    read_bytes!,
    delete!,
    list_dir!,
    create_dir!,
    create_all!,
    delete_empty!,
    delete_all!,
    hard_link!,
    rename!,
]

import InternalPath
import InternalIOErr
import Host

## Represents a path to a file or directory on the filesystem.
Path : InternalPath.InternalPath

## Tag union of possible errors when reading and writing a file or directory.
##
## > This is the same as [`File.Err`](File#Err).
IOErr : InternalIOErr.IOErr

## Write data to a file.
##
## First encode a `val` using a given `fmt` which implements the ability [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
##
## For example, suppose you have a `Json.utf8` which implements
## [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
## You can use this to write [JSON](https://en.wikipedia.org/wiki/JSON)
## data to a file like this:
##
## ```
## # Writes `{"some":"json stuff"}` to the file `output.json`:
## Path.write!(
##     { some: "json stuff" },
##     Path.from_str("output.json"),
##     Json.utf8,
## )?
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [Path.write_bytes!] instead.
write! : val, Path, fmt => Result {} [FileWriteErr Path IOErr] where val implements Encoding, fmt implements EncoderFormatting
write! = |val, path, fmt|
    bytes = Encode.to_bytes(val, fmt)

    # TODO handle encoding errors here, once they exist
    write_bytes!(bytes, path)

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## Path.write_bytes!([1, 2, 3], Path.from_str("myfile.dat"))?
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [Path.write!] instead.
write_bytes! : List U8, Path => Result {} [FileWriteErr Path IOErr]
write_bytes! = |bytes, path|
    path_bytes = InternalPath.to_bytes(path)

    Host.file_write_bytes!(path_bytes, bytes)
    |> Result.map_err(|err| FileWriteErr(path, InternalIOErr.handle_err(err)))

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## Path.write_utf8!("Hello!", Path.from_str("myfile.txt"))?
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [Path.write_bytes!] instead.
write_utf8! : Str, Path => Result {} [FileWriteErr Path IOErr]
write_utf8! = |str, path|
    path_bytes = InternalPath.to_bytes(path)

    Host.file_write_utf8!(path_bytes, str)
    |> Result.map_err(|err| FileWriteErr(path, InternalIOErr.handle_err(err)))

## Note that the path may not be valid depending on the filesystem where it is used.
## For example, paths containing `:` are valid on ext4 and NTFS filesystems, but not
## on FAT ones. So if you have multiple disks on the same machine, but they have
## different filesystems, then this path could be valid on one but invalid on another!
##
## It's safest to assume paths are invalid (even syntactically) until given to an operation
## which uses them to open a file. If that operation succeeds, then the path was valid
## (at the time). Otherwise, error handling can happen for that operation rather than validating
## up front for a false sense of security (given symlinks, parts of a path being renamed, etc.).
from_str : Str -> Path
from_str = |str|
    FromStr(str)
    |> InternalPath.wrap

## Not all filesystems use Unicode paths. This function can be used to create a path which
## is not valid Unicode (like a [Str] is), but which is valid for a particular filesystem.
##
## Note that if the list contains any `0` bytes, sending this path to any file operations
## (e.g. `Path.read_bytes` or `WriteStream.open_path`) will fail.
from_bytes : List U8 -> Path
from_bytes = |bytes|
    ArbitraryBytes(bytes)
    |> InternalPath.wrap

## Unfortunately, operating system paths do not include information about which charset
## they were originally encoded with. It's most common (but not guaranteed) that they will
## have been encoded with the same charset as the operating system's curent locale (which
## typically does not change after it is set during installation of the OS), so
## this should convert a [Path] to a valid string as long as the path was created
## with the given `Charset`. (Use `Env.charset` to get the current system charset.)
##
## For a conversion to [Str] that is lossy but does not return a [Result], see
## [display].
## to_inner : Path -> [Str Str, Bytes (List U8)]
## Assumes a path is encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8),
## and converts it to a string using `Str.display`.
##
## This conversion is lossy because the path may contain invalid UTF-8 bytes. If that happens,
## any invalid bytes will be replaced with the [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
## instead of returning an error. As such, it's rarely a good idea to use the [Str] returned
## by this function for any purpose other than displaying it to a user.
##
## When you don't know for sure what a path's encoding is, UTF-8 is a popular guess because
## it's the default on UNIX and also is the encoding used in Roc strings. This platform also
## automatically runs applications under the [UTF-8 code page](https://docs.microsoft.com/en-us/windows/apps/design/globalizing/use-utf8-code-page)
## on Windows.
##
## Converting paths to strings can be an unreliable operation, because operating systems
## don't record the paths' encodings. This means it's possible for the path to have been
## encoded with a different character set than UTF-8 even if UTF-8 is the system default,
## which means when [display] converts them to a string, the string may include gibberish.
## [Here is an example.](https://unix.stackexchange.com/questions/667652/can-a-file-path-be-invalid-utf-8/667863#667863)
##
## If you happen to know the `Charset` that was used to encode the path, you can use
## `to_str_using_charset` instead of [display].
display : Path -> Str
display = |path|
    when InternalPath.unwrap(path) is
        FromStr(str) -> str
        FromOperatingSystem(bytes) | ArbitraryBytes(bytes) ->
            when Str.from_utf8(bytes) is
                Ok(str) -> str
                # TODO: this should use the builtin Str.display to display invalid UTF-8 chars in just the right spots, but that does not exist yet!
                Err(_) -> "�"

## Returns true if the path exists on disk and is pointing at a directory.
## Returns `Ok false` if the path exists and it is not a directory. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_dir](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_dir).
##
## > [`File.is_dir`](File#is_dir!) does the same thing, except it takes a [Str] instead of a [Path].
is_dir! : Path => Result Bool [PathErr IOErr]
is_dir! = |path|
    res = type!(path)?
    Ok((res == IsDir))

## Returns true if the path exists on disk and is pointing at a regular file.
## Returns `Ok false` if the path exists and it is not a file. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_file](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_file).
##
## > [`File.is_file`](File#is_file!) does the same thing, except it takes a [Str] instead of a [Path].
is_file! : Path => Result Bool [PathErr IOErr]
is_file! = |path|
    res = type!(path)?
    Ok((res == IsFile))

## Returns true if the path exists on disk and is pointing at a symbolic link.
## Returns `Ok false` if the path exists and it is not a symbolic link. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [`File.is_sym_link`](File#is_sym_link!) does the same thing, except it takes a [Str] instead of a [Path].
is_sym_link! : Path => Result Bool [PathErr IOErr]
is_sym_link! = |path|
    res = type!(path)?
    Ok((res == IsSymLink))

## Returns true if the path exists on disk.
##
## This uses [rust's std::path::try_exists](https://doc.rust-lang.org/std/path/struct.Path.html#method.try_exists).
##
## > [`File.exists!`](File#exists!) does the same thing, except it takes a [Str] instead of a [Path].
exists! : Path => Result Bool [PathErr IOErr]
exists! = |path|
    Host.file_exists!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Return the type of the path if the path exists on disk.
##
## > [`File.type`](File#type!) does the same thing, except it takes a [Str] instead of a [Path].
type! : Path => Result [IsFile, IsDir, IsSymLink] [PathErr IOErr]
type! = |path|
    Host.path_type!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))
    |> Result.map_ok(
        |path_type|
            if path_type.is_sym_link then
                IsSymLink
            else if path_type.is_dir then
                IsDir
            else
                IsFile,
    )

## If the last component of this path has no `.`, appends `.` followed by the given string.
## Otherwise, replaces everything after the last `.` with the given string.
##
## ```
## # Each of these gives "foo/bar/baz.txt"
## Path.from_str("foo/bar/baz") |> Path.with_extension("txt")
## Path.from_str("foo/bar/baz.") |> Path.with_extension("txt")
## Path.from_str("foo/bar/baz.xz") |> Path.with_extension("txt")
## ```
with_extension : Path, Str -> Path
with_extension = |path, extension|
    when InternalPath.unwrap(path) is
        FromOperatingSystem(bytes) | ArbitraryBytes(bytes) ->
            before_dot =
                when List.split_last(bytes, Num.to_u8('.')) is
                    Ok({ before }) -> before
                    Err(NotFound) -> bytes

            before_dot
            |> List.reserve((Str.count_utf8_bytes(extension) |> Num.int_cast |> Num.add_saturated(1)))
            |> List.append(Num.to_u8('.'))
            |> List.concat(Str.to_utf8(extension))
            |> ArbitraryBytes
            |> InternalPath.wrap

        FromStr(str) ->
            before_dot =
                when Str.split_last(str, ".") is
                    Ok({ before }) -> before
                    Err(NotFound) -> str

            before_dot
            |> Str.reserve((Str.count_utf8_bytes(extension) |> Num.add_saturated(1)))
            |> Str.concat(".")
            |> Str.concat(extension)
            |> FromStr
            |> InternalPath.wrap

## Deletes a file from the filesystem.
##
## Performs a [`DeleteFile`](https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-deletefile)
## on Windows and [`unlink`](https://en.wikipedia.org/wiki/Unlink_(Unix)) on
## UNIX systems. On Windows, this will fail when attempting to delete a readonly
## file; the file's readonly permission must be disabled before it can be
## successfully deleted.
##
## ```
## # Deletes the file named `myfile.dat`
## Path.delete!(Path.from_str("myfile.dat"))?
## ```
##
## > This does not securely erase the file's contents from disk; instead, the operating
## system marks the space it was occupying as safe to write over in the future. Also, the operating
## system may not immediately mark the space as free; for example, on Windows it will wait until
## the last file handle to it is closed, and on UNIX, it will not remove it until the last
## [hard link](https://en.wikipedia.org/wiki/Hard_link) to it has been deleted.
##
## > [`File.delete!`](File#delete!) does the same thing, except it takes a [Str] instead of a [Path].
delete! : Path => Result {} [FileWriteErr Path IOErr]
delete! = |path|
    Host.file_delete!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| FileWriteErr(path, InternalIOErr.handle_err(err)))

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## contents_str = Path.read_utf8!(Path.from_str("myfile.txt"))?
## ```
##
## This opens the file first and closes it after reading its contents.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [Path.read_bytes!] instead.
## >
## > [`File.read_utf8!`](File#read_utf8!) does the same thing, except it takes a [Str] instead of a [Path].
read_utf8! : Path => Result Str [FileReadErr Path IOErr, FileReadUtf8Err Path _]
read_utf8! = |path|
    bytes =
        Host.file_read_bytes!(InternalPath.to_bytes(path))
        |> Result.map_err(|read_err| FileReadErr(path, InternalIOErr.handle_err(read_err)))?

    Str.from_utf8(bytes)
    |> Result.map_err(|err| FileReadUtf8Err(path, err))

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## contents_bytes = Path.read_bytes!(Path.from_str("myfile.txt"))?
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file into a [Str], you can use [Path.read_utf8!] instead.
## >
## > [`File.read_bytes`](File#read_bytes!) does the same thing, except it takes a [Str] instead of a [Path].
read_bytes! : Path => Result (List U8) [FileReadErr Path IOErr]
read_bytes! = |path|
    Host.file_read_bytes!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| FileReadErr(path, InternalIOErr.handle_err(err)))

## Lists the files and directories inside the directory.
##
## > [`Dir.list`](Dir#list!) does the same thing, except it takes a [Str] instead of a [Path].
list_dir! : Path => Result (List Path) [DirErr IOErr]
list_dir! = |path|
    when Host.dir_list!(InternalPath.to_bytes(path)) is
        Ok(entries) -> Ok(List.map(entries, InternalPath.from_os_bytes))
        Err(err) -> Err(DirErr(InternalIOErr.handle_err(err)))

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [`Dir.delete_empty`](Dir#delete_empty!) does the same thing, except it takes a [Str] instead of a [Path].
delete_empty! : Path => Result {} [DirErr IOErr]
delete_empty! = |path|
    Host.dir_delete_empty!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| DirErr(InternalIOErr.handle_err(err)))

## Recursively deletes a directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [`Dir.delete_all`](Dir#delete_all!) does the same thing, except it takes a [Str] instead of a [Path].
delete_all! : Path => Result {} [DirErr IOErr]
delete_all! = |path|
    Host.dir_delete_all!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| DirErr(InternalIOErr.handle_err(err)))

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
##
## > [`Dir.create`](Dir#create!) does the same thing, except it takes a [Str] instead of a [Path].
create_dir! : Path => Result {} [DirErr IOErr]
create_dir! = |path|
    Host.dir_create!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| DirErr(InternalIOErr.handle_err(err)))

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
##
## > [`Dir.create_all`](Dir#create_all!) does the same thing, except it takes a [Str] instead of a [Path].
create_all! : Path => Result {} [DirErr IOErr]
create_all! = |path|
    Host.dir_create_all!(InternalPath.to_bytes(path))
    |> Result.map_err(|err| DirErr(InternalIOErr.handle_err(err)))

## Creates a new [hard link](https://en.wikipedia.org/wiki/Hard_link) on the filesystem.
##
## The link path will be a link pointing to the original path.
## Note that systems often require these two paths to both be located on the same filesystem.
##
## This uses [rust's std::fs::hard_link](https://doc.rust-lang.org/std/fs/fn.hard_link.html).
##
## > [File.hard_link!] does the same thing, except it takes a [Str] instead of a [Path].
hard_link! : Path, Path => Result {} [LinkErr IOErr]
hard_link! = |path_original, path_link|
    Host.hard_link!(InternalPath.to_bytes(path_original), InternalPath.to_bytes(path_link))
    |> Result.map_err(InternalIOErr.handle_err)
    |> Result.map_err(LinkErr)

## Renames a file or directory.
##
## This uses [rust's std::fs::rename](https://doc.rust-lang.org/std/fs/fn.rename.html).
rename! : Path, Path => Result {} [PathErr IOErr]
rename! = |from, to|
    from_path_bytes = InternalPath.to_bytes(from)
    to_path_bytes = InternalPath.to_bytes(to)
    Host.file_rename!(from_path_bytes, to_path_bytes)
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))
