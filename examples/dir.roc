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
    makeShouldSucceed <- Task.attempt (Dir.make (Path.fromStr "e"))
    expect
        makeShouldSucceed == Ok {}

    # Create a directory and its parents
    makeRecursiveShouldSucceed <- Task.attempt (Dir.makeRecursive (Path.fromStr "a/b/c/child"))
    expect
        makeRecursiveShouldSucceed == Ok {}

    # List contents of a directory
    contents <- Task.attempt (Dir.list (Path.fromStr "./src"))
    dbg contents

    # # Create a child directory
    # makeChildShouldSucceed <- Task.attempt (Dir.make (Path.fromStr "a/child"))
    # expect
    #     makeChildShouldSucceed == Ok {}

    # # Try to create a directory without a parent
    # makeWithoutParentShouldFail <- Task.attempt (Dir.make (Path.fromStr "d/child"))
    # expect
    #     makeWithoutParentShouldFail == Err NotFound

    # # Delete an empty directory
    # _ <-
    #     Task.attempt (Dir.deleteEmptyDir (Path.fromStr "e")) \removeChild ->
    #         when removeChild is
    #             Ok _ -> Task.ok {}
    #             Err err ->
    #                 dbg
    #                     err

    #                 Stderr.line "Failed to delete an empty directory"
    #     |> Task.await

    # # Delete all directories recursively
    # _ <-
    #     Task.attempt (Dir.deleteRecursive (Path.fromStr "a")) \removeChild ->
    #         when removeChild is
    #             Ok _ -> Task.ok {}
    #             Err err ->
    #                 dbg
    #                     err

    #                 Stderr.line "Failed to delete directory recursively"
    #     |> Task.await

    Stdout.line "Success!"
