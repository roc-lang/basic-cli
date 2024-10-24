app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Path

main! =

    # Create a directory
    Dir.create! "dirExampleE"
    |> Result.mapErr? UnableToCreateFirstDir

    # Create a directory and its parents
    Dir.createAll! "dirExampleA/b/c/child"
    |> Result.mapErr? UnableToCreateSubDirs

    # Create a child directory
    Dir.create! "dirExampleA/child"
    |> Result.mapErr? UnableToCreateChildDir

    # List the contents of a directory
    paths =
        Dir.list! "dirExampleA"
        |> Result.mapErr? FailedToListDir

    pathsAsStr = List.map paths Path.display

    # Check the contents of the directory
    expect (Set.fromList pathsAsStr) == (Set.fromList ["dirExampleA/b", "dirExampleA/child"])

    # Try to create a directory without a parent (should fail, ignore error)
    Dir.create! "dirExampleD/child"
    |> Result.onErr? \_ -> Ok {}

    # Delete an empty directory
    Dir.deleteEmpty! "dirExampleE"
    |> Result.mapErr? UnableToDeleteEmptyDirectory

    # Delete all directories recursively
    Dir.deleteAll! "dirExampleA"
    |> Result.mapErr? UnableToDeleteRecursively

    Stdout.line! "Success!"
