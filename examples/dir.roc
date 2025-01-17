app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.Dir
import pf.Path

main! = |_args|

    # Create a directory
    Dir.create!("dirExampleE")?

    # Create a directory and its parents
    Dir.create_all!("dirExampleA/b/c/child")?

    # Create a child directory
    Dir.create!("dirExampleA/child")?

    # List the contents of a directory
    paths_as_str =
        Dir.list!("dirExampleA")
        |> Result.map_ok(|paths| List.map(paths, Path.display))
        |> try

    # Check the contents of the directory
    expect (Set.from_list(paths_as_str)) == (Set.from_list(["dirExampleA/b", "dirExampleA/child"]))

    # Try to create a directory without a parent (should fail, ignore error)
    when Dir.create!("dirExampleD/child") is
        Ok({}) -> {}
        Err(_) -> {}

    # Delete an empty directory
    Dir.delete_empty!("dirExampleE")?

    # Delete all directories recursively
    Dir.delete_all!("dirExampleA")?

    Stdout.line!("Success!")?

    Ok({})
