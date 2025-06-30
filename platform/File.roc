module [
    IOErr,
    Reader,
    write_utf8!,
    write_bytes!,
    write!,
    read_utf8!,
    read_bytes!,
    delete!,
    is_dir!,
    is_file!,
    is_sym_link!,
    exists!,
    is_executable!,
    is_readable!,
    is_writable!,
    time_accessed!,
    time_modified!,
    time_created!,
    rename!,
    type!,
    open_reader!,
    open_reader_with_capacity!,
    read_line!,
    hard_link!,
    size_in_bytes!,
]

import Path exposing [Path]
import InternalIOErr
import Host
import InternalPath
import Utc exposing [Utc]

## Tag union of possible errors when reading and writing a file or directory.
##
## **NotFound** - An entity was not found, often a file.
##
## **PermissionDenied** - The operation lacked the necessary privileges to complete.
##
## **BrokenPipe** - The operation failed because a pipe was closed.
##
## **AlreadyExists** - An entity already exists, often a file.
##
## **Interrupted** - This operation was interrupted. Interrupted operations can typically be retried.
##
## **Unsupported** - This operation is unsupported on this platform. This means that the operation can never succeed.
##
## **OutOfMemory** - An operation could not be completed, because it failed to allocate enough memory.
##
## **Other** - A custom error that does not fall under any other I/O error kind.
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
## File.write!(
##     { some: "json stuff" },
##     "output.json",
##     Json.utf8,
## )?
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [File.write_bytes!] instead.
## >
## > [Path.write!] does the same thing, except it takes a [Path] instead of a [Str].
write! : val, Str, fmt => Result {} [FileWriteErr Path IOErr] where val implements Encoding, fmt implements EncoderFormatting
write! = |val, path_str, fmt|
    Path.write!(val, Path.from_str(path_str), fmt)

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## File.write_bytes!([1, 2, 3], "myfile.dat")?
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [File.write!] instead.
## >
## > [Path.write_bytes!] does the same thing, except it takes a [Path] instead of a [Str].
write_bytes! : List U8, Str => Result {} [FileWriteErr Path IOErr]
write_bytes! = |bytes, path_str|
    Path.write_bytes!(bytes, Path.from_str(path_str))

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## File.write_utf8!("Hello!", "myfile.txt")?
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [File.write_bytes!] instead.
## >
## > [Path.write_utf8!] does the same thing, except it takes a [Path] instead of a [Str].
write_utf8! : Str, Str => Result {} [FileWriteErr Path IOErr]
write_utf8! = |str, path_str|
    Path.write_utf8!(str, Path.from_str(path_str))

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
## File.delete!("myfile.dat")?
## ```
##
## > This does not securely erase the file's contents from disk; instead, the operating
## system marks the space it was occupying as safe to write over in the future. Also, the operating
## system may not immediately mark the space as free; for example, on Windows it will wait until
## the last file handle to it is closed, and on UNIX, it will not remove it until the last
## [hard link](https://en.wikipedia.org/wiki/Hard_link) to it has been deleted.
## >
## > [Path.delete!] does the same thing, except it takes a [Path] instead of a [Str].
delete! : Str => Result {} [FileWriteErr Path IOErr]
delete! = |path_str|
    Path.delete!(Path.from_str(path_str))

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## bytes = File.read_bytes!("myfile.txt")?
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file into a [Str], you can use [File.read_utf8!] instead.
## >
## > [Path.read_bytes!] does the same thing, except it takes a [Path] instead of a [Str].
read_bytes! : Str => Result (List U8) [FileReadErr Path IOErr]
read_bytes! = |path_str|
    Path.read_bytes!(Path.from_str(path_str))

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## str = File.read_utf8!("myfile.txt")?
## ```
##
## This opens the file first and closes it after reading its contents.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [File.read_bytes!] instead.
##
## > [Path.read_utf8!] does the same thing, except it takes a [Path] instead of a [Str].
read_utf8! : Str => Result Str [FileReadErr Path IOErr, FileReadUtf8Err Path _]
read_utf8! = |path_str|
    Path.read_utf8!(Path.from_str(path_str))


