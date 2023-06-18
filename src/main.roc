platform "cli"
    requires {} { main : Task {} U32 }
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
        Sleep,
        Tty,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} U32 as Fx
mainForHost = main
