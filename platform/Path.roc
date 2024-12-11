module [
    Path,
    IOErr,
    DirEntry,
    LinkErr,
    display,
    fromStr,
    fromBytes,
    withExtension,
    # These can all be found in File as well
    isDir!,
    isFile!,
    isSymLink!,
    type!,
    writeUtf8!,
    writeBytes!,
    write!,
    readUtf8!,
    readBytes!,
    # read, TODO fix "Ability specialization is unknown - code generation cannot proceed!: DeriveError(UnboundVar)"
    delete!,
    # These can all be found in Dir as well
    listDir!,
    createDir!,
    createAll!,
    deleteEmpty!,
    deleteAll!,
    hardLink!,
]

import InternalPath
import InternalFile
import FileMetadata exposing [FileMetadata]
import Host

## Represents a path to a file or directory on the filesystem.
Path : InternalPath.InternalPath

## Record which represents a directory
##
## > This is the same as [`Dir.DirEntry`](Dir#DirEntry).
DirEntry : {
    path : Path,
    type : [File, Dir, Symlink],
    metadata : FileMetadata,
}

## Tag union of possible errors when reading and writing a file or directory.
##
## > This is the same as [`File.IOErr`](File#IOErr).
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
## Path.write!
##     { some: "json stuff" }
##     (Path.fromStr "output.json")
##     Json.toCompactUtf8
## ```
##
## This opens the file first and closes it after writing to it.
## If writing to the file fails, for example because of a file permissions issue, the task fails with [WriteErr].
##
## > To write unformatted bytes to a file, you can use [Path.writeBytes!] instead.
write! : val, Path, fmt => Result {} [FileWriteErr Path IOErr] where val implements Encoding, fmt implements EncoderFormatting
write! = \val, path, fmt ->
    bytes = Encode.toBytes val fmt

    # TODO handle encoding errors here, once they exist
    writeBytes! bytes path

## Writes bytes to a file.
##
## ```
## # Writes the bytes 1, 2, 3 to the file `myfile.dat`.
## Path.writeBytes! [1, 2, 3] (Path.fromStr "myfile.dat")
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To format data before writing it to a file, you can use [Path.write!] instead.
writeBytes! : List U8, Path => Result {} [FileWriteErr Path IOErr]
writeBytes! = \bytes, path ->
    pathBytes = InternalPath.toBytes path

    Host.fileWriteBytes! pathBytes bytes
    |> Result.mapErr \err -> FileWriteErr path (InternalFile.handleErr err)

## Writes a [Str] to a file, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Writes "Hello!" encoded as UTF-8 to the file `myfile.txt`.
## Path.writeUtf8! "Hello!" (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after writing to it.
##
## > To write unformatted bytes to a file, you can use [Path.writeBytes!] instead.
writeUtf8! : Str, Path => Result {} [FileWriteErr Path IOErr]
writeUtf8! = \str, path ->
    pathBytes = InternalPath.toBytes path

    Host.fileWriteUtf8! pathBytes str
    |> Result.mapErr \err -> FileWriteErr path (InternalFile.handleErr err)

## Note that the path may not be valid depending on the filesystem where it is used.
## For example, paths containing `:` are valid on ext4 and NTFS filesystems, but not
## on FAT ones. So if you have multiple disks on the same machine, but they have
## different filesystems, then this path could be valid on one but invalid on another!
##
## It's safest to assume paths are invalid (even syntactically) until given to an operation
## which uses them to open a file. If that operation succeeds, then the path was valid
## (at the time). Otherwise, error handling can happen for that operation rather than validating
## up front for a false sense of security (given symlinks, parts of a path being renamed, etc.).
fromStr : Str -> Path
fromStr = \str ->
    FromStr str
    |> InternalPath.wrap

## Not all filesystems use Unicode paths. This function can be used to create a path which
## is not valid Unicode (like a [Str] is), but which is valid for a particular filesystem.
##
## Note that if the list contains any `0` bytes, sending this path to any file operations
## (e.g. `Path.readBytes` or `WriteStream.openPath`) will fail.
fromBytes : List U8 -> Path
fromBytes = \bytes ->
    ArbitraryBytes bytes
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
## toInner : Path -> [Str Str, Bytes (List U8)]
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
## `toStrUsingCharset` instead of [display].
display : Path -> Str
display = \path ->
    when InternalPath.unwrap path is
        FromStr str -> str
        FromOperatingSystem bytes | ArbitraryBytes bytes ->
            when Str.fromUtf8 bytes is
                Ok str -> str
                # TODO: this should use the builtin Str.display to display invalid UTF-8 chars in just the right spots, but that does not exist yet!
                Err _ -> "�"

