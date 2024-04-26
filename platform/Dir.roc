interface Dir
    exposes [
        DirEntry,
        Err,
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
        FileMetadata.{ FileMetadata },
    ]

## Tag union of possible errors
Err : InternalDir.IOError

## Record which represents a directory
DirEntry : {
    path : Path,
    type : [File, Dir, Symlink],
    metadata : FileMetadata,
}

## Lists the files and directories inside the directory.
list : Path -> Task (List Path) [DirError Err]
list = \path ->
    InternalPath.toBytes path
    |> Effect.dirList
    |> Effect.map \result ->
        when result is
            Ok entries -> Ok (List.map entries InternalPath.fromOsBytes)
            Err err -> Err err
    |> InternalTask.fromEffect
    |> Task.mapErr DirError

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
deleteEmpty : Path -> Task {} [DirError Err]
deleteEmpty = \path ->
    InternalPath.toBytes path
    |> Effect.dirDeleteEmpty
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect
    |> Task.mapErr DirError

## Recursively deletes the directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
deleteAll : Path -> Task {} [DirError Err]
deleteAll = \path ->
    InternalPath.toBytes path
    |> Effect.dirDeleteAll
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect
    |> Task.mapErr DirError

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
create : Path -> Task {} [DirError Err]
create = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreate
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect
    |> Task.mapErr DirError

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
createAll : Path -> Task {} [DirError Err]
createAll = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreateAll
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect
    |> Task.mapErr DirError