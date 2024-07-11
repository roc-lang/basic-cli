app [main] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.Task exposing [Task]
import pf.Arg.Cli as Cli
import pf.Arg.SubCmd as SubCmd
import pf.Arg.Opt as Opt
import pf.Arg.Param as Param
import pf.Arg

main =
    args = Arg.list! {}

    when Cli.parseOrDisplayMessage cli args is
        Ok subcommand ->
            mathOutcome =
                when subcommand is
                    Max { first, rest } ->
                        rest
                        |> List.walk first \max, n ->
                            Num.max max n

                    Div { dividend, divisor } ->
                        dividend / divisor

            Stdout.line (Num.toStr mathOutcome)

        Err message ->
            Stderr.line! message

            Task.err (Exit 1 "")

cli =
    SubCmd.required [maxSubcommand, divideSubcommand]
    |> Cli.finish {
        name: "args-example",
        description: "A calculator example of the CLI platform argument parser.",
        version: "0.1.0",
    }
    |> Cli.assertValid

maxSubcommand =
    { Cli.combine <-
        # ensure there's at least one parameter provided
        first: Param.dec { name: "first", help: "the first number to compare." },
        rest: Param.decList { name: "rest", help: "the other numbers to compare." },
    }
    |> SubCmd.finish {
        name: "max",
        description: "Find the largest of multiple numbers.",
        mapper: Max,
    }

divideSubcommand =
    { Cli.combine <-
        dividend: Opt.dec {
            short: "n",
            long: "dividend",
            help: "the number to divide; corresponds to a numerator.",
        },
        divisor: Opt.dec {
            short: "d",
            long: "divisor",
            help: "the number to divide by; corresponds to a denominator.",
        },
    }
    |> SubCmd.finish {
        name: "div",
        description: "Divide two numbers.",
        mapper: Div,
    }
