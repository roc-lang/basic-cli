app "dir"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Dir.{ MakeErr },
        pf.Path,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main : Task {} I32
main =

    # Create a directory
    {} <-
        Path.fromStr "e"
        |> Dir.create
        |> Task.onErr \_ -> crash "Failed to create directory"
        |> Task.await

    # Create a directory and its parents
    {} <-
        Path.fromStr "a/b/c/child"
        |> Dir.createAll
        |> Task.onErr \_ -> crash "Failed to create directory and its parents"
        |> Task.await

    # Create a child directory
    {} <-
        Path.fromStr "a/child"
        |> Dir.create
        |> Task.onErr \_ -> crash "Failed to create child directory a/child"
        |> Task.await

    # List the contents of a directory
    _ <-
        Path.fromStr "a"
        |> Dir.list
        |> Task.onErr \_ -> crash "Failed to list directory"
        |> Task.await

    # List the contents of a directory
    paths <-
        Path.fromStr "a"
        |> Dir.list
        |> Task.onErr \_ -> crash "Failed to list directory"
        |> Task.await

    # Check the contents of the directory
    expect
        (List.map paths Path.display) == ["b", "child"]

    # Try to create a directory without a parent
    {} <-
        Path.fromStr "d/child"
        |> Dir.create
        |> Task.attempt \result ->
            when result is
                Ok {} -> crash "Should return error creating directory without a parent"
                Err _ -> Task.ok {}
        |> Task.await

    # Delete an empty directory
    _ <-
        Path.fromStr "e"
        |> Dir.deleteEmpty
        |> Task.onErr \_ -> crash "Failed to delete an empty directory"
        |> Task.await

    # Delete all directories recursively
    _ <-
        Path.fromStr "a"
        |> Dir.deleteAll
        |> Task.onErr \_ -> crash "Failed to delete directory recursively"
        |> Task.await

    Stdout.line "Success!"
