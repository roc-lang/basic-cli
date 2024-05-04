platform "glue"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [
        InternalHttp,
        InternalCommand,
        InternalFile,
        InternalPath,
        InternalTcp,
    ]
    provides [mainForHost]

GlueTypes : {
    ha : InternalHttp.Request,
    hb : InternalHttp.Method,
    hc : InternalHttp.Header,
    hd : InternalHttp.TimeoutConfig,
    he : InternalHttp.Part,
    hf : InternalHttp.InternalResponse,
    hi : InternalHttp.Error,
    ca : InternalCommand.Command,
    cb : InternalCommand.Output,
    cc : InternalCommand.CommandErr,
    fa : InternalFile.ReadErr,
    fb : InternalFile.WriteErr,
    pa : InternalPath.UnwrappedPath,
    pb : InternalPath.InternalPath,
    pc : InternalPath.GetMetadataErr,
    pd : InternalPath.InternalPathType,
    tcpa : InternalTcp.Stream,
    tcpb : InternalTcp.ConnectErr,
    tcpc : InternalTcp.StreamErr,
    tcpd : InternalTcp.ConnectResult,
    tcpe : InternalTcp.WriteResult,
    tcpf : InternalTcp.ReadResult,
    tcpg : InternalTcp.ReadExactlyResult,
}

mainForHost : GlueTypes
mainForHost = main
