platform "glue"
    requires {} { main : GlueTypes }
    exposes []
    packages {}
    imports [
        InternalHttp
    ]
    provides [mainForHost]

GlueTypes : [
     A InternalHttp.Request,
     B InternalHttp.Method,
     C InternalHttp.Header,
     D InternalHttp.TimeoutConfig,
     E InternalHttp.Part,
     G InternalHttp.Response,
     H InternalHttp.Metadata,
     I InternalHttp.Error
]

mainForHost : GlueTypes
mainForHost = main
