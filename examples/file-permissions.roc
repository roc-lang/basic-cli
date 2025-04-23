app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.File

main! = |_args|
    file = "LICENSE"

    is_executable = File.is_executable!(file)?

    is_readable = File.is_readable!(file)?

    is_writable = File.is_writable!(file)?

    Stdout.line!(
        """
        ${file} file permissions:
            Executable: ${Inspect.to_str(is_executable)}
            Readable: ${Inspect.to_str(is_readable)}
            Writable: ${Inspect.to_str(is_writable)}
        """
    )