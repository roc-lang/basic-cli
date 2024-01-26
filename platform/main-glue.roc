platform "glue"
    requires {} { main : GlueTypes }
    exposes []
    packages {}
    imports [
        InternalPath,
    ]
    provides [mainForHost]

GlueTypes : [
    A InternalPath.GetMetadataErr,
    B InternalPath.InternalPathType,
]

mainForHost : GlueTypes
mainForHost = main
