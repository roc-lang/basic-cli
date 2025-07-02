app [main!] { 
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br",
}

import pf.Stdout
import pf.Stderr
import pf.File
import pf.Arg exposing [Arg]
import pf.Cmd
import json.Json

main! : List Arg => Result {} _
main! = |_args|
    when run_tests!({}) is
        Ok(_) ->
            cleanup_test_files!(FilesNeedToExist)
        Err(err) ->
            cleanup_test_files!(FilesMaybeExist)?
            Err(Exit(1, "Test run failed:\n\t${Inspect.to_str(err)}"))

run_tests! : {} => Result {} _
run_tests! = |{}|
    Stdout.line!("Testing some File functions...")?
    Stdout.line!("This will create and manipulate test files in the current directory.")?
    Stdout.line!("")?

    # Test basic file operations
    test_basic_file_operations!({})?
    
    # Test file type checking
    test_file_type_checking!({})?
    
    # Test file reader with capacity
    test_file_reader_with_capacity!({})?

    # Test hard link creation
    test_hard_link!({})?

    # Test file rename
    test_file_rename!({})?

    # Test file exists
    test_file_exists!({})?

    Stdout.line!("\nI ran all file function tests.")

test_basic_file_operations! : {} => Result {} _
test_basic_file_operations! = |{}|
    Stdout.line!("Testing File.write_bytes! and File.read_bytes!:")?

    test_bytes = [72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33] # "Hello, World!" in bytes
    File.write_bytes!(test_bytes, "test_bytes.txt")?

    file_content_bytes = File.read_bytes!("test_bytes.txt")?
    Stdout.line!("Bytes in test_bytes.txt: ${Inspect.to_str(file_content_bytes)}")?


    Stdout.line!("\nTesting File.write!:")?

    File.write!({ some: "json stuff" }, "test_write.json", Json.utf8)?
    json_file_content = File.read_utf8!("test_write.json")?
    Stdout.line!("Content of test_write.json: ${json_file_content}")?

    Ok({})

test_file_type_checking! : {} => Result {} _
test_file_type_checking! = |{}|

    Stdout.line!("\nTesting File.is_file!:")?
    is_file_result = File.is_file!("test_bytes.txt")?
    if is_file_result then
        Stdout.line!("✓ test_bytes.txt is confirmed to be a file")?
    else
        Stderr.line!("✗ test_bytes.txt is not recognized as a file")?


    Stdout.line!("\nTesting File.is_sym_link!:")?
    is_symlink_one = File.is_sym_link!("test_bytes.txt")?
    if is_symlink_one then
        Stderr.line!("✗ test_bytes.txt is a symbolic link")?
    else
        Stdout.line!("✓ test_bytes.txt is not a symbolic link")?

    Cmd.exec!("ln",["-s", "test_bytes.txt","test_symlink.txt"])?

    is_symlink_two = File.is_sym_link!("test_symlink.txt")?
    if is_symlink_two then
        Stdout.line!("✓ test_symlink.txt is a symbolic link")?
    else
        Stderr.line!("✗ test_symlink.txt is not a symbolic link")?


    Stdout.line!("\nTesting File.type!:")?

    file_type_file = File.type!("test_bytes.txt")?
    Stdout.line!("test_bytes.txt file type: ${Inspect.to_str(file_type_file)}")?

    file_type_dir = File.type!(".")?
    Stdout.line!(". file type: ${Inspect.to_str(file_type_dir)}")?

    file_type_symlink = File.type!("test_symlink.txt")?
    Stdout.line!("test_symlink.txt file type: ${Inspect.to_str(file_type_symlink)}")?

    Ok({})

test_file_reader_with_capacity! : {} => Result {} _
test_file_reader_with_capacity! = |{}|
    Stdout.line!("\nTesting File.open_reader_with_capacity!:")?
    
    # First, create a multi-line test file
    multi_line_content = "First line\nSecond line\nThird line\n"
    File.write_utf8!(multi_line_content, "test_multiline.txt")?
    
    # Open reader with custom capacity
    reader_buf_size = 3
    reader = File.open_reader_with_capacity!("test_multiline.txt", reader_buf_size)?
    Stdout.line!("✓ Successfully opened reader with ${Num.to_str(reader_buf_size)} byte capacity")?
    
    # Read lines one by one
    Stdout.line!("\nReading lines from file:")?
    line1_bytes = File.read_line!(reader)?
    line1_str = Str.from_utf8(line1_bytes) ? |_| LineOneInvalidUtf8
    Stdout.line!("Line 1: ${line1_str}")?
    
    line2_bytes = File.read_line!(reader)?
    line2_str = Str.from_utf8(line2_bytes) ? |_| LineTwoInvalidUtf8
    Stdout.line!("Line 2: ${line2_str}")?

    Ok({})

