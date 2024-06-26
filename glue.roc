app [makeGlue] {
    pf: platform "https://github.com/lukewilliamboswell/roc/releases/download/test/olBfrjtI-HycorWJMxdy7Dl2pcbbBoJy4mnSrDtRrlI.tar.br",
    glue: "https://github.com/lukewilliamboswell/roc-glue-code-gen/releases/download/0.1.0/NprKi63CKBinQjoke2ttsOTHmjmsrmsILzRgzlds02c.tar.br",
}

import glue.Rust

# generate the std lib builtins from the Rust glue code package

makeGlue = \_ -> Ok Rust.builtins
