platform "cli"
    requires {} { main : Task {} [] }
    exposes [Task, Process, Stdout, Stderr, Stdin, Path, File, FileMetadata, Dir, Arg, Env, EnvDecoding, Url, Http]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

mainForHost : Task {} [] as Fx
mainForHost = main
