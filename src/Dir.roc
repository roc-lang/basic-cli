interface Dir
    exposes [
        IOError,
        DirEntry,
        list,
        create,
        createAll,
        deleteEmpty,
        deleteAll,
    ]
    imports [
        Effect,
        Task.{ Task },
        InternalTask,
        Path.{ Path },
        InternalPath,
        InternalDir,
    ]

## Tag union of possible errors
IOError : InternalDir.IOError

## Record which represents a directory
DirEntry : InternalDir.DirEntry

## Lists the files and directories inside the directory.
list : Path -> Task (List Path) IOError
list = \path ->
    InternalPath.toBytes path
    |> Effect.dirList
    |> Effect.map \result ->
        when result is
            Ok entries -> Ok (List.map entries InternalPath.fromOsBytes)
            Err err -> Err err
    |> InternalTask.fromEffect

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
deleteEmpty : Path -> Task {} IOError
deleteEmpty = \path ->
    InternalPath.toBytes path
    |> Effect.dirDeleteEmpty
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect

## Recursively deletes the directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
deleteAll : Path -> Task {} IOError
deleteAll = \path ->
    InternalPath.toBytes path
    |> Effect.dirDeleteAll
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
create : Path -> Task {} IOError
create = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreate
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
createAll : Path -> Task {} IOError
createAll = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreateAll
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect
