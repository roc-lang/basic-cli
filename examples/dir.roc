app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Path

main! = \_args ->

    # Create a directory
    try Dir.create! "dirExampleE"

    # Create a directory and its parents
    try Dir.createAll! "dirExampleA/b/c/child"

    # Create a child directory
    try Dir.create! "dirExampleA/child"

    # List the contents of a directory
    pathsAsStr =
        Dir.list! "dirExampleA"
        |> Result.map \paths -> List.map paths Path.display
        |> try

    # Check the contents of the directory
    expect (Set.fromList pathsAsStr) == (Set.fromList ["dirExampleA/b", "dirExampleA/child"])

    # Try to create a directory without a parent (should fail, ignore error)
    when Dir.create! "dirExampleD/child" is
        Ok {} -> {}
        Err _ -> {}

    # Delete an empty directory
    try Dir.deleteEmpty! "dirExampleE"

    # Delete all directories recursively
    try Dir.deleteAll! "dirExampleA"

    Stdout.line! "Success!"
