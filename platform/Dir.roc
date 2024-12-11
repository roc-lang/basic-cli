module [
    DirEntry,
    IOErr,
    list!,
    create!,
    createAll!,
    deleteEmpty!,
    deleteAll!,
]

import Path exposing [Path]
import InternalFile

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

## Record which represents a directory
##
## > This is the same as [`Path.DirEntry`](Path#DirEntry).
DirEntry : Path.DirEntry

## Lists the files and directories inside the directory.
##
## > [Path.listDir!] does the same thing, except it takes a [Path] instead of a [Str].
list! : Str => Result (List Path) [DirErr IOErr]
list! = \path ->
    Path.listDir! (Path.fromStr path)

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [Path.deleteEmpty!] does the same thing, except it takes a [Path] instead of a [Str].
deleteEmpty! : Str => Result {} [DirErr IOErr]
deleteEmpty! = \path ->
    Path.deleteEmpty! (Path.fromStr path)

## Recursively deletes the directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [Path.deleteAll!] does the same thing, except it takes a [Path] instead of a [Str].
deleteAll! : Str => Result {} [DirErr IOErr]
deleteAll! = \path ->
    Path.deleteAll! (Path.fromStr path)

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
##
## > [Path.createDir!] does the same thing, except it takes a [Path] instead of a [Str].
create! : Str => Result {} [DirErr IOErr]
create! = \path ->
    Path.createDir! (Path.fromStr path)

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
##
## > [Path.createAll!] does the same thing, except it takes a [Path] instead of a [Str].
createAll! : Str => Result {} [DirErr IOErr]
createAll! = \path ->
    Path.createAll! (Path.fromStr path)
