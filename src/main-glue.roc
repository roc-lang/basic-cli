platform "cli"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [
        InternalCommand,
        InternalDir,
        InternalFile,
        InternalTcp,
        InternalHttp,
    ]
    provides [mainForHost]

mainForHost : IncludeTheseTypes
mainForHost = main

IncludeTheseTypes : [
    A InternalCommand.CommandErr, 
    B InternalCommand.Command,
    C InternalCommand.Output,
    D InternalDir.IOError,
    E InternalDir.DirEntry,
    F InternalFile.ReadErr,
    G InternalFile.WriteErr,
    H InternalTcp.Stream,
    I InternalTcp.ConnectErr,
    J InternalTcp.StreamErr,
    K InternalTcp.ConnectResult,
    L InternalTcp.WriteResult,
    M InternalTcp.ReadResult,
    N InternalTcp.ReadExactlyResult,
    O InternalHttp.Request, 
    P InternalHttp.Method, 
    Q InternalHttp.Header, 
    R InternalHttp.TimeoutConfig, 
    S InternalHttp.Part, 
    T InternalHttp.Body, 
    U InternalHttp.Response, 
    V InternalHttp.Metadata, 
    W InternalHttp.Error
]