## Creates a new [hard link](https://en.wikipedia.org/wiki/Hard_link) on the filesystem.
##
## The link path will be a link pointing to the original path.
## Note that systems often require these two paths to both be located on the same filesystem.
##
## This uses [rust's std::fs::hard_link](https://doc.rust-lang.org/std/fs/fn.hard_link.html).
##
## > [Path.hard_link!] does the same thing, except it takes a [Path] instead of a [Str].
hard_link! : Str, Str => Result {} [LinkErr IOErr]
hard_link! = |path_str_original, path_str_link|
    Path.hard_link!(Path.from_str(path_str_original), Path.from_str(path_str_link))

## Returns True if the path exists on disk and is pointing at a directory.
## Returns False if the path exists and it is not a directory. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_dir](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_dir).
##
## > [Path.is_dir!] does the same thing, except it takes a [Path] instead of a [Str].
is_dir! : Str => Result Bool [PathErr IOErr]
is_dir! = |path_str|
    Path.is_dir!(Path.from_str(path_str))

## Returns True if the path exists on disk and is pointing at a regular file.
## Returns False if the path exists and it is not a file. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_file](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_file).
##
## > [Path.is_file!] does the same thing, except it takes a [Path] instead of a [Str].
is_file! : Str => Result Bool [PathErr IOErr]
is_file! = |path_str|
    Path.is_file!(Path.from_str(path_str))

## Returns True if the path exists on disk and is pointing at a symbolic link.
## Returns False if the path exists and it is not a symbolic link. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.is_sym_link!] does the same thing, except it takes a [Path] instead of a [Str].
is_sym_link! : Str => Result Bool [PathErr IOErr]
is_sym_link! = |path_str|
    Path.is_sym_link!(Path.from_str(path_str))

## Returns true if the path exists on disk.
##
## This uses [rust's std::path::try_exists](https://doc.rust-lang.org/std/path/struct.Path.html#method.try_exists).
exists! : Str => Result Bool [PathErr IOErr]
exists! = |path_str|
    Host.file_exists!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Checks if the file has the execute permission for the current process.
##
## This uses rust [std::fs::Metadata](https://doc.rust-lang.org/std/fs/struct.Metadata.html).
is_executable! : Str => Result Bool [PathErr IOErr]
is_executable! = |path_str|
    Host.file_is_executable!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Checks if the file has the readable permission for the current process.
##
## This uses rust [std::fs::Metadata](https://doc.rust-lang.org/std/fs/struct.Metadata.html).
is_readable! : Str => Result Bool [PathErr IOErr]
is_readable! = |path_str|
    Host.file_is_readable!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Checks if the file has the writeable permission for the current process.
##
## This uses rust [std::fs::Metadata](https://doc.rust-lang.org/std/fs/struct.Metadata.html).
is_writable! : Str => Result Bool [PathErr IOErr]
is_writable! = |path_str|
    Host.file_is_writable!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Returns the time when the file was last accessed.
