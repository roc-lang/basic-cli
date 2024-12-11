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

## Tag union of possible errors when reading and writing a file or directory.
##
## > This is the same as [`File.IOErr`](File#IOErr).
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
