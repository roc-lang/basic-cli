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
        FileMetadata.{ FileMetadata },
    ]

## **NotFound** - This error is raised when the specified directory does not exist, typically during attempts to access or manipulate it.
##
## **PermissionDenied** - Occurs when the user lacks the necessary permissions to perform an action on a directory, such as reading, writing, or executing.
##
## **AlreadyExists** - This error is thrown when trying to create a directory that already exists.
##
## **NotADirectory** - Raised when an operation that requires a directory (e.g., listing contents) is attempted on a file instead.
##
## **Other** - A catch-all for any other types of errors not explicitly listed above.
Err : [
    NotFound,
    PermissionDenied,
    AlreadyExists,
    NotADirectory,
    Other Str,
]

# There are othe errors which may be useful, however they are currently unstable
# features see https://github.com/rust-lang/rust/issues/86442
# TODO add these when available
# ErrorKind::NotADirectory => RocStr::from("ErrorKind::NotADirectory"),
# ErrorKind::IsADirectory => RocStr::from("ErrorKind::IsADirectory"),
# ErrorKind::DirectoryNotEmpty => RocStr::from("ErrorKind::DirectoryNotEmpty"),
# ErrorKind::ReadOnlyFilesystem => RocStr::from("ErrorKind::ReadOnlyFilesystem"),
# ErrorKind::FilesystemLoop => RocStr::from("ErrorKind::FilesystemLoop"),
# ErrorKind::FilesystemQuotaExceeded => RocStr::from("ErrorKind::FilesystemQuotaExceeded"),
# ErrorKind::StorageFull => RocStr::from("ErrorKind::StorageFull"),
# ErrorKind::InvalidFilename => RocStr::from("ErrorKind::InvalidFilename"),
handleErr = \err ->
    when err is 
        e if e == "ErrorKind::NotFound" -> DirErr NotFound
        e if e == "ErrorKind::PermissionDenied" -> DirErr PermissionDenied
        e if e == "ErrorKind::AlreadyExists" -> DirErr AlreadyExists
        e if e == "ErrorKind::NotADirectory" -> DirErr NotADirectory
        str -> DirErr (Other str)

## Record which represents a directory
DirEntry : {
    path : Path,
    type : [File, Dir, Symlink],
    metadata : FileMetadata,
}

## Lists the files and directories inside the directory.
list : Path -> Task (List Path) [DirErr Err]
list = \path ->
    InternalPath.toBytes path
    |> Effect.dirList
    |> Effect.map \result ->
        when result is
            Ok entries -> Ok (List.map entries InternalPath.fromOsBytes)
            Err err -> Err (handleErr err)
    |> InternalTask.fromEffect

## Deletes a directory if it's empty
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
deleteEmpty : Path -> Task {} [DirErr Err]
deleteEmpty = \path ->
    InternalPath.toBytes path
    |> Effect.dirDeleteEmpty
    |> Effect.map \res -> Result.mapErr res handleErr
    |> InternalTask.fromEffect

## Recursively deletes the directory as well as all files and directories
## inside it.
##
## This may fail if:
##   - the path doesn't exist
##   - the path is not a directory
##   - the directory is not empty
##   - the user lacks permission to remove the directory.
deleteAll : Path -> Task {} [DirErr Err]
deleteAll = \path ->
    InternalPath.toBytes path
    |> Effect.dirDeleteAll
    |> Effect.map \res -> Result.mapErr res handleErr
    |> InternalTask.fromEffect

## Creates a directory
##
## This may fail if:
##   - a parent directory does not exist
##   - the user lacks permission to create a directory there
##   - the path already exists.
create : Path -> Task {} [DirErr Err]
create = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreate
    |> Effect.map \res -> Result.mapErr res handleErr
    |> InternalTask.fromEffect

## Creates a directory recursively adding any missing parent directories.
##
## This may fail if:
##   - the user lacks permission to create a directory there
##   - the path already exists
createAll : Path -> Task {} [DirErr Err]
createAll = \path ->
    InternalPath.toBytes path
    |> Effect.dirCreateAll
    |> Effect.map \res -> Result.mapErr res handleErr
    |> InternalTask.fromEffect