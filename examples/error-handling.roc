app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.File
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Demonstrates handling of every possible error

main! : List Arg => Result {} _
main! = |_args|
    file_name = "test-file.txt"

    file_read_result = File.read_utf8!(file_name)

    when file_read_result is
        Ok(file_content) ->
            Stdout.line!("${file_name} contatins: ${file_content}")

        Err(err) ->
            err_msg =
                when err is
                    FileReadErr(_, io_err) -> "Error: failed to read file ${file_name} with error:\n\t${Inspect.to_str(io_err)}"
                    FileReadUtf8Err(_, io_err) -> "Error: file ${file_name} contains invalid UTF-8:\n\t${Inspect.to_str(io_err)}"

            
            Stderr.line!(err_msg)?
            Err(Exit(1, "")) # non-zero exit code to indicate failure