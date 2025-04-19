module [
    IOErr,
    list!,
    create!,
    create_all!,
    delete_empty!,
    delete_all!,
]

import Path exposing [Path]
import InternalIOErr

## Tag union of possible errors when reading and writing a file or directory.
##
## > This is the same as [`File.IOErr`](File#IOErr).
IOErr : InternalIOErr.IOErr

## Lists the files and directories inside the directory.
##
## > [Path.list_dir!] does the same thing, except it takes a [Path] instead of a [Str].
list! : Str => Result (List Path) [DirErr IOErr]
list! = |path|
    Path.list_dir!(Path.from_str(path))

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [Path.delete_empty!] does the same thing, except it takes a [Path] instead of a [Str].
delete_empty! : Str => Result {} [DirErr IOErr]
delete_empty! = |path|
    Path.delete_empty!(Path.from_str(path))

## Recursively deletes the directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
##
## > [Path.delete_all!] does the same thing, except it takes a [Path] instead of a [Str].
delete_all! : Str => Result {} [DirErr IOErr]
delete_all! = |path|
    Path.delete_all!(Path.from_str(path))

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
##
## > [Path.create_dir!] does the same thing, except it takes a [Path] instead of a [Str].
create! : Str => Result {} [DirErr IOErr]
create! = |path|
    Path.create_dir!(Path.from_str(path))

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
##
## > [Path.create_all!] does the same thing, except it takes a [Path] instead of a [Str].
create_all! : Str => Result {} [DirErr IOErr]
create_all! = |path|
    Path.create_all!(Path.from_str(path))
