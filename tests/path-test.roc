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
    when run_tests!({}) is
        Ok(_) ->
            cleanup_test_files!(FilesNeedToExist)
        Err(err) ->
            _ = cleanup_test_files!(FilesMaybeExist)
            Err(Exit(1, "Test run failed:\n\t${Inspect.to_str(err)}"))

run_tests!: {} => Result {} _
run_tests! = |{}|
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

    # Test file rename
    test_path_rename!({})?

    # Test path exists
    test_path_exists!({})?

    Stdout.line!("\nI ran all Path function tests.")

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
    
    # Verify file exists
    _ = Cmd.exec!("test", ["-e", "test_path_bytes.txt"])?
    
    read_bytes = Path.read_bytes!(bytes_path)?
    
    Stdout.line!(
        """
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
    cat_output = Cmd.new("cat") |> Cmd.args(["test_path_utf8.txt"]) |> Cmd.exec_output!()?
    
    read_utf8 = Path.read_utf8!(utf8_path)?
    
    Stdout.line!(
        """
        File content via cat: ${cat_output.stdout_utf8}
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
    _ = Cmd.exec!("test", ["-e", "test_to_delete.txt"])?

    Path.delete!(delete_path) ? DeleteFailed
    
    # Verify file is gone after deletion
    exists_after_res = Cmd.exec!("test", ["-e", "test_to_delete.txt"])
    
    Stdout.line!(
        """
        File no longer exists: ${Inspect.to_str(Result.is_err(exists_after_res))}
        """
    )?

    Ok({})

test_directory_operations! : {} => Result {} _
test_directory_operations! = |{}|
    Stdout.line!("\nTesting Path directory operations...")?

    # Test Path.create_dir!
    single_dir = Path.from_str("test_single_dir")
    Path.create_dir!(single_dir)?
    
    # Verify directory exists
    _ = Cmd.exec!("test", ["-d", "test_single_dir"])?

    # Test Path.create_all! (nested directories)
    nested_dir = Path.from_str("test_parent/test_child/test_grandchild")
    Path.create_all!(nested_dir)?
    
    # Verify nested structure with find
    find_output = Cmd.new("find") |> Cmd.args(["test_parent", "-type", "d"]) |> Cmd.exec_output!()?
    
    # Count directories created
    dir_count = Str.split_on(find_output.stdout_utf8, "\n") |> List.len
    
    Stdout.line!(
        """
        Nested directory structure:
        ${find_output.stdout_utf8}
        Number of directories created: ${Num.to_str(dir_count - 1)}
        """
    )?

    # Create some files in the directory for testing
    Path.write_utf8!("File 1", Path.from_str("test_single_dir/file1.txt"))?
    Path.write_utf8!("File 2", Path.from_str("test_single_dir/file2.txt"))?
    Path.create_dir!(Path.from_str("test_single_dir/subdir"))?
    
    # List directory contents
    ls_contents = Cmd.new("ls") |> Cmd.args(["-la", "test_single_dir"]) |> Cmd.exec_output!()?
    
    Stdout.line!(
        """
        Directory contents:
        ${ls_contents.stdout_utf8}
        """
    )?

    # Test Path.delete_empty!
    empty_dir = Path.from_str("test_empty_dir")
    Path.create_dir!(empty_dir)?
    
    # Verify it exists
    _ = Cmd.exec!("test", ["-e", "test_empty_dir"])?
    
    Path.delete_empty!(empty_dir)?
    
    # Verify it's gone
    exists_after_res = Cmd.exec!("test", ["-e", "test_empty_dir"])
    
    Stdout.line!(
        """
        Empty dir was deleted: ${Inspect.to_str(Result.is_err(exists_after_res))}
        """
    )?

    # Test Path.delete_all!
    # First show what we're about to delete
    du_output = Cmd.new("du") |> Cmd.args(["-sh", "test_parent"]) |> Cmd.exec_output!()?
    
    Path.delete_all!(Path.from_str("test_parent"))?
    
    # Verify it's gone
    parent_exists_afer_res = Cmd.exec!("test", ["-e", "test_parent"])
    
    Stdout.line!(
        """
        Size before delete_all: ${du_output.stdout_utf8}
        Parent dir no longer exists: ${Inspect.to_str(Result.is_err(parent_exists_afer_res))}
        """
    )?

    # Clean up other test directory
    Path.delete_all!(single_dir)?

    Ok({})

get_hard_link_count! : Str => Result Str _
get_hard_link_count! = |path_str|
    ls_l =
        Cmd.new("ls")
        |> Cmd.args(["-l", path_str])
        |> Cmd.exec_output!()?

    hard_link_count_str =
        (ls_l.stdout_utf8
        |> Str.split_on(" ")
        |> List.keep_if(|str| !Str.is_empty(str))
        |> List.get(1)) ? |_| IExpectedALineWithASpaceHere(ls_l)

    Ok(hard_link_count_str)

test_hard_link! : {} => Result {} _
test_hard_link! = |{}|
    Stdout.line!("\nTesting Path.hard_link!:")?
    
    # Create original file
    original_path = Path.from_str("test_path_original.txt")
    Path.write_utf8!("Original content for Path hard link test", original_path)?
    
    hard_link_count_before = get_hard_link_count!("test_path_original.txt")?
    
    # Create hard link
    link_path = Path.from_str("test_path_hardlink.txt")
    when Path.hard_link!(original_path, link_path) is
        Ok({}) ->
            # Get link count after
            hard_link_count_after = get_hard_link_count!("test_path_original.txt")?

            # Verify both files exist and have same content
            original_content = Path.read_utf8!(original_path)?
            link_content = Path.read_utf8!(link_path)?
            
            Stdout.line!(
                """
                Hard link count before: ${hard_link_count_before}
                Hard link count after: ${hard_link_count_after}
                Original content: ${original_content}
                Link content: ${link_content}
                Content matches: ${Inspect.to_str(original_content == link_content)}
                """
            )?

            # Check inodes are the same
            ls_li_output =
                Cmd.new("ls")
                |> Cmd.args(["-li", "test_path_original.txt", "test_path_hardlink.txt"])
                |> Cmd.exec_output!()?

            inodes =
                Str.split_on(ls_li_output.stdout_utf8, "\n")
                |> List.map(|line| 
                                Str.split_on(line, " ")
                                |> List.take_first(1)
                            )

            first_inode = List.get(inodes, 0) ? |_| FirstInodeNotFound
            second_inode = List.get(inodes, 1) ? |_| SecondInodeNotFound

            Stdout.line!(
                """
                Inode information:
                ${ls_li_output.stdout_utf8}
                First file inode: ${Inspect.to_str(first_inode)}
                Second file inode: ${Inspect.to_str(second_inode)}
                Inodes are equal: ${Inspect.to_str(first_inode == second_inode)}
                """
            )
        
        Err(err) ->
            Stderr.line!("✗ Hard link creation failed: ${Inspect.to_str(err)}")

test_path_rename! : {} => Result {} _
test_path_rename! = |{}|
    Stdout.line!("\nTesting Path.rename!:")?
    
    # Create original file
    original_path = Path.from_str("test_path_rename_original.txt")
    new_path = Path.from_str("test_path_rename_new.txt")
    test_file_content = "Content for rename test."

    Path.write_utf8!(test_file_content, original_path) ? WriteOriginalFailed
    
    # Rename the file
    when Path.rename!(original_path, new_path) is
        Ok({}) ->
            original_file_exists_after =                                                                      
                  when Path.is_file!(original_path) is                                                     
                      Ok(exists) -> exists                                                                 
                      Err(_) -> Bool.false
            
            if original_file_exists_after then
                Stderr.line!("✗ Original file still exists after rename")?
            else
                Stdout.line!("✓ Original file no longer exists")?
            
            new_file_exists = Path.is_file!(new_path) ? NewIsFileFailed

            if new_file_exists then
                Stdout.line!("✓ Renamed file exists")?
                
                content = Path.read_utf8!(new_path) ? NewFileReadFailed

                if content == test_file_content then
                    Stdout.line!("✓ Renamed file has correct content")
                else
                    Stderr.line!("✗ Renamed file has incorrect content")
            else
                Stderr.line!("✗ Renamed file does not exist")
        
        Err(err) ->
            Stderr.line!("✗ File rename failed: ${Inspect.to_str(err)}")

test_path_exists! : {} => Result {} _
test_path_exists! = |{}|
    Stdout.line!("\nTesting Path.exists!:")?
    
    # Test that a file that exists returns true
    filename = Path.from_str("test_path_exists.txt")
    Path.write_utf8!("This file exists", filename)?

    file_exists = Path.exists!(filename) ? PathExistsCheckFailed

    if file_exists then 
        Stdout.line!("✓ Path.exists! returns true for a file that exists")?
    else
        Stderr.line!("✗ Path.exists! returned false for a file that exists")?

    # Test that a file that does not exist returns false
    Path.delete!(filename)?

    file_exists_after_delete = Path.exists!(filename) ? PathExistsCheckAfterDeleteFailed

    if file_exists_after_delete then
        Stderr.line!("✗ Path.exists! returned true for a file that does not exist")?
    else
        Stdout.line!("✓ Path.exists! returns false for a file that does not exist")?

    Ok({})

cleanup_test_files! : [FilesNeedToExist, FilesMaybeExist] => Result {} _
cleanup_test_files! = |files_requirement|
    Stdout.line!("\nCleaning up test files...")?
    
    test_files = [
        "test_path_bytes.txt",
        "test_path_utf8.txt",
        "test_path_json.json",
        "test_path_original.txt",
        "test_path_hardlink.txt",
        "test_path_rename_new.txt"
    ]

    # Show files before cleanup
    ls_before_cleanup = Cmd.new("ls") |> Cmd.args(["-la"] |> List.concat(test_files)) |> Cmd.exec_output!()?
    
    Stdout.line!(
        """
        Files to clean up:
        ${ls_before_cleanup.stdout_utf8}
        """
    )?

    delete_result = List.for_each_try!(test_files, |filename| 
        Path.delete!(Path.from_str(filename))
    )

    when files_requirement is
        FilesNeedToExist ->
            delete_result ? FileDeletionFailed
        FilesMaybeExist ->
            Ok({})?
    
    # Verify cleanup
    ls_after_cleanup_res = Cmd.exec!("ls", test_files)
    
    Stdout.line!(
        """
        Files deleted successfully: ${Inspect.to_str(Result.is_err(ls_after_cleanup_res))}
        """
    )