##
## This uses [rust's std::fs::Metadata::accessed](https://doc.rust-lang.org/std/fs/struct.Metadata.html#method.accessed).
## Note that this is [not guaranteed to be correct in all cases](https://doc.rust-lang.org/std/fs/struct.Metadata.html#method.accessed).
##
## NOTE: these functions will not work if basic-cli was built with musl, which is the case for the normal tar.br URL release.
## See https://github.com/roc-lang/basic-cli?tab=readme-ov-file#running-locally to build basic-cli without musl.
time_accessed! : Str => Result Utc [PathErr IOErr]
time_accessed! = |path_str|
    Host.file_time_accessed!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_ok(|time_u128| Num.to_i128(time_u128) |> Utc.from_nanos_since_epoch)
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Returns the time when the file was last modified.
##
## This uses [rust's std::fs::Metadata::modified](https://doc.rust-lang.org/std/fs/struct.Metadata.html#method.modified).
##
## NOTE: these functions will not work if basic-cli was built with musl, which is the case for the normal tar.br URL release.
## See https://github.com/roc-lang/basic-cli?tab=readme-ov-file#running-locally to build basic-cli without musl.
time_modified! : Str => Result Utc [PathErr IOErr]
time_modified! = |path_str|
    Host.file_time_modified!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_ok(|time_u128| Num.to_i128(time_u128) |> Utc.from_nanos_since_epoch)
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Returns the time when the file was created.
##
## This uses [rust's std::fs::Metadata::created](https://doc.rust-lang.org/std/fs/struct.Metadata.html#method.created).
##
## NOTE: these functions will not work if basic-cli was built with musl, which is the case for the normal tar.br URL release.
## See https://github.com/roc-lang/basic-cli?tab=readme-ov-file#running-locally to build basic-cli without musl.
time_created! : Str => Result Utc [PathErr IOErr]
time_created! = |path_str|
    Host.file_time_created!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_ok(|time_u128| Num.to_i128(time_u128) |> Utc.from_nanos_since_epoch)
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Renames a file or directory.
##
## This uses [rust's std::fs::rename](https://doc.rust-lang.org/std/fs/fn.rename.html).
rename! : Str, Str => Result {} [PathErr IOErr]
rename! = |from_str, to_str|
    from_bytes = InternalPath.to_bytes(Path.from_str(from_str))
    to_bytes = InternalPath.to_bytes(Path.from_str(to_str))
    Host.file_rename!(from_bytes, to_bytes)
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))

## Return the type of the path if the path exists on disk.
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.type!] does the same thing, except it takes a [Path] instead of a [Str].
type! : Str => Result [IsFile, IsDir, IsSymLink] [PathErr IOErr]
type! = |path_str|
    Path.type!(Path.from_str(path_str))

Reader := { reader : Host.FileReader, path : Path }

## Try to open a `File.Reader` for buffered (= part by part) reading given a path string.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html).
##
## Use [read_utf8!] if you want to get the entire file contents at once.
open_reader! : Str => Result Reader [GetFileReadErr Path IOErr]
open_reader! = |path_str|
    path = Path.from_str(path_str)

    # 0 means with default capacity
    Host.file_reader!(Str.to_utf8(path_str), 0)
    |> Result.map_err(|err| GetFileReadErr(path, InternalIOErr.handle_err(err)))
    |> Result.map_ok(|reader| @Reader({ reader, path }))

## Try to open a `File.Reader` for buffered (= part by part) reading given a path string.
## The buffer will be created with the specified capacity.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html).
##
## Use [read_utf8!] if you want to get the entire file contents at once.
open_reader_with_capacity! : Str, U64 => Result Reader [GetFileReadErr Path IOErr]
open_reader_with_capacity! = |path_str, capacity|
    path = Path.from_str(path_str)

    Host.file_reader!(Str.to_utf8(path_str), capacity)
    |> Result.map_err(|err| GetFileReadErr(path, InternalIOErr.handle_err(err)))
    |> Result.map_ok(|reader| @Reader({ reader, path }))

## Try to read a line from a file given a Reader.
## The line will be provided as the list of bytes (`List U8`) until a newline (`0xA` byte).
## This list will be empty when we reached the end of the file.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's `BufRead::read_line`](https://doc.rust-lang.org/std/io/trait.BufRead.html#method.read_line).
##
## Use [read_utf8!] if you want to get the entire file contents at once.
read_line! : Reader => Result (List U8) [FileReadErr Path IOErr]
read_line! = |@Reader({ reader, path })|
    Host.file_read_line!(reader)
    |> Result.map_err(|err| FileReadErr(path, InternalIOErr.handle_err(err)))

## Returns the size of a file in bytes.
## 
## This uses [rust's std::fs::Metadata::len](https://doc.rust-lang.org/std/fs/struct.Metadata.html#method.len).
size_in_bytes! : Str => Result U64 [PathErr IOErr]
size_in_bytes! = |path_str|
    Host.file_size_in_bytes!(InternalPath.to_bytes(Path.from_str(path_str)))
    |> Result.map_err(|err| PathErr(InternalIOErr.handle_err(err)))