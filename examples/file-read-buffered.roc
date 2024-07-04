app [main] { pf: platform "../platform/main.roc" }

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

main =
    reader = File.getFileReader! "LICENSE"

    readSummary = Task.loop!
        { linesRead: 0, bytesRead: 0 }
        (processLine reader)
    # Why you should close files: https://stackoverflow.com/a/29536383
    File.closeFileReader! reader
    Stdout.line! "Done reading file: $(Inspect.toStr readSummary)"

ReadSummary : { linesRead : U64, bytesRead : U64 }

## Count the number of lines and the number of bytes read.
processLine : File.FileReader -> (ReadSummary -> Task [Step ReadSummary, Done ReadSummary] _)
processLine = \reader -> \{ linesRead, bytesRead } ->
        when File.readLine reader |> Task.result! is
            Ok bytes if List.len bytes == 0 ->
                Task.ok (Done { linesRead, bytesRead })

            Ok bytes ->
                Task.ok (Step { linesRead: linesRead + 1, bytesRead: bytesRead + (List.len bytes |> Num.intCast) })

            Err err ->
                Task.err (ErrorReadingLine (Inspect.toStr err))
