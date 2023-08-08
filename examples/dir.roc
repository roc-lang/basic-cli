app "dir"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Dir.{ MakeErr },
        pf.Path,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main : Task {} I32
main =

    # Create a directory
    createShouldSucceed <- Task.attempt (Dir.create (Path.fromStr "e"))
    expect
        createShouldSucceed == Ok {}

    # Create a directory and its parents
    createAllShouldSucceed <- Task.attempt (Dir.createAll (Path.fromStr "a/b/c/child"))
    expect
        createAllShouldSucceed == Ok {}

    # Create a child directory
    createChildShouldSucceed <- Task.attempt (Dir.create (Path.fromStr "a/child"))
    expect
        createChildShouldSucceed == Ok {}

    # Try to create a directory without a parent
    createWithoutParentShouldFail <- Task.attempt (Dir.create (Path.fromStr "d/child"))
    expect
        createWithoutParentShouldFail == Err NotFound

    # Delete an empty directory
    _ <-
        Task.attempt (Dir.deleteEmpty (Path.fromStr "e")) \removeChild ->
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
