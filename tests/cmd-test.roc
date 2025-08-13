app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd
import pf.Arg exposing [Arg]

# Tests some error branches in Cmd functions.

# TODO test all error branches in Cmd functions

main! : List Arg => Result {} _
main! = |_args|
    
    exec_res = Cmd.exec!("blablaXYZ", [])

    _ = 
        Cmd.new("cargo")
        |> Cmd.arg("build")
        |> Cmd.env("RUST_BACKTRACE", "1")
        |> Cmd.exec_cmd!()?

    _ = when exec_res is
        Ok(_) ->
            Err(FakeBlaBlaCommandShouldHaveFailed)?
        Err(err) ->
            Stdout.line!("Expected failure: ${Inspect.to_str(err)}")?
            Ok({})

    Stdout.line!("${Inspect.to_str(Cmd.exec!("ls", ["hehe"]))}")?

    Ok({})