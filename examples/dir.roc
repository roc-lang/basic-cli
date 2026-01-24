app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Dir

# Demo of all Dir functions.

main! = |_args| {
    # Create a directory
    Dir.create!("empty-dir")?

    # Create a directory and its parents
    Dir.create_all!("nested-dir/a/b/c")?

    # Create a child directory
    Dir.create!("nested-dir/child")?

    # List the contents of a directory
    paths = Dir.list!("nested-dir")?

    # Check the contents of the directory
    expect List.len(paths) == 2
    expect List.contains(paths, "nested-dir/a")
    expect List.contains(paths, "nested-dir/child")

    # Delete an empty directory
    Dir.delete_empty!("empty-dir")?

    # Delete all directories recursively
    Dir.delete_all!("nested-dir")?

    Stdout.line!("Success!")

    Ok({})
}
