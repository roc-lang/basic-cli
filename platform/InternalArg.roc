module [ArgToAndFromHost]

# represented this way to simplify the glue across the host boundary
ArgToAndFromHost : {
    type : [Unix, Windows],
    unix : List U8,
    windows : List U16,
}
