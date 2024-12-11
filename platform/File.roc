module [
    IOErr,
    writeUtf8!,
    writeBytes!,
    write!,
    readUtf8!,
    readBytes!,
    # read, TODO fix "Ability specialization is unknown - code generation cannot proceed!: DeriveError(UnboundVar)"
    delete!,
    isDir!,
    isFile!,
    isSymLink!,
    type!,
    Reader,
    openReader!,
    openReaderWithCapacity!,
    readLine!,
    hardLink!,
]

import Path exposing [Path]
import InternalFile
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
IOErr : InternalFile.IOErr

## Write data to a file.
##
## First encode a `val` using a given `fmt` which implements the ability [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
##
## For example, suppose you have a `Json.toCompactUtf8` which implements
## [Encode.EncoderFormatting](https://www.roc-lang.org/builtins/Encode#EncoderFormatting).
## You can use this to write [JSON](https://en.wikipedia.org/wiki/JSON)
## data to a file like this:
##
## ```
## # Writes `{"some":"json stuff"}` to the file `output.json`:
## File.write!
##     { some: "json stuff" }
##     (Path.fromStr "output.json")
##     Json.toCompactUtf8
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [File.writeBytes!] instead.
## >
## > [Path.write!] does the same thing, except it takes a [Path] instead of a [Str].
write! : val, Str, fmt => Result {} [FileWriteErr Path IOErr] where val implements Encoding, fmt implements EncoderFormatting
write! = \val, path, fmt ->
    Path.write! val (Path.fromStr path) fmt

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## File.writeBytes! [1, 2, 3] (Path.fromStr "myfile.dat")
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [File.write!] instead.
## >
## > [Path.writeBytes!] does the same thing, except it takes a [Path] instead of a [Str].
writeBytes! : List U8, Str => Result {} [FileWriteErr Path IOErr]
writeBytes! = \bytes, path ->
    Path.writeBytes! bytes (Path.fromStr path)

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## File.writeUtf8! "Hello!" "myfile.txt"
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [File.writeBytes!] instead.
## >
## > [Path.writeUtf8!] does the same thing, except it takes a [Path] instead of a [Str].
writeUtf8! : Str, Str => Result {} [FileWriteErr Path IOErr]
writeUtf8! = \str, path ->
    Path.writeUtf8! str (Path.fromStr path)

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
## File.delete! (Path.fromStr "myfile.dat") [1, 2, 3]
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
delete! = \path ->
    Path.delete! (Path.fromStr path)

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## File.readBytes! "myfile.txt"
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file, you can use `File.read` instead.
## >
## > [Path.readBytes!] does the same thing, except it takes a [Path] instead of a [Str].
readBytes! : Str => Result (List U8) [FileReadErr Path IOErr]
readBytes! = \path ->
    Path.readBytes! (Path.fromStr path)

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## File.readUtf8! "myfile.txt"
## ```
##
## This opens the file first and closes it after writing to it.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [File.readBytes!] instead.
##
## > [Path.readUtf8!] does the same thing, except it takes a [Path] instead of a [Str].
readUtf8! : Str => Result Str [FileReadErr Path IOErr, FileReadUtf8Err Path _]
readUtf8! = \path ->
    Path.readUtf8! (Path.fromStr path)

# read : Str, fmt => Result contents [FileReadErr Path ReadErr, FileReadDecodingFailed] where contents implements Decoding, fmt implements DecoderFormatting
# read = \path, fmt ->
#    Path.read! (Path.fromStr path) fmt

## Creates a new hard link on the filesystem.
##
## The link path will be a link pointing to the original path.
## Note that systems often require these two paths to both be located on the same filesystem.
##
## This uses [rust's std::fs::hard_link](https://doc.rust-lang.org/std/fs/fn.hard_link.html).
##
## > [Path.hardLink!] does the same thing, except it takes a [Path] instead of a [Str].
hardLink! : Str => Result {} [LinkErr Path.LinkErr]
hardLink! = \path ->
    Path.hardLink! (Path.fromStr path)

## Returns True if the path exists on disk and is pointing at a directory.
## Returns False if the path exists and it is not a directory. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_dir](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_dir).
##
## > [Path.isDir!] does the same thing, except it takes a [Path] instead of a [Str].
isDir! : Str => Result Bool [PathErr IOErr]
isDir! = \path ->
    Path.isDir! (Path.fromStr path)

## Returns True if the path exists on disk and is pointing at a regular file.
## Returns False if the path exists and it is not a file. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_file](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_file).
##
## > [Path.isFile!] does the same thing, except it takes a [Path] instead of a [Str].
isFile! : Str => Result Bool [PathErr IOErr]
isFile! = \path ->
    Path.isFile! (Path.fromStr path)

## Returns True if the path exists on disk and is pointing at a symbolic link.
## Returns False if the path exists and it is not a symbolic link. If the path does not exist,
## this function will return `Err (PathErr PathDoesNotExist)`.
##
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.isSymLink!] does the same thing, except it takes a [Path] instead of a [Str].
isSymLink! : Str => Result Bool [PathErr IOErr]
isSymLink! = \path ->
    Path.isSymLink! (Path.fromStr path)

## Return the type of the path if the path exists on disk.
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.type!] does the same thing, except it takes a [Path] instead of a [Str].
type! : Str => Result [IsFile, IsDir, IsSymLink] [PathErr IOErr]
type! = \path ->
    Path.type! (Path.fromStr path)

Reader := { reader : Host.FileReader, path : Path }

## Try to open a `File.Reader` for buffered (= part by part) reading given a path string.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html).
##
## Use [readUtf8!] if you want to get the entire file contents at once.
openReader! : Str => Result Reader [GetFileReadErr Path IOErr]
openReader! = \pathStr ->
    path = Path.fromStr pathStr

    # 0 means with default capacity
    Host.fileReader! (Str.toUtf8 pathStr) 0
    |> Result.mapErr \err -> GetFileReadErr path (InternalFile.handleErr err)
    |> Result.map \reader -> @Reader { reader, path }

## Try to open a `File.Reader` for buffered (= part by part) reading given a path string.
## The buffer will be created with the specified capacity.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html).
##
## Use [readUtf8!] if you want to get the entire file contents at once.
openReaderWithCapacity! : Str, U64 => Result Reader [GetFileReadErr Path IOErr]
openReaderWithCapacity! = \pathStr, capacity ->
    path = Path.fromStr pathStr

    Host.fileReader! (Str.toUtf8 pathStr) capacity
    |> Result.mapErr \err -> GetFileReadErr path (InternalFile.handleErr err)
    |> Result.map \reader -> @Reader { reader, path }

## Try to read a line from a file given a Reader.
## The line will be provided as the list of bytes (`List U8`) until a newline (`0xA` byte).
## This list will be empty when we reached the end of the file.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's `BufRead::read_line`](https://doc.rust-lang.org/std/io/trait.BufRead.html#method.read_line).
##
## Use [readUtf8!] if you want to get the entire file contents at once.
readLine! : Reader => Result (List U8) [FileReadErr Path IOErr]
readLine! = \@Reader { reader, path } ->
    Host.fileReadLine! reader
    |> Result.mapErr \err -> FileReadErr path (InternalFile.handleErr err)
