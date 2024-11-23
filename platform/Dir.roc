module [
    DirEntry,
    Err,
    list!,
    create!,
    createAll!,
    deleteEmpty!,
    deleteAll!,
]

import Path exposing [Path]

## **NotFound** - This error is raised when the specified path does not exist, typically during attempts to access or manipulate it, but also potentially when trying to create a directory and a parent directory does not exist.
##
## **PermissionDenied** - Occurs when the user lacks the necessary permissions to perform an action on a directory, such as reading, writing, or executing.
##
## **Other** - A catch-all for any other types of errors not explicitly listed above.
##
## > This is the same as [`Path.DirErr`].
Err : Path.DirErr

## Record which represents a directory
##
## > This is the same as [`Path.DirEntry`].
DirEntry : Path.DirEntry

## Lists the files and directories inside the directory.
##
## > [Path.listDir!] does the same thing, except it takes a [Path] instead of a [Str].
list! : Str => Result (List Path) [DirErr Err]
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
deleteEmpty! : Str => Result {} [DirErr Err]
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
deleteAll! : Str => Result {} [DirErr Err]
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
create! : Str => Result {} [DirErr Err]
create! = \path ->
    Path.createDir! (Path.fromStr path)

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
##
## > [Path.createAll!] does the same thing, except it takes a [Path] instead of a [Str].
createAll! : Str => Result {} [DirErr Err]
createAll! = \path ->
    Path.createAll! (Path.fromStr path)