test_hard_link! : {} => Result {} _
test_hard_link! = |{}|
    Stdout.line!("\nTesting File.hard_link!:")?
    
    # Create original file
    File.write_utf8!("Original file content for hard link test", "test_original_file.txt")?
    
    # Create hard link
    when File.hard_link!("test_original_file.txt", "test_link_to_original.txt") is
        Ok({}) ->
            Stdout.line!("✓ Successfully created hard link: test_link_to_original.txt")?

            ls_li_output =
                Cmd.new("ls")
                |> Cmd.args(["-li", "test_original_file.txt", "test_link_to_original.txt"])
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

            Stdout.line!("Hard link inodes should be equal: ${Inspect.to_str(first_inode == second_inode)}")?
            
            # Verify both files exist and have same content
            original_content = File.read_utf8!("test_original_file.txt")?
            link_content = File.read_utf8!("test_link_to_original.txt")?
            
            if original_content == link_content then
                Stdout.line!("✓ Hard link contains same content as original")
            else
                Stderr.line!("✗ Hard link content differs from original")
        
        Err(err) ->
            Stderr.line!("✗ Hard link creation failed: ${Inspect.to_str(err)}")

test_file_rename! : {} => Result {} _
test_file_rename! = |{}|
    Stdout.line!("\nTesting File.rename!:")?
    
    # Create original file
    original_name = "test_rename_original.txt"
    new_name = "test_rename_new.txt"
    File.write_utf8!("Content for rename test", original_name)?
    
    # Rename the file
    when File.rename!(original_name, new_name) is
        Ok({}) ->
            Stdout.line!("✓ Successfully renamed ${original_name} to ${new_name}")?
            
            # Verify original file no longer exists
            original_exists_after = 
                when File.is_file!(original_name) is
                    Ok(exists) -> exists
                    Err(_) -> Bool.false
            
            if original_exists_after then
                Stderr.line!("✗ Original file ${original_name} still exists after rename")?
            else
                Stdout.line!("✓ Original file ${original_name} no longer exists")?
            
            # Verify new file exists and has correct content
            new_exists = File.is_file!(new_name)?
            if new_exists then
                Stdout.line!("✓ Renamed file ${new_name} exists")?
                
                content = File.read_utf8!(new_name)?
                if content == "Content for rename test" then
                    Stdout.line!("✓ Renamed file has correct content")?
                else
                    Stderr.line!("✗ Renamed file has incorrect content")?
            else
                Stderr.line!("✗ Renamed file ${new_name} does not exist")?
        
        Err(err) ->
            Stderr.line!("✗ File rename failed: ${Inspect.to_str(err)}")?
    
    Ok({})

test_file_exists! : {} => Result {} _
test_file_exists! = |{}|
    Stdout.line!("\nTesting File.exists!:")?

    # Test that a file that exists returns true
    filename = "test_exists.txt"
    File.write_utf8!("", filename)?

    test_file_exists = File.exists!(filename) ? |err| FileExistsCheckFailed(err)

    if test_file_exists then 
        Stdout.line!("✓ File.exists! returns true for a file that exists")?
    else
        Stderr.line!("✗ File.exists! returned false for a file that exists")?

    # Test that a file that does not exist returns false
    File.delete!(filename)?

    test_file_exists_after_delete = File.exists!(filename) ? |err| FileExistsCheckAfterDeleteFailed(err)

    if test_file_exists_after_delete then
        Stderr.line!("✗ File.exists! returned true for a file that does not exist")?
    else
        Stdout.line!("✓ File.exists! returns false for a file that does not exist")?

    Ok({})

cleanup_test_files! : [FilesNeedToExist, FilesMaybeExist] => Result {} _
cleanup_test_files! = |files_requirement|
    Stdout.line!("\nCleaning up test files...")?
    
    test_files = [
        "test_bytes.txt",
        "test_symlink.txt",
        "test_write.json", 
        "test_multiline.txt",
        "test_original_file.txt",
        "test_link_to_original.txt",
        "test_rename_new.txt",
    ]

    delete_result = List.for_each_try!(
        test_files,
        |filename| File.delete!(filename)
    )
    
    when files_requirement is
        FilesNeedToExist ->
            delete_result ? |err| FileDeletionFailed(err)
            
        FilesMaybeExist ->
            Ok({})?

    Stdout.line!("✓ Deleted all files.")

