app [makeGlue] {
    pf: platform "https://github.com/lukewilliamboswell/roc/releases/download/glue-0.2/5bWcGHHGninJr_RP0-Mg5lPEGYGpPeYwYmVCwG_cZG4.tar.br",
    glue: "https://github.com/lukewilliamboswell/roc-glue-code-gen/releases/download/0.4.0/E6x8uVSMI0YQ9CgpMww6Cj2g3BlN1lV8H04UEZh_-QA.tar.br",
}

import glue.Rust

# generate the std lib builtins from the Rust glue code package

makeGlue = \_ -> Ok Rust.builtins
