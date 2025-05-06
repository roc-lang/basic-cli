app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir
import pf.Path
import pf.File
import pf.Arg exposing [Arg]

# Demo of all Dir functions.

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|

    # Create a directory
    Dir.create!("empty-dir")?

    dir_exists = File.is_dir!("empty-dir")?
    expect dir_exists

    # Create a directory and its parents
    Dir.create_all!("nested-dir/a/b/c")?

    # Create a child directory
    Dir.create!("nested-dir/child")?

    # List the contents of a directory
    paths_as_str =
        Dir.list!("nested-dir")
        |> Result.map_ok(|paths| List.map(paths, Path.display))?

    # Check the contents of the directory
    expect Set.from_list(paths_as_str) == Set.from_list(["nested-dir/a", "nested-dir/child"])

    # Delete an empty directory
    Dir.delete_empty!("empty-dir")?

    # Delete all directories recursively
    Dir.delete_all!("nested-dir")?

    Stdout.line!("Success!")
