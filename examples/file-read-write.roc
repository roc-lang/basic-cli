app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|
    # Note: you can also import files directly if you know the path: https://www.roc-lang.org/examples/IngestFiles/README.html
    out_file = "out.txt"

    file_write_read!(out_file)?

    # Cleanup
    File.delete!(out_file)

file_write_read! : Str => Result {} [FileReadErr _ _, FileReadUtf8Err _ _, FileWriteErr _ _, StdoutErr _]
file_write_read! = |file_name|

    Stdout.line!("Writing a string to out.txt")?

    File.write_utf8!("a string!", file_name)?

    contents = File.read_utf8!(file_name)?

    Stdout.line!("I read the file back. Its contents are: \"${contents}\"")