## Returns true if the path exists on disk and is pointing at a directory.
## Returns `Task.ok false` if the path exists and it is not a directory. If the path does not exist,
## this function will return `Task.err PathErr PathDoesNotExist`.
##
## This uses [rust's std::path::is_dir](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_dir).
##
## > [`File.isDir`](File#isDir!) does the same thing, except it takes a [Str] instead of a [Path].
isDir! : Path => Result Bool [PathErr IOErr]
isDir! = \path ->
    res = type!? path
    Ok (res == IsDir)

## Returns true if the path exists on disk and is pointing at a regular file.
## Returns `Task.ok false` if the path exists and it is not a file. If the path does not exist,
## this function will return `Task.err PathErr PathDoesNotExist`.
##
## This uses [rust's std::path::is_file](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_file).
##
## > [`File.isFile`](File#isFile!) does the same thing, except it takes a [Str] instead of a [Path].
isFile! : Path => Result Bool [PathErr IOErr]
isFile! = \path ->
    res = type!? path
    Ok (res == IsFile)

## Returns true if the path exists on disk and is pointing at a symbolic link.
## Returns `Task.ok false` if the path exists and it is not a symbolic link. If the path does not exist,
## this function will return `Task.err PathErr PathDoesNotExist`.
##
## This uses [rust's std::path::is_symlink](https://doc.rust-lang.org/std/path/struct.Path.html#method.is_symlink).
##
## > [`File.isSymLink`](File#isSymLink!) does the same thing, except it takes a [Str] instead of a [Path].
isSymLink! : Path => Result Bool [PathErr IOErr]
isSymLink! = \path ->
    res = type!? path
    Ok (res == IsSymLink)

## Return the type of the path if the path exists on disk.
##
## > [`File.type`](File#type!) does the same thing, except it takes a [Str] instead of a [Path].
type! : Path => Result [IsFile, IsDir, IsSymLink] [PathErr IOErr]
type! = \path ->
    Host.pathType! (InternalPath.toBytes path)
    |> Result.mapErr \err -> PathErr (InternalFile.handleErr err)
    |> Result.map \pathType ->
        if pathType.isSymLink then
            IsSymLink
        else if pathType.isDir then
            IsDir
        else
            IsFile

## If the last component of this path has no `.`, appends `.` followed by the given string.
## Otherwise, replaces everything after the last `.` with the given string.
##
## ```
## # Each of these gives "foo/bar/baz.txt"
## Path.fromStr "foo/bar/baz" |> Path.withExtension "txt"
## Path.fromStr "foo/bar/baz." |> Path.withExtension "txt"
## Path.fromStr "foo/bar/baz.xz" |> Path.withExtension "txt"
## ```
withExtension : Path, Str -> Path
withExtension = \path, extension ->
    when InternalPath.unwrap path is
        FromOperatingSystem bytes | ArbitraryBytes bytes ->
            beforeDot =
                when List.splitLast bytes (Num.toU8 '.') is
                    Ok { before } -> before
                    Err NotFound -> bytes

            beforeDot
            |> List.reserve (Str.countUtf8Bytes extension |> Num.intCast |> Num.addSaturated 1)
            |> List.append (Num.toU8 '.')
            |> List.concat (Str.toUtf8 extension)
            |> ArbitraryBytes
            |> InternalPath.wrap

        FromStr str ->
            beforeDot =
                when Str.splitLast str "." is
                    Ok { before } -> before
                    Err NotFound -> str

            beforeDot
            |> Str.reserve (Str.countUtf8Bytes extension |> Num.addSaturated 1)
            |> Str.concat "."
            |> Str.concat extension
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
## Path.delete (Path.fromStr "myfile.dat") [1, 2, 3]
## ```
##
## > This does not securely erase the file's contents from disk; instead, the operating
## system marks the space it was occupying as safe to write over in the future. Also, the operating
## system may not immediately mark the space as free; for example, on Windows it will wait until
## the last file handle to it is closed, and on UNIX, it will not remove it until the last
## [hard link](https://en.wikipedia.org/wiki/Hard_link) to it has been deleted.
##
## > [`File.delete`](File#delete!) does the same thing, except it takes a [Str] instead of a [Path].
delete! : Path => Result {} [FileWriteErr Path IOErr]
delete! = \path ->
    Host.fileDelete! (InternalPath.toBytes path)
    |> Result.mapErr \err -> FileWriteErr path (InternalFile.handleErr err)

## Reads a [Str] from a file containing [UTF-8](https://en.wikipedia.org/wiki/UTF-8)-encoded text.
##
## ```
## # Reads UTF-8 encoded text into a Str from the file "myfile.txt"
## Path.readUtf8 (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after writing to it.
## The task will fail with `FileReadUtf8Err` if the given file contains invalid UTF-8.
##
## > To read unformatted bytes from a file, you can use [Path.readBytes!] instead.
## >
## > [`File.readUtf8`](File#readUtf8!) does the same thing, except it takes a [Str] instead of a [Path].
readUtf8! : Path => Result Str [FileReadErr Path IOErr, FileReadUtf8Err Path _]
readUtf8! = \path ->
    bytes =
        Host.fileReadBytes! (InternalPath.toBytes path)
        |> Result.mapErr? \readErr -> FileReadErr path (InternalFile.handleErr readErr)

    Str.fromUtf8 bytes
    |> Result.mapErr \err -> FileReadUtf8Err path err

## Reads all the bytes in a file.
##
## ```
## # Read all the bytes in `myfile.txt`.
## Path.readBytes! (Path.fromStr "myfile.txt")
## ```
##
## This opens the file first and closes it after reading its contents.
##
## > To read and decode data from a file, you can use `Path.read` instead.
## >
## > [`File.readBytes`](File#readBytes!) does the same thing, except it takes a [Str] instead of a [Path].
readBytes! : Path => Result (List U8) [FileReadErr Path IOErr]
readBytes! = \path ->
    Host.fileReadBytes! (InternalPath.toBytes path)
    |> Result.mapErr \err -> FileReadErr path (InternalFile.handleErr err)

## Lists the files and directories inside the directory.
##
## > [`Dir.list`](Dir#list!) does the same thing, except it takes a [Str] instead of a [Path].
listDir! : Path => Result (List Path) [DirErr IOErr]
listDir! = \path ->
    when Host.dirList! (InternalPath.toBytes path) is
        Ok entries -> Ok (List.map entries InternalPath.fromOsBytes)
        Err err -> Err (DirErr (InternalFile.handleErr err))

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [`Dir.deleteEmpty`](Dir#deleteEmpty!) does the same thing, except it takes a [Str] instead of a [Path].
deleteEmpty! : Path => Result {} [DirErr IOErr]
deleteEmpty! = \path ->
    Host.dirDeleteEmpty! (InternalPath.toBytes path)
    |> Result.mapErr \err -> DirErr (InternalFile.handleErr err)

## Recursively deletes a directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [`Dir.deleteAll`](Dir#deleteAll!) does the same thing, except it takes a [Str] instead of a [Path].
deleteAll! : Path => Result {} [DirErr IOErr]
deleteAll! = \path ->
    Host.dirDeleteAll! (InternalPath.toBytes path)
    |> Result.mapErr \err -> DirErr (InternalFile.handleErr err)

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
##
## > [`Dir.create`](Dir#create!) does the same thing, except it takes a [Str] instead of a [Path].
createDir! : Path => Result {} [DirErr IOErr]
createDir! = \path ->
    Host.dirCreate! (InternalPath.toBytes path)
    |> Result.mapErr \err -> DirErr (InternalFile.handleErr err)

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
##
## > [`Dir.createAll`](Dir#createAll!) does the same thing, except it takes a [Str] instead of a [Path].
createAll! : Path => Result {} [DirErr IOErr]
createAll! = \path ->
    Host.dirCreateAll! (InternalPath.toBytes path)
    |> Result.mapErr \err -> DirErr (InternalFile.handleErr err)

## Creates a new hard link on the filesystem.
##
## The link path will be a link pointing to the original path.
## Note that systems often require these two paths to both be located on the same filesystem.
##
## This uses [rust's std::fs::hard_link](https://doc.rust-lang.org/std/fs/fn.hard_link.html).
##
## > [File.hardLink!] does the same thing, except it takes a [Str] instead of a [Path].
hardLink! : Path => Result {} [LinkErr LinkErr]
hardLink! = \path ->
    Host.hardLink! (InternalPath.toBytes path)
    |> Result.mapErr LinkErr

## Tag union of possible errors when linking a file or directory.
LinkErr : Host.InternalIOErr
