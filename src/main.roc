platform "cli"
    requires {} { main : Task {} [] (Op *) }
    exposes []
    packages {}
    imports [Task.{ Task }, Op.{ Op }]
    provides [mainForHost]

mainForHost : Task {} [] (Op *) as Fx
mainForHost = main
