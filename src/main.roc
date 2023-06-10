platform "cli"
    requires {} { main : Task {} [] }
    exposes [
        Path,
        Arg,
        Dir,
        Env, 
        File,
        FileMetadata,
        Http,
        Process, 
        Stderr,
        Stdin,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} [] as Fx
mainForHost = main
