app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Path

main! = \{} ->

    # Create a directory
    Dir.create!? "dirExampleE"

    # Create a directory and its parents
    Dir.create_all!? "dirExampleA/b/c/child"

    # Create a child directory
    Dir.create!? "dirExampleA/child"

    # List the contents of a directory
    paths_as_str =
        Dir.list! "dirExampleA"
        |> Result.map? \paths -> List.map paths Path.display

    # Check the contents of the directory
    expect (Set.fromList paths_as_str) == (Set.fromList ["dirExampleA/b", "dirExampleA/child"])

    # Try to create a directory without a parent (should fail, ignore error)
    when Dir.create! "dirExampleD/child" is
        Ok {} -> {}
        Err _ -> {}

    # Delete an empty directory
    Dir.delete_empty!? "dirExampleE"

    # Delete all directories recursively
    Dir.delete_all!? "dirExampleA"

    Stdout.line! "Success!"
