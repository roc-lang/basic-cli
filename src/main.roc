platform "cli"
    requires {} { main : Task {} [] }
    exposes [Task, Arg, Dir, Env, EnvDecoding, File, FileMetadata, Path, Process, Stdout, Stderr, Stdin, Url]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} [] as Fx
mainForHost = main
