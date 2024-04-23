app "dir"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Dir.{ MakeErr },
        pf.Path,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main =

    # Create a directory
    createShouldSucceed = Dir.create (Path.fromStr "e") |> Task.result!
    expect
        createShouldSucceed == Ok {}

    # Create a directory and its parents
    createAllShouldSucceed = Dir.createAll (Path.fromStr "a/b/c/child") |> Task.result!
    expect
        createAllShouldSucceed == Ok {}

    # Create a child directory
    createChildShouldSucceed = Dir.create (Path.fromStr "a/child") |> Task.result!
    expect
        createChildShouldSucceed == Ok {}

    # List the contents of a directory
    paths =
        Path.fromStr "a"
        |> Dir.list
        |> Task.onErr! \_ -> crash "Failed to list directory"

    # Check the contents of the directory
    expect
        (List.map paths Path.display) == ["b", "child"]

    # Try to create a directory without a parent
    createWithoutParentShouldFail = Dir.create (Path.fromStr "d/child") |> Task.result!
    expect
        createWithoutParentShouldFail == Err NotFound

    # Delete an empty directory
    _ <-
        Dir.deleteEmpty (Path.fromStr "e") |> Task.attempt \removeChild ->
            when removeChild is
                Ok _ -> Task.ok {}
                Err err ->
                    dbg
                        err

                    Stderr.line "Failed to delete an empty directory"
        |> Task.await

    # Delete all directories recursively
    _ <-
        Task.attempt (Dir.deleteAll (Path.fromStr "a")) \removeChild ->
            when removeChild is
                Ok _ -> Task.ok {}
                Err err ->
                    dbg
                        err

                    Stderr.line "Failed to delete directory recursively"
        |> Task.await

    Stdout.line "Success!"
