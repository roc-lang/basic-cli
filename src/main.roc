platform "cli"
    requires {} { main : Task {} [] }
    exposes [Arg, Dir, Env, EnvDecoding, File, FileMetadata, Http, Path, Process, Stderr, Stdout, Task, Url]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} [] as Fx
mainForHost = main
