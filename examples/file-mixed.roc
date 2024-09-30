app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.File
import pf.Path
import pf.Env
import pf.Dir

path = "out.txt"
task =
    cwd = Env.cwd!
    cwdStr = Path.display cwd

    Stdout.line! "cwd: $(cwdStr)"
    dirEntries = Dir.list! cwdStr
    contentsStr = Str.joinWith (List.map dirEntries Path.display) "\n    "

    Stdout.line! "Directory contents:\n    $(contentsStr)\n"
    Stdout.line! "Writing a string to out.txt"
    File.writeUtf8! path "a string!"
    contents = File.readUtf8! path
    Stdout.line "I read the file back. Its contents: \"$(contents)\""

main =
    Task.attempt task \result ->
        when result is
            Ok {} -> Stdout.line "Successfully wrote a string to out.txt"
            Err err ->
                msg =
                    when err is
                        FileWriteErr _ PermissionDenied -> "PermissionDenied"
                        FileWriteErr _ Unsupported -> "Unsupported"
                        FileWriteErr _ (Unrecognized _ other) -> other
                        FileReadErr _ _ -> "Error reading file"
                        _ -> "Uh oh, there was an error!"

                Stderr.line! msg

                Task.err (Exit 1 "unable to write file: $(msg)") # non-zero exit code to indicate failure
