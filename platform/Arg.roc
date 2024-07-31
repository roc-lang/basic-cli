module [list, parse]

import PlatformTask
import Stdout

import Arg.Cli exposing [CliParser]
import Arg.ErrorFormatter exposing [formatArgExtractErr]
import Arg.Help exposing [helpText, usageHelp]

## Gives a list of the program's command-line arguments.
list : {} -> Task (List Str) *
list = \{} ->
    PlatformTask.args
    |> PlatformTask.infallible

## Parse arguments using a CLI parser or show a useful message on failure.
##
## We have the following priorities in returning messages to the user:
## 1) If the `-h/--help` flag is passed, the help page for the command/subcommand
##    called will be displayed no matter if your arguments were correctly parsed.
## 2) If the `-V/--version` flag is passed, the version for the app will
##    be displayed no matter if your arguments were correctly parsed.
## 3) If the provided arguments were parsed and neither of the above two
##    built-in flags were passed, we return to you your data.
## 4) If the provided arguments were not correct, we return a short message
##    with which argument was not provided correctly, followed by the
##    usage section of the relevant command/subcommand's help text.
##
## ```roc
## exampleCli =
##     { Cli.combine <-
##         verbosity: Opt.count { short: "v", help: "How verbose our logs should be." },
##         alpha: Opt.mapbeU64 { short: "a", help: "Set the alpha level." },
##     }
##     |> Cli.finish {
##         name: "example",
##         version: "v0.1.0",
##         description: "An example CLI.",
##     }
##     |> Cli.assertValid
##
## expect
##     exampleCli
##     |> Cli.parseOrDisplayMessage ["example", "-h"]
##     == Err
##         """
##         example v0.1.0
##
##         An example CLI.
##
##         Usage:
##           example [OPTIONS]
##
##         Options:
##           -v             How verbose our logs should be.
##           -a             Set the alpha level.
##           -h, --help     Show this help page.
##           -V, --version  Show the version.
##         """
##
## expect
##     exampleCli
##     |> Cli.parseOrDisplayMessage ["example", "-V"]
##     == Err "v0.1.0"
##
## expect
##     exampleCli
##     |> Cli.parseOrDisplayMessage ["example", "-v"]
##     == Ok { verbosity: 1 }
##
## expect
##     exampleCli
##     |> Cli.parseOrDisplayMessage ["example", "-x"]
##     == Err
##         """
##         Error: The argument -x was not recognized.
##
##         Usage:
##           example [OPTIONS]
##         """
## ```
parse : CliParser state -> Task state [Exit I32 Str, StdoutErr Stdout.Err]
parse = \parser ->
    when parser.parser (list! {}) is
        SuccessfullyParsed data ->
            Task.ok data

        ShowHelp { subcommandPath } ->
            helpMessage =
                helpText parser.config subcommandPath parser.textStyle
            Stdout.line! helpMessage
            Task.err (Exit 0 "")

        ShowVersion ->
            Stdout.line! parser.config.version
            Task.err (Exit 0 "")

        IncorrectUsage err { subcommandPath } ->
            incorrectUsageMessage =
                """
                Error: $(formatArgExtractErr err)

                $(usageHelp parser.config subcommandPath parser.textStyle)
                """
            Stdout.line! incorrectUsageMessage
            Task.err (Exit 1 "")
