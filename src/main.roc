platform "cli"
    requires {} { main : Task {} [] }
    exposes [Task, Process, Stdout, Stderr, Stdin, Path, File, FileMetadata, Dir, Arg, Env, EnvDecoding, Url]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} [] as Fx
mainForHost = main
