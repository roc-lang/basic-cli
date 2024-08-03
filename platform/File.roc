module [
    ReadErr,
    WriteErr,
    writeUtf8,
    writeBytes,
    write,
    readUtf8,
    readBytes,
    # read, TODO fix "Ability specialization is unknown - code generation cannot proceed!: DeriveError(UnboundVar)"
    delete,
    isDir,
    isFile,
    isSymLink,
    type,
    Reader,
    openReader,
    openReaderWithCapacity,
    readLine,
]

import Path exposing [Path, MetadataErr]
import InternalFile
import PlatformTask

## Tag union of possible errors when reading a file or directory.
##
## > This is the same as [`Path.ReadErr`].
ReadErr : Path.ReadErr

## Tag union of possible errors when writing a file or directory.
##
## > This is the same as [`Path.WriteErr`].
WriteErr : Path.WriteErr

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
## File.write
##     (Path.fromStr "output.json")
##     { some: "json stuff" }
##     Json.toCompactUtf8
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [File.writeBytes] instead.
## >
## > [Path.write] does the same thing, except it takes a [Path] instead of a [Str].
write : Str, val, fmt -> Task {} [FileWriteErr Path WriteErr] where val implements Encoding, fmt implements EncoderFormatting
write = \path, val, fmt ->
    Path.write (Path.fromStr path) val fmt

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## File.writeBytes (Path.fromStr "myfile.dat") [1, 2, 3]
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [File.write] instead.
## >
## > [Path.writeBytes] does the same thing, except it takes a [Path] instead of a [Str].
writeBytes : Str, List U8 -> Task {} [FileWriteErr Path WriteErr]
writeBytes = \path, bytes ->
    Path.writeBytes (Path.fromStr path) bytes

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## File.writeUtf8 (Path.fromStr "myfile.txt") "Hello!"
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [File.writeBytes] instead.
## >
## > [Path.writeUtf8] does the same thing, except it takes a [Path] instead of a [Str].
writeUtf8 : Str, Str -> Task {} [FileWriteErr Path WriteErr]
writeUtf8 = \path, str ->
    Path.writeUtf8 (Path.fromStr path) str

## Deletes a file from the filesystem.
##
## Performs a [`DeleteFile`](https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-deletefile)
## on Windows and [`unlink`](https://en.wikipedia.org/wiki/Unlink_(Unix)) on
## UNIX systems. On Windows, this will fail when attempting to delete a readonly
## file; the file's readonly permission must be disabled before it can be
## successfully deleted.
##
## ```
## # Deletes the file named
## File.delete (Path.fromStr "myfile.dat") [1, 2, 3]
## ```
##
## > This does not securely erase the file's contents from disk; instead, the operating
## system marks the space it was occupying as safe to write over in the future. Also, the operating
## system may not immediately mark the space as free; for example, on Windows it will wait until
## the last file handle to it is closed, and on UNIX, it will not remove it until the last
## [hard link](https://en.wikipedia.org/wiki/Hard_link) to it has been deleted.
## >
## > [Path.delete] does the same thing, except it takes a [Path] instead of a [Str].
delete : Str -> Task {} [FileWriteErr Path WriteErr]
delete = \path ->
    Path.delete (Path.fromStr path)

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## File.readBytes "myfile.txt"
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file, you can use `File.read` instead.
## >
## > [Path.readBytes] does the same thing, except it takes a [Path] instead of a [Str].
readBytes : Str -> Task (List U8) [FileReadErr Path ReadErr]
readBytes = \path ->
    Path.readBytes (Path.fromStr path)

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## File.readUtf8 "myfile.txt"
## ```
##
## This opens the file first and closes it after writing to it.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [File.readBytes] instead.
##
## > [Path.readUtf8] does the same thing, except it takes a [Path] instead of a [Str].
readUtf8 : Str -> Task Str [FileReadErr Path ReadErr, FileReadUtf8Err Path _]
readUtf8 = \path ->
    Path.readUtf8 (Path.fromStr path)

# read : Str, fmt -> Task contents [FileReadErr Path ReadErr, FileReadDecodingFailed] where contents implements Decoding, fmt implements DecoderFormatting
# read = \path, fmt ->
#    Path.read (Path.fromStr path) fmt

## Returns true if the path exists on disk and is pointing at a directory.
## Any error will return false.
## This uses [rust's std::path::is_dir](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_dir).
##
## > [Path.isDir] does the same thing, except it takes a [Path] instead of a [Str].
isDir : Str -> Task Bool [PathErr MetadataErr]
isDir = \path ->
    Path.isDir (Path.fromStr path)

## Returns true if the path exists on disk and is pointing at a regular file.
## Any error will return false.
## This uses [rust's std::path::is_file](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_file).
##
## > [Path.isFile] does the same thing, except it takes a [Path] instead of a [Str].
isFile : Str -> Task Bool [PathErr MetadataErr]
isFile = \path ->
    Path.isFile (Path.fromStr path)

## Returns true if the path exists on disk and is pointing at a symbolic link.
## Any error will return false.
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.isSymLink] does the same thing, except it takes a [Path] instead of a [Str].
isSymLink : Str -> Task Bool [PathErr MetadataErr]
isSymLink = \path ->
    Path.isSymLink (Path.fromStr path)

## Return the type of the path if the path exists on disk.
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [Path.type] does the same thing, except it takes a [Path] instead of a [Str].
type : Str -> Task [IsFile, IsDir, IsSymLink] [PathErr MetadataErr]
type = \path ->
    Path.type (Path.fromStr path)

Reader := { reader : PlatformTask.FileReader, path : Path }

## Try to open a `File.Reader` for buffered (= part by part) reading given a path string.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html).
##
## Use [readUtf8] if you want to get the entire file contents at once.
openReader : Str -> Task Reader [GetFileReadErr Path ReadErr]
openReader = \pathStr ->
    path = Path.fromStr pathStr

    # 0 means with default capacity
    PlatformTask.fileReader (Str.toUtf8 pathStr) 0
    |> Task.mapErr \err -> GetFileReadErr path (InternalFile.handleReadErr err)
    |> Task.map \reader -> @Reader { reader, path }

## Try to open a `File.Reader` for buffered (= part by part) reading given a path string.
## The buffer will be created with the specified capacity.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html).
##
## Use [readUtf8] if you want to get the entire file contents at once.
openReaderWithCapacity : Str, U64 -> Task Reader [GetFileReadErr Path ReadErr]
openReaderWithCapacity = \pathStr, capacity ->
    path = Path.fromStr pathStr

    PlatformTask.fileReader (Str.toUtf8 pathStr) capacity
    |> Task.mapErr \err -> GetFileReadErr path (InternalFile.handleReadErr err)
    |> Task.map \reader -> @Reader { reader, path }

## Try to read a line from a file given a Reader.
## The line will be provided as the list of bytes (`List U8`) until a newline (`0xA` byte).
## This list will be empty when we reached the end of the file.
## See [examples/file-read-buffered.roc](https://github.com/roc-lang/basic-cli/blob/main/examples/file-read-buffered.roc) for example usage.
##
## This uses [rust's `BufRead::read_line`](https://doc.rust-lang.org/std/io/trait.BufRead.html#method.read_line).
##
## Use [readUtf8] if you want to get the entire file contents at once.
readLine : Reader -> Task (List U8) [FileReadErr Path Str]
readLine = \@Reader { reader, path } ->
    PlatformTask.fileReadLine reader
    |> Task.mapErr \err -> FileReadErr path err
