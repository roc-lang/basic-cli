interface Dir
    exposes [
        IOError, 
        DirEntry, 
        list,
        create,
        createRecursive,
        deleteEmptyDir, 
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
## This may fail if the path doesn't exist or is not a directory, the directory 
## is not empty, the user lacks permission to remove a directory. 
deleteEmptyDir : Path -> Task {} IOError
deleteEmptyDir = \path ->
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
## This may fail if the path doesn't exist or is not a directory, the directory 
## is not empty, the user lacks permission to remove a directory.
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
## This may fail if a parent directory does not exist, or user lacks permission
## to create a directory, or the path already exists.
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
## This may fail if user lacks permission to create a directory, or the 
## path already exists.
createRecursive : Path -> Task {} IOError
createRecursive = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreateAll
    |> Effect.map \result ->
        when result is
            Ok {} -> Ok {}
            Err AddrInUse -> Ok {} # TODO investigate why we need this here
            Err err -> Err err
    |> InternalTask.fromEffect