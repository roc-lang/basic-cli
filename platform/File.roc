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
    type!,
    open_reader!,
    open_reader_with_capacity!,
    read_line!,
    hard_link!,
]

import Path exposing [Path]
import InternalIOErr
import Host

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
## For example, suppose you have a `Json.to_compact_utf8` which implements
## [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
## You can use this to write [JSON](https://en.wikipedia.org/wiki/JSON)
## data to a file like this:
##
## ```
## # Writes `{"some":"json stuff"}` to the file `output.json`:
## File.write!(
##     { some: "json stuff" },
##     Path.from_str("output.json"),
##     Json.to_compact_utf8,
## )
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [File.write_bytes!] instead.
## >
## > [Path.write!] does the same thing, except it takes a [Path] instead of a [Str].
write! : val, Str, fmt => Result {} [FileWriteErr Path IOErr] where val implements Encoding, fmt implements EncoderFormatting
write! = |val, path, fmt|
    Path.write!(val, Path.from_str(path), fmt)

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## File.write_bytes!([1, 2, 3], Path.from_str("myfile.dat"))?
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [File.write!] instead.
## >
## > [Path.write_bytes!] does the same thing, except it takes a [Path] instead of a [Str].
write_bytes! : List U8, Str => Result {} [FileWriteErr Path IOErr]
write_bytes! = |bytes, path|
    Path.write_bytes!(bytes, Path.from_str(path))

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
write_utf8! = |str, path|
    Path.write_utf8!(str, Path.from_str(path))

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
## File.delete!(Path.from_str("myfile.dat"), [1, 2, 3])?
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
delete! = |path|
    Path.delete!(Path.from_str(path))

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
read_bytes! = |path|
    Path.read_bytes!(Path.from_str(path))

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
read_utf8! = |path|
    Path.read_utf8!(Path.from_str(path))

# read : Str, fmt => Result contents [FileReadErr Path ReadErr, FileReadDecodingFailed] where contents implements Decoding, fmt implements DecoderFormatting
# read = \path, fmt ->
#    Path.read! (Path.from_str path) fmt

## Creates a new hard link on the filesystem.
##
## The link path will be a link pointing to the original path.
## Note that systems often require these two paths to both be located on the same filesystem.
##
## This uses [rust's std::fs::hard_link](https://doc.rust-lang.org/std/fs/fn.hard_link.html).
##
## > [Path.hard_link!] does the same thing, except it takes a [Path] instead of a [Str].
hard_link! : Str => Result {} [LinkErr IOErr]
hard_link! = |path|
    Path.hard_link!(Path.from_str(path))

## Returns True if the path exists on disk and is pointing at a directory.
## Returns False if the path exists and it is not a directory. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_dir](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_dir).
##
## > [Path.is_dir!] does the same thing, except it takes a [Path] instead of a [Str].
is_dir! : Str => Result Bool [PathErr IOErr]
is_dir! = |path|
    Path.is_dir!(Path.from_str(path))

## Returns True if the path exists on disk and is pointing at a regular file.
## Returns False if the path exists and it is not a file. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_file](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_file).
##
## > [Path.is_file!] does the same thing, except it takes a [Path] instead of a [Str].
is_file! : Str => Result Bool [PathErr IOErr]
is_file! = |path|
    Path.is_file!(Path.from_str(path))

## Returns True if the path exists on disk and is pointing at a symbolic link.
## Returns False if the path exists and it is not a symbolic link. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.is_sym_link!] does the same thing, except it takes a [Path] instead of a [Str].
is_sym_link! : Str => Result Bool [PathErr IOErr]
is_sym_link! = |path|
    Path.is_sym_link!(Path.from_str(path))

## Return the type of the path if the path exists on disk.
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.type!] does the same thing, except it takes a [Path] instead of a [Str].
type! : Str => Result [IsFile, IsDir, IsSymLink] [PathErr IOErr]
type! = |path|
    Path.type!(Path.from_str(path))

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
