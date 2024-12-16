app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.File
import pf.Path
import pf.Env
import pf.Dir

outTxtPath = "out.txt"

task! = \{} ->

    cwd_str = Path.display (try Env.cwd! {})

    try Stdout.line! "cwd: $(cwd_str)"

    dir_entries = try Dir.list! cwd_str

    dir_entries_tr = Str.joinWith (List.map dir_entries Path.display) "\n    "

    try Stdout.line! "Directory contents:\n    $(dir_entries_tr)\n"

    try Stdout.line! "Writing a string to out.txt"

    try File.write_utf8! "a string!" outTxtPath

    contents = try File.read_utf8! outTxtPath

    Stdout.line! "I read the file back. Its contents: \"$(contents)\""

main! = \{} ->
    when task! {} is
        Ok {} -> Stdout.line! "Successfully wrote a string to out.txt"
        Err err ->
            msg =
                when err is
                    FileWriteErr _ PermissionDenied -> "PermissionDenied"
                    FileWriteErr _ Unsupported -> "Unsupported"
                    FileWriteErr _ (Unrecognized _ other) -> other
                    FileReadErr _ _ -> "Error reading file"
                    _ -> "Uh oh, there was an error!"

            try Stderr.line! msg

            Err (Exit 1 "unable to write file: $(msg)") # non-zero exit code to indicate failure
