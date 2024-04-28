platform "cli"
    requires {} { main : Task {} [Exit I32 Str]_ }
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
    imports [Task.{ Task }, Stderr.{line}]
    provides [mainForHost]

mainForHost : Task {} I32 as Fx
mainForHost =
    Task.attempt main \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code str) -> 
                line str
                |> Task.onErr \_ -> Task.err code
                |> Task.await \_ -> Task.err code
            Err err ->
                line "Program exited early with error: $(Inspect.toStr err)"
                |> Task.onErr \_ -> Task.err 1
                |> Task.await \_ -> Task.err 1