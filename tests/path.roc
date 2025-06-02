app [main!] { 
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br",
}

import pf.Stdout
import pf.Stderr
import pf.Path
import pf.Arg exposing [Arg]
import pf.Cmd
import json.Json

main! : List Arg => Result {} _
main! = |_args|
    Stdout.line!(
        """
        Testing Path functions...
        This will create and manipulate test files and directories in the current directory.
        
        """
    )?

    # Test path creation
    test_path_creation!({})?
    
    # Test file operations
    test_file_operations!({})?
    
    # Test directory operations
    test_directory_operations!({})?
    
    # Test hard link creation
    test_hard_link!({})?

    Stdout.line!("\n✓ All Path function tests completed! ✓")

test_path_creation! : {} => Result {} _
test_path_creation! = |{}|
    Stdout.line!("Testing Path.from_bytes and Path.with_extension:")?

    # Test Path.from_bytes
    path_bytes = [116, 101, 115, 116, 95, 112, 97, 116, 104] # "test_path" in bytes
    path_from_bytes = Path.from_bytes(path_bytes)
    expected_str = "test_path"
    actual_str = Path.display(path_from_bytes)
    
    # Test Path.with_extension
    base_path = Path.from_str("test_file")
    path_with_ext = Path.with_extension(base_path, "txt")
    
    path_with_dot = Path.from_str("test_file.")
    path_dot_ext = Path.with_extension(path_with_dot, "json")
    
    path_replace_ext = Path.from_str("test_file.old")
    path_new_ext = Path.with_extension(path_replace_ext, "new")

    Stdout.line!(
        """
        Created path from bytes: ${Path.display(path_from_bytes)}
        Path.from_bytes result matches expected: ${Inspect.to_str(actual_str == expected_str)}
        Path with extension: ${Path.display(path_with_ext)}
        Extension added correctly: ${Inspect.to_str(Path.display(path_with_ext) == "test_file.txt")}
        Path with dot and extension: ${Path.display(path_dot_ext)}
        Extension after dot: ${Inspect.to_str(Path.display(path_dot_ext) == "test_file.json")}
        Path with replaced extension: ${Path.display(path_new_ext)}
        Extension replaced: ${Inspect.to_str(Path.display(path_new_ext) == "test_file.new")}
        """
    )?

    Ok({})

test_file_operations! : {} => Result {} _
test_file_operations! = |{}|
    Stdout.line!("\nTesting Path file operations:")?

    # Test Path.write_bytes! and Path.read_bytes!
    test_bytes = [72, 101, 108, 108, 111, 44, 32, 80, 97, 116, 104, 33] # "Hello, Path!" in bytes
    bytes_path = Path.from_str("test_path_bytes.txt")
    Path.write_bytes!(test_bytes, bytes_path)?
    
    # Verify file exists using ls
    ls_output = Cmd.new("ls") |> Cmd.args(["-la", "test_path_bytes.txt"]) |> Cmd.output!()
    ls_stdout = Str.from_utf8(ls_output.stdout) ? |_| LsInvalidUtf8
    
    read_bytes = Path.read_bytes!(bytes_path)?
    
    Stdout.line!(
        """
        File created: ${ls_stdout}
        Bytes written: ${Inspect.to_str(test_bytes)}
        Bytes read: ${Inspect.to_str(read_bytes)}
        Bytes match: ${Inspect.to_str(test_bytes == read_bytes)}
        """
    )?

    # Test Path.write_utf8! and Path.read_utf8!
    utf8_content = "Hello from Path module! 🚀"
    utf8_path = Path.from_str("test_path_utf8.txt")
    Path.write_utf8!(utf8_content, utf8_path)?
    
    # Check file content with cat
    cat_output = Cmd.new("cat") |> Cmd.args(["test_path_utf8.txt"]) |> Cmd.output!()
    cat_stdout = Str.from_utf8(cat_output.stdout) ? |_| CatInvalidUtf8
    
    read_utf8 = Path.read_utf8!(utf8_path)?
    
    Stdout.line!(
        """
        File content via cat: ${cat_stdout}
        UTF-8 written: ${utf8_content}
        UTF-8 read: ${read_utf8}
        UTF-8 content matches: ${Inspect.to_str(utf8_content == read_utf8)}
        """
    )?

    # Test Path.write! with JSON encoding
    json_data = { message: "Path test", numbers: [1, 2, 3] }
    json_path = Path.from_str("test_path_json.json")
    Path.write!(json_data, json_path, Json.utf8)?
    
    json_content = Path.read_utf8!(json_path)?
    
    # Verify it's valid JSON by checking it contains expected fields
    contains_message = Str.contains(json_content, "\"message\"")
    contains_numbers = Str.contains(json_content, "\"numbers\"")
    
    Stdout.line!(
        """
        JSON content: ${json_content}
        JSON contains 'message' field: ${Inspect.to_str(contains_message)}
        JSON contains 'numbers' field: ${Inspect.to_str(contains_numbers)}
        """
    )?

    # Test Path.delete!
    delete_path = Path.from_str("test_to_delete.txt")
    Path.write_utf8!("This file will be deleted", delete_path)?
    
    # Verify file exists before deletion
    ls_before = Cmd.new("ls") |> Cmd.args(["test_to_delete.txt"]) |> Cmd.output!() 

    Stdout.line!("hey")?
    
    Path.delete!(delete_path) ? |err| DeleteFailed(err)

    Stdout.line!("yo")?
    
    # Verify file is gone after deletion
    ls_after = Cmd.new("ls") |> Cmd.args(["test_to_delete.txt"]) |> Cmd.output!()

    Stdout.line!("after")?
    
    Stdout.line!(
        """
        File exists before delete: ${Inspect.to_str(ls_before.status? == 0)}
        File exists after delete: ${Inspect.to_str(ls_after.status? == 0)}
        ✓ Successfully deleted test file
        """
    )?

    Ok({})

