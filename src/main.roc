platform "cli"
    requires {} { main : Task {} [] }
    exposes [
        Path,
        Arg,
        Dir,
        Env, 
        File,
        Http,
        Process, 
        Stderr,
        Stdin,
        Task,
        Url,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} [] as Fx
mainForHost = main
