interface Op
    exposes [Op]
    imports []

Op : [
    StdoutLine Str ({} -> Op),
    StdoutWrite Str ({} -> Op),
    StdinLine (Str -> Op),
    Done,
]