test_directory_operations! : {} => Result {} _
test_directory_operations! = |{}|
    Stdout.line!("\nTesting Path directory operations:")?

    # Test Path.create_dir!
    single_dir = Path.from_str("test_single_dir")
    Path.create_dir!(single_dir)?
    
    # Verify directory exists
    ls_dir = Cmd.new("ls") |> Cmd.args(["-ld", "test_single_dir"]) |> Cmd.output!()
    ls_dir_stdout = Str.from_utf8(ls_dir.stdout) ? |_| LsDirInvalidUtf8
    is_dir = Str.starts_with(ls_dir_stdout, "d")
    
    Stdout.line!(
        """
        Created directory: ${ls_dir_stdout}
        Is directory (starts with 'd'): ${Inspect.to_str(is_dir)}
        """
    )?

    # Test Path.create_all! (nested directories)
    nested_dir = Path.from_str("test_parent/test_child/test_grandchild")
    Path.create_all!(nested_dir)?
    
    # Verify nested structure with tree or find
    find_output = Cmd.new("find") |> Cmd.args(["test_parent", "-type", "d"]) |> Cmd.output!()
    find_stdout = Str.from_utf8(find_output.stdout) ? |_| FindInvalidUtf8
    
    # Count directories created
    dir_count = Str.split_on(find_stdout, "\n") |> List.len
    
    Stdout.line!(
        """
        Nested directory structure:
        ${find_stdout}
        Number of directories created: ${Num.to_str(dir_count - 1)}
        """
    )?

    # Create some files in the directory for testing
    Path.write_utf8!("File 1", Path.from_str("test_single_dir/file1.txt"))?
    Path.write_utf8!("File 2", Path.from_str("test_single_dir/file2.txt"))?
    Path.create_dir!(Path.from_str("test_single_dir/subdir"))?
    
    # List directory contents
    ls_contents = Cmd.new("ls") |> Cmd.args(["-la", "test_single_dir"]) |> Cmd.output!()
    ls_contents_stdout = Str.from_utf8(ls_contents.stdout) ? |_| LsContentsInvalidUtf8
    
    Stdout.line!(
        """
        Directory contents:
        ${ls_contents_stdout}
        """
    )?

    # Test Path.delete_empty!
    empty_dir = Path.from_str("test_empty_dir")
    Path.create_dir!(empty_dir)?
    
    # Verify it exists
    ls_empty_before = Cmd.new("ls") |> Cmd.args(["-ld", "test_empty_dir"]) |> Cmd.output!()
    
    Path.delete_empty!(empty_dir)?
    
    # Verify it's gone
    ls_empty_after = Cmd.new("ls") |> Cmd.args(["-ld", "test_empty_dir"]) |> Cmd.output!()
    
    Stdout.line!(
        """
        Empty dir exists before delete: ${Inspect.to_str(ls_empty_before.status? == 0)}
        Empty dir exists after delete: ${Inspect.to_str(ls_empty_after.status? == 0)}
        """
    )?

    # Test Path.delete_all!
    # First show what we're about to delete
    du_output = Cmd.new("du") |> Cmd.args(["-sh", "test_parent"]) |> Cmd.output!()
    du_stdout = Str.from_utf8(du_output.stdout) ? |_| DuInvalidUtf8
    
    Path.delete_all!(Path.from_str("test_parent"))?
    
    # Verify it's gone
    ls_parent_after = Cmd.new("ls") |> Cmd.args(["test_parent"]) |> Cmd.output!()
    
    Stdout.line!(
        """
        Size before delete_all: ${du_stdout}
        Parent dir exists after delete_all: ${Inspect.to_str(ls_parent_after.status? == 0)}
        ✓ Recursively deleted directory tree
        """
    )?

    # Clean up remaining test directory
    Path.delete_all!(single_dir)?

    Ok({})

