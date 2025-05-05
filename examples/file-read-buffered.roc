app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# # Buffered File Reading
#
# Instead of reading an entire file and storing all of it in memory,
# like with File.read_utf8, you may want to read it in parts.
# A part of the file is stored in a buffer.
# Typically you process a part and then you ask for the next one.
#
# This can be useful to process large files without using a lot of RAM or
# requiring the user to wait until the complete file is processed when they
# only wanted to look at the first page.
#
# See examples/file-read-write.roc if you want to read the full contents at once.

main! : List Arg => Result {} _
main! = |_args|
    reader = File.open_reader!("LICENSE")?

    read_summary = process_line!(reader, { lines_read: 0, bytes_read: 0 })?

    Stdout.line!("Done reading file: ${Inspect.to_str(read_summary)}")

ReadSummary : {
    lines_read : U64,
    bytes_read : U64,
}

## Count the number of lines and the number of bytes read.
process_line! : File.Reader, ReadSummary => Result ReadSummary _
process_line! = |reader, { lines_read, bytes_read }|
    when File.read_line!(reader) is
        Ok(bytes) if List.len(bytes) == 0 ->
            Ok({ lines_read, bytes_read })

        Ok(bytes) ->
            process_line!(
                reader,
                {
                    lines_read: lines_read + 1,
                    bytes_read: bytes_read + (List.len(bytes) |> Num.int_cast),
                },
            )

        Err(err) ->
            Err(ErrorReadingLine(Inspect.to_str(err)))
