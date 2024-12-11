app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File

# Buffered File Reading
#
# Instead of reading an entire file and storing all of it in memory,
# like with File.readUtf8, you may want to read it in parts.
# A part of the file is stored in a buffer.
# Typically you process a part and then you ask for the next one.
#
# This can be useful to process large files without using a lot of RAM or
# requiring the user to wait until the complete file is processed when they
# only wanted to look at the first page.
#
# See examples/file-read.roc if you want to read the full contents at once.

main! = \{} ->
    reader = try File.openReader! "LICENSE"

    readSummary = try processLine! reader { linesRead: 0, bytesRead: 0 }

    Stdout.line! "Done reading file: $(Inspect.toStr readSummary)"

ReadSummary : { linesRead : U64, bytesRead : U64 }

## Count the number of lines and the number of bytes read.
processLine! : File.Reader, ReadSummary => Result ReadSummary _
processLine! = \reader, { linesRead, bytesRead } ->
    when File.readLine! reader is
        Ok bytes if List.len bytes == 0 ->
            Ok { linesRead, bytesRead }

        Ok bytes ->
            processLine! reader {
                linesRead: linesRead + 1,
                bytesRead: bytesRead + (List.len bytes |> Num.intCast),
            }

        Err err ->
            Err (ErrorReadingLine (Inspect.toStr err))