test_hard_link! : {} => Result {} _
test_hard_link! = |{}|
    Stdout.line!("\nTesting Path.hard_link!:")?
    
    # Create original file
    original_path = Path.from_str("test_path_original.txt")
    Path.write_utf8!("Original content for Path hard link test", original_path)?
    
    # Get original file stats
    stat_before = Cmd.new("stat") |> Cmd.args(["-c", "%h", "test_path_original.txt"]) |> Cmd.output!()
    links_before = Str.from_utf8(stat_before.stdout) ? |_| StatBeforeInvalidUtf8
    
    # Create hard link
    link_path = Path.from_str("test_path_hardlink.txt")
    when Path.hard_link!(original_path, link_path) is
        Ok({}) ->
            # Get link count after
            stat_after = Cmd.new("stat") |> Cmd.args(["-c", "%h", "test_path_original.txt"]) |> Cmd.output!()
            links_after = Str.from_utf8(stat_after.stdout) ? |_| StatAfterInvalidUtf8

            # Verify both files exist and have same content
            original_content = Path.read_utf8!(original_path)?
            link_content = Path.read_utf8!(link_path)?
            
            Stdout.line!(
                """
                ✓ Successfully created hard link
                Hard link count before: ${Str.trim(links_before)}
                Hard link count after: ${Str.trim(links_after)}
                Original content: ${original_content}
                Link content: ${link_content}
                Content matches: ${Inspect.to_str(original_content == link_content)}
                """
            )?

            # Check inodes are the same
            ls_li_output =
                Cmd.new("ls")
                |> Cmd.args(["-li", "test_path_original.txt", "test_path_hardlink.txt"])
                |> Cmd.output!()

            ls_li_stdout_utf8 = Str.from_utf8(ls_li_output.stdout) ? |_| LsLiInvalidUtf8

            inodes =
                Str.split_on(ls_li_stdout_utf8, "\n")
                |> List.map(|line| 
                                Str.split_on(line, " ")
                                |> List.take_first(1)
                            )

            first_inode = List.get(inodes, 0) ? |_| FirstInodeNotFound
            second_inode = List.get(inodes, 1) ? |_| SecondInodeNotFound

            Stdout.line!(
                """
                Inode information:
                ${ls_li_stdout_utf8}
                First file inode: ${Inspect.to_str(first_inode)}
                Second file inode: ${Inspect.to_str(second_inode)}
                Inodes are equal: ${Inspect.to_str(first_inode == second_inode)}
                """
            )?
        
        Err(err) ->
            Stderr.line!("✗ Hard link creation failed: ${Inspect.to_str(err)}")?

    # Clean up test files
    cleanup_test_files!({})

cleanup_test_files! : {} => Result {} _
cleanup_test_files! = |{}|
    Stdout.line!("\nCleaning up test files...")?
    
    test_files = [
        "test_path_bytes.txt",
        "test_path_utf8.txt",
        "test_path_json.json",
        "test_path_original.txt",
        "test_path_hardlink.txt"
    ]

    # Show files before cleanup
    ls_before_cleanup = Cmd.new("ls") |> Cmd.args(["-la"] |> List.concat(test_files)) |> Cmd.output!()
    
    if ls_before_cleanup.status? == 0 then
        cleanup_stdout = Str.from_utf8(ls_before_cleanup.stdout) ? |_| CleanupInvalidUtf8
        
        Stdout.line!(
            """
            Files to clean up:
            ${cleanup_stdout}
            """
        )?

        List.for_each_try!(test_files, |filename| 
            Path.delete!(Path.from_str(filename))
        )?
        
        # Verify cleanup
        ls_after_cleanup = Cmd.new("ls") |> Cmd.args(test_files) |> Cmd.output!()
        
        Stdout.line!(
            """
            Files remaining after cleanup: ${Inspect.to_str(ls_after_cleanup.status? == 0)}
            ✓ Deleted all test files.
            """
        )
    else
        Stderr.line!("✗ Error listing files before cleanup: `ls -la ...` exited with non-zero exit code:\n\t${Inspect.to_str(ls_before_cleanup)}")