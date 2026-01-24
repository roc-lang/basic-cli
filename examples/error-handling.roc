app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File

# Demonstrates error handling patterns

main! = |_args| {
    file_name = "test-file.txt"

    # Try to read a file that doesn't exist - should error
    result = File.read_utf8!("nonexistent-file.txt")
    match result {
        Ok(content) => Stdout.line!("Unexpected success: ${content}")
        Err(FileErr(NotFound)) => Stdout.line!("Expected error: File not found (NotFound)")
        Err(FileErr(PermissionDenied)) => Stdout.line!("Error: Permission denied")
        Err(FileErr(Other(msg))) => Stdout.line!("Error: ${msg}")
        Err(_) => Stdout.line!("Error: Other file error")
    }

    # Now demonstrate success path - create, read, then cleanup
    # Using ? operator to propagate errors (works with open tag unions)
    File.write_utf8!(file_name, "Hello from error-handling example!")?

    content = File.read_utf8!(file_name)?
    Stdout.line!("${file_name} contains: ${content}")

    # Cleanup
    File.delete!(file_name)?

    Ok({})
}
