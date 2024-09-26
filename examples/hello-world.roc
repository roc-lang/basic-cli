app [main] {
    pf: platform "../platform/main.roc",
    path: "../../path/package/main.roc",
}

#import pf.Stdout
import pf.Env
import path.Path as Path2

main =

    #path = Env.exePath!

    #dbg path

    #Stdout.line! "Hello, World!"

    Env.setCwd (Path2.fromRaw (Unix (Str.toUtf8 ".")))
