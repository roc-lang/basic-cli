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

    Stdout.line!("\n✓ All File function tests completed! ✓")

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
                Stdout.line!("✓ Hard link contains same content as original")?
            else
                Stderr.line!("✗ Hard link content differs from original")?
        
        Err(err) ->
            Stderr.line!("✗ Hard link creation failed: ${Inspect.to_str(err)}")?

    # Clean up test files
    cleanup_test_files!({})

cleanup_test_files! : {} => Result {} _
cleanup_test_files! = |{}|
    Stdout.line!("\nCleaning up test files...")?
    
    test_files = [
        "test_bytes.txt",
        "test_symlink.txt",
        "test_write.json", 
        "test_multiline.txt",
        "test_original_file.txt",
        "test_link_to_original.txt"
    ]

    List.for_each_try!(test_files, |filename| File.delete!(filename))?
    Stdout.line!("✓ Deleted all files.")
