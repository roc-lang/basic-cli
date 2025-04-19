app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.File

main! = |_args|
    file_size = File.size_in_bytes!("LICENSE")?

    Stdout.line!("The size of the LICENSE file is: ${Num.to_str(file_size)} bytes")
