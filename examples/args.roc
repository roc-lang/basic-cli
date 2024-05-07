app [main] {
    pf: platform "../platform/main.roc",
    weaver: "https://github.com/smores56/weaver/releases/download/0.2.0/BBDPvzgGrYp-AhIDw0qmwxT0pWZIQP_7KOrUrZfp_xw.tar.br",
}

import pf.Stdout
import pf.Env
import pf.Task exposing [Task]
import weaver.Cli
import weaver.Subcommand
import weaver.Opt
import weaver.Param

main =
    when Cli.parseOrDisplayMessage cli Env.args! is
        Ok { command: subcommand } ->
            runCommand subcommand
            |> Num.toStr
            |> Stdout.line

        Err usage ->
            Stdout.line! usage

            Task.err (Exit 1 "") # 1 is an exit code to indicate failure

runCommand = \command ->
    when command is
        Max { first, rest } ->
            rest
            |> List.walk first \max, n ->
                Num.max max n

        Div { dividend, divisor } ->
            dividend / divisor

cli =
    Cli.weave {
        command: <- Subcommand.required [maxSubcommand, divideSubcommand],
    }
    |> Cli.finish {
        name: "args-example",
        description: "A calculator example of the CLI platform argument parser.",
        version: "0.1.0",
    }
    |> Cli.assertValid

maxSubcommand =
    Cli.weave {
        # ensure there's at least one parameter provided
        first: <- Param.dec { name: "first", help: "the first number to compare." },
        rest: <- Param.decList { name: "rest", help: "the other numbers to compare." },
    }
    |> Subcommand.finish {
        name: "max",
        description: "Find the largest of multiple numbers.",
        mapper: Max,
    }

divideSubcommand =
    Cli.weave {
        dividend: <-
            Opt.dec {
                short: "n",
                long: "dividend",
                help: "the number to divide; corresponds to a numerator.",
            },
        divisor: <-
            Opt.dec {
                short: "d",
                long: "divisor",
                help: "the number to divide by; corresponds to a denominator.",
            },
    }
    |> Subcommand.finish {
        name: "div",
        description: "Divide two numbers.",
        mapper: Div,
    }
