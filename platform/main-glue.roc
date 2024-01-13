platform "glue"
    requires {} { main : GlueTypes }
    exposes []
    packages {}
    imports [
        InternalCommand,
        InternalFile,
        InternalTcp,
    ]
    provides [mainForHost]

GlueTypes : [
    A InternalCommand.Command,
    B InternalCommand.Output,
    C InternalCommand.CommandErr,
    D InternalFile.ReadErr, 
    E InternalFile.WriteErr,
    F InternalTcp.Stream,
    G InternalTcp.ConnectErr,
    H InternalTcp.StreamErr,
    I InternalTcp.ConnectResult,
    J InternalTcp.WriteResult,
    K InternalTcp.ReadResult,
    L InternalTcp.ReadExactlyResult
]

mainForHost : GlueTypes
mainForHost = main
