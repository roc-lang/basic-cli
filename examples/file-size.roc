app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|
    file_size = File.size_in_bytes!("LICENSE")?

    Stdout.line!("The size of the LICENSE file is: ${Num.to_str(file_size)} bytes")
