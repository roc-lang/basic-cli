interface Op
    exposes [Op, mapOp]
    imports [InternalHttp, InternalFile, InternalTcp]

# These would be interface that could be defined in a pure Roc library.
# It is not really need for this platform, but this is just to show how the api would be split.
StdoutInfo a : [
    Line Str ({} -> a),
    Write Str ({} -> a),
]

mapStdoutInfo : StdoutInfo a, (a -> b) -> StdoutInfo b
mapStdoutInfo = \info, f ->
    when info is
        Line str cont -> Line str (\{} -> f (cont {}))
        Write str cont -> Write str (\{} -> f (cont {}))

Op a : [
    Stdout (StdoutInfo a),
    StderrLine Str ({} -> a),
    StderrWrite Str ({} -> a),
    StdinLine (Str -> a),
    FileWriteBytes (List U8) (List U8) (Result {} InternalFile.WriteErr -> a),
    FileWriteUtf8 (List U8) Str (Result {} InternalFile.WriteErr -> a),
    FileWriteDelete (List U8) (Result {} InternalFile.WriteErr -> a),
    FileReadBytes (List U8) (Result (List U8) InternalFile.ReadErr -> a),
    # This should be InternalDir.ReadErr, but that breaks `roc glue`.
    DirList (List U8) (Result (List (List U8)) InternalFile.ReadErr -> a),
    EnvDict (Dict Str Str -> a),
    EnvVar Str (Result Str {} -> a),
    ExePath (Result (List U8) {} -> a),
    SetCwd (List U8) (Result {} {} -> a),
    ProcessExit U8 ({} -> a),
    # If we encounter a Unicode error in any of the args, it will be replaced with
    # the Unicode replacement char where necessary.
    Args (List Str -> a),
    Cwd (List U8 -> a),
    SendRequest (Box InternalHttp.Request) (InternalHttp.Response -> a),
    TcpConnect Str U16 (InternalTcp.ConnectResult -> a),
    TcpClose InternalTcp.Stream ({} -> a),
    TcpReadUpTo Nat InternalTcp.Stream (InternalTcp.ReadResult -> a),
    TcpReadExactly Nat InternalTcp.Stream (InternalTcp.ReadExactlyResult -> a),
    TcpReadUntil Nat InternalTcp.Stream (InternalTcp.ReadResult -> a),
    TcpWrite (List U8) InternalTcp.Stream (InternalTcp.WriteResult -> a),
    PosixTime (U128 -> a),
    Done,
]

mapOp : Op a, (a -> b) -> Op b
mapOp = \op, f ->
    when op is
        Stdout info -> Stdout (mapStdoutInfo info f)
        StderrLine str cont -> StderrLine str (\{} -> f (cont {}))
        StderrWrite str cont -> StderrWrite str (\{} -> f (cont {}))
        StdinLine cont -> StdinLine (\s -> f (cont s))
        FileWriteBytes path bytes cont -> FileWriteBytes path bytes (\res -> f (cont res))
        FileWriteUtf8 path str cont -> FileWriteUtf8 path str (\res -> f (cont res))
        FileWriteDelete path cont -> FileWriteDelete path (\res -> f (cont res))
        FileReadBytes path cont -> FileReadBytes path (\res -> f (cont res))
        DirList path cont -> DirList path (\res -> f (cont res))
        EnvDict cont -> EnvDict (\dict -> f (cont dict))
        EnvVar str cont -> EnvVar str (\res -> f (cont res))
        ExePath cont -> ExePath (\res -> f (cont res))
        SetCwd path cont -> SetCwd path (\res -> f (cont res))
        ProcessExit code cont -> ProcessExit code (\{} -> f (cont {}))
        Cwd cont -> Cwd (\path -> f (cont path))
        Args cont -> Args (\args -> f (cont args))
        SendRequest req cont -> SendRequest req (\res -> f (cont res))
        TcpConnect str port cont -> TcpConnect str port (\res -> f (cont res))
        TcpClose stream cont -> TcpClose stream (\res -> f (cont res))
        TcpReadUpTo bytes stream cont -> TcpReadUpTo bytes stream (\res -> f (cont res))
        TcpReadExactly bytes stream cont -> TcpReadExactly bytes stream (\res -> f (cont res))
        TcpReadUntil bytes stream cont -> TcpReadUntil bytes stream (\res -> f (cont res))
        TcpWrite bytes stream cont -> TcpWrite bytes stream (\res -> f (cont res))
        PosixTime cont -> PosixTime (\t -> f (cont t))
        Done -> Done
