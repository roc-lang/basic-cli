platform "cli"
    requires {} { main : Task {} I32 }
    exposes [
        Path,
        Arg,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        Stderr,
        Stdin,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
        Sleep,
        Cmd,
        Tty,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} I32 as Fx
mainForHost = main
