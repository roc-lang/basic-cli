platform "cli"
    requires {} { main : Str -> Task Str I32 }
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
        Command,
        Tty,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Str -> (Task Str I32 as Fx)
mainForHost = \arg -> main arg
