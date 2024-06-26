app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Path
import pf.Task exposing [Task]

main =

    # Create a directory
    Dir.create "dirExampleE"
        |> Task.mapErr! UnableToCreateFirstDir
    # Create a directory and its parents
    Dir.createAll "dirExampleA/b/c/child"
        |> Task.mapErr! UnableToCreateSubDirs
    # Create a child directory
    Dir.create "dirExampleA/child"
        |> Task.mapErr! UnableToCreateChildDir

    # List the contents of a directory
    paths =
        "dirExampleA"
            |> Dir.list
            |> Task.mapErr! FailedToListDir

    pathsAsStr = List.map paths Path.display

    # Check the contents of the directory
    expect pathsAsStr == ["dirExampleA/child", "dirExampleA/b"]
    # Try to create a directory without a parent (should fail, ignore error)
    Dir.create "dirExampleD/child"
        |> Task.onErr! \_ -> Task.ok {}
    # Delete an empty directory
    Dir.deleteEmpty "dirExampleE"
        |> Task.mapErr! UnableToDeleteEmptyDirectory
    # Delete all directories recursively
    Dir.deleteAll "dirExampleA"
        |> Task.mapErr! UnableToDeleteRecursively
    Stdout.line! "Success!"
