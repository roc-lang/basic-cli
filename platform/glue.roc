platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

InternalIOErr : {
    tag : [
        BrokenPipe,
        WouldBlock,
        WriteZero,
        Unsupported,
        Interrupted,
        OutOfMemory,
        UnexpectedEof,
        InvalidInput,
        Other,
    ],
    msg : Str,
}

mainForHost : InternalIOErr
mainForHost = main
