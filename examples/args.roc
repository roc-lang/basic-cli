app [main!] {
    pf: platform "../platform/main.roc",
    weaver: "https://github.com/smores56/weaver/releases/download/0.3.1/CZWzZ3WIfkG5_rxdcwPQ0PqgrlZQFwKQUi2zyMYddXc.tar.br",
}

import pf.Stdout
import pf.Stderr
import pf.Arg
import weaver.Cli
import weaver.SubCmd
import weaver.Opt
import weaver.Param

main! : {} => Result {} _
main! = \{} ->
    when Cli.parseOrDisplayMessage cli (Arg.list! {}) is
        Ok subcommand ->
            mathOutcome =
                when subcommand is
                    Max { first, rest } ->
                        rest
                        |> List.walk first \max, n ->
                            Num.max max n

                    Div { dividend, divisor } ->
                        dividend / divisor

            try Stdout.line! (Num.toStr mathOutcome)

            Ok {}

        Err message ->
            try Stderr.line! message

            Err (Exit 1 "")

cli =
    SubCmd.required [maxSubcommand, divideSubcommand]
    |> Cli.finish {
        name: "args-example",
        description: "A calculator example of the CLI platform argument parser.",
        version: "0.1.0",
    }
    |> Cli.assertValid

maxSubcommand =
    { Cli.weave <-
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
    { Cli.weave <-
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
