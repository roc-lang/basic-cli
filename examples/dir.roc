app "dir"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Dir.{ MakeErr },
        pf.Path,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main =

    # Create a directory
    Dir.create (Path.fromStr "dirExampleE") 
    |> Task.mapErr! UnableToCreateFirstDir
    
    # Create a directory and its parents
    Dir.createAll (Path.fromStr "dirExampleA/b/c/child") 
    |> Task.mapErr! UnableToCreateSubDirs

    # Create a child directory
    Dir.create (Path.fromStr "dirExampleA/child") 
    |> Task.mapErr! UnableToCreateChildDir

    # List the contents of a directory
    paths =
        Path.fromStr "dirExampleA"
        |> Dir.list
        |> Task.mapErr! FailedToListDir
    
    # Check the contents of the directory
    expect (List.map paths Path.display) == ["b", "child"]

    # Try to create a directory without a parent (should fail, ignore error)
    Dir.create (Path.fromStr "dirExampleD/child")
    |> Task.onErr! \_ -> Task.ok {}

    # Delete an empty directory
    Dir.deleteEmpty (Path.fromStr "dirExampleE")
    |> Task.mapErr! UnableToDeleteEmptyDirectory
    
    # Delete all directories recursively
    Dir.deleteAll (Path.fromStr "dirExampleA")
    |> Task.mapErr! UnableToDeleteRecursively

    Stdout.line! "Success!"
