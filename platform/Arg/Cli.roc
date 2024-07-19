## Build a CLI parser using the `<-` builder notation!
##
## This module is the entry point for creating CLIs.
## To get started, create a
## [record builder](https://www.roc-lang.org/examples/RecordBuilder/README.html)
## using the [combine] method as the mapper.
## You can pass `Opt`s, `Param`s, or `Subcommand`s as fields,
## and they will automatically be registered in the CLI config
## as well as build a parser with the inferred types of the fields
## you set.
##
## ```roc
## { Cli.combine <-
##     alpha: Opt.u64 { short: "a", help: "Set the alpha level" },
##     verbosity: Opt.count { short: "v", long: "verbose", help: "How loud we should be." },
##     files: Param.strList { name: "files", help: "The files to process." },
## }
## |> Cli.finish {
##     name: "example",
##     version: "v1.0.0",
##     authors: ["Some One <some.one@mail.com>"],
##     description: "Do some work with some files."
## }
## |> Cli.assertValid
## ```
##
## You can also add create subcommands in the same way:
##
## ```roc
## fooSubcommand =
##     Opt.u64 { short: "a", help: "Set the alpha level" }
##     |> SubCmd.finish {
##         name: "foo",
##         description: "Foo some stuff."
##         mapper: Foo,
##     }
##
## barSubcommand =
##     # We allow two subcommands of the same parent to have overlapping
##     # fields since only one can ever be parsed at a time.
##     Opt.u64 { short: "a", help: "Set the alpha level" }
##     |> SubCmd.finish {
##         name: "bar",
##         description: "Bar some stuff."
##         mapper: Bar,
##     }
##
## { Cli.combine <-
##     verbosity: Opt.count { short: "v", long: "verbose" },
##     sc: SubCmd.optional [fooSubcommand, barSubcommand],
## }
## ```
##
## And those subcommands can have their own subcommands! But anyway...
##
## Once you have a command with all of its fields configured, you can
## turn it into a parser using the [finish] function, followed by
## the [assertValid] function that asserts that the CLI is well configured.
##
## From there, you can take in command line arguments and use your
## data if it parses correctly:
##
## ```roc
## cliParser =
##     { Cli.combine <-
##         alpha: Opt.u64 { short: "a", help: "Set the alpha level" },
##         verbosity: Opt.count { short: "v", long: "verbose", help: "How loud we should be." },
##         files: Param.strList { name: "files", help: "The files to process." },
##     }
##     |> Cli.finish {
##         name: "example",
##         version: "v1.0.0",
##         authors: ["Some One <some.one@mail.com>"],
##         description: "Do some work with some files."
##     }
##     |> Cli.assertValid
##
## expect
##     cliParser
##     |> Cli.parseOrDisplayMessage ["example", "-a", "123", "-vvv", "file.txt", "file-2.txt"]
##     == Ok { alpha: 123, verbosity: 3, files: ["file.txt", "file-2.txt"] }
## ```
##
## You're ready to start parsing arguments!
##
## _note: `Opt`s must be set before an optional `Subcommand` field is given,_
## _and the `Subcommand` field needs to be set before `Param`s are set._
## _`Param` lists also cannot be followed by anything else including_
## _themselves. These requirements ensure we parse arguments in the_
## _right order. Luckily, all of this is ensured at the type level._
module [
    CliParser,
    map,
    combine,
    finish,
    finishWithoutValidating,
    assertValid,
    parseOrDisplayMessage,
]

import Arg.Opt
import Arg.Param
import Arg.Base exposing [
    TextStyle,
    ArgParserResult,
    ArgExtractErr,
    CliConfig,
    CliConfigParams,
    mapSuccessfullyParsed,
]
import Arg.Parser exposing [Arg, parseArgs]
import Arg.Builder exposing [CliBuilder]
import Arg.Validate exposing [validateCli, CliValidationErr]
import Arg.ErrorFormatter exposing [
    formatArgExtractErr,
    formatCliValidationErr,
]
import Arg.Help exposing [helpText, usageHelp]

## A parser that interprets command line arguments and returns well-formed data.
CliParser state : {
    config : CliConfig,
    parser : List Str -> ArgParserResult state,
    textStyle : TextStyle,
}

## Map over the parsed value of a CLI parser field.
##
## Useful for naming bare fields, or handling default values.
##
## ```roc
## expect
##     { parser } =
##         { Cli.combine <-
##             verbosity: Opt.count { short: "v", long: "verbose" }
##                 |> Cli.map Verbosity,
##             file: Param.maybeStr { name: "file" }
##                 |> Cli.map \f -> Result.withDefault f "NO_FILE",
##         }
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##    parser ["example", "-vvv"]
##    == SuccessfullyParsed { verbosity: Verbosity 3, file: "NO_FILE" }
## ```
map : CliBuilder a fromAction toAction, (a -> b) -> CliBuilder b fromAction toAction
map = \builder, mapper ->
    Arg.Builder.map builder mapper

## Assemble a CLI builder using the `<- ` builder notation.
##
## Check the module-level documentation for general usage instructions.
##
## ```roc
## expect
##     { parser } =
##         { Cli.combine <-
##             verbosity: Opt.count { short: "v", long: "verbose" },
##             file: Param.str { name: "file" },
##         }
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##    parser ["example", "file.txt", "-vvv"]
##    == SuccessfullyParsed { verbosity: 3, file: "file.txt" }
## ```
combine : CliBuilder a action1 action2, CliBuilder b action2 action3, (a, b -> c) -> CliBuilder c action1 action3
combine = \left, right, combiner ->
    Arg.Builder.combine left right combiner

## Fail the parsing process if any arguments are left over after parsing.
ensureAllArgsWereParsed : List Arg -> Result {} ArgExtractErr
ensureAllArgsWereParsed = \remainingArgs ->
    when remainingArgs is
        [] -> Ok {}
        [first, ..] ->
            extraArgErr =
                when first is
                    Parameter param -> ExtraParamProvided param
                    Long long -> UnrecognizedLongArg long.name
                    Short short -> UnrecognizedShortArg short
                    ShortGroup sg ->
                        firstShortArg = List.first sg.names |> Result.withDefault ""
                        UnrecognizedShortArg firstShortArg

            Err extraArgErr

## Bundle a CLI builder into a parser, ensuring that its configuration is valid.
##
## Though the majority of the validation we'd need to do for type safety is
## rendered unnecessary by the design of this library, there are some things
## that the type system isn't able to prevent. Here are the checks we currently
## perform after building your CLI parser:
##
## - All commands and subcommands must have kebab-case names.
## - All options must have either:
##   - A short flag which is a single character.
##   - A long flag which is more than one character and kebab-case.
##   - Both a short and a long flag with the above requirements.
## - All parameters must be have kebab-case names.
## - All custom option/parameter types are have kebab-case names.
## - No options can overlap, even between different subcommands, so long
##   as the options between the subcommands are ambiguous.
##   - For example, a CLI with a `-t` option at the root level and also
##     a `-t` option in the subcommand `sub` would fail validation since
##     we wouldn't know who should get the `-t` option.
##   - However, a CLI with two subcommands that each have a `-t` option
##     would not fail validation since only one subcommand can be called
##     at once.
##
## If you would like to avoid these validations, you can use [finishWithoutValidating]
## instead, but you may receive some suprising results when parsing because
## our parsing logic assumes the above validations have been made.
##
## ```roc
## expect
##     { Cli.combine <-
##         verbosity: Opt.count { short: "v", long: "verbose" },
##         file: Param.str { name: "file" },
##     }
##     |> Cli.finish { name: "example" }
##     |> Result.isOk
##
## expect
##     { Cli.combine <-
##         verbosity: Opt.count { short: "" },
##         file: Param.str { name: "" },
##     }
##     |> Cli.finish { name: "example" }
##     |> Result.isErr
## ```
finish : CliBuilder data fromAction toAction, CliConfigParams -> Result (CliParser data) CliValidationErr
finish = \builder, params ->
    { parser, config, textStyle } = finishWithoutValidating builder params

    validateCli config
    |> Result.map \{} -> { parser, config, textStyle }

## Bundle a CLI builder into a parser without validating its configuration.
##
## We recommend using the [finish] function to validate your parser as our
## library's logic assumes said validation has taken place. However, this method
## could be useful if you know better than our validations about the correctness
## of your CLI.
##
## ```roc
## expect
##     { parser } =
##         { Cli.combine <-
##             verbosity: Opt.count { short: "v", long: "verbose" },
##             file: Param.maybeStr { name: "file" },
##         }
##         |> Cli.finishWithoutValidating { name: "example" }
##
##     parser ["example", "-v", "-v"]
##     == SuccessfullyParsed { verbosity: 2, file: Err NoValue }
## ```
finishWithoutValidating : CliBuilder data fromAction toAction, CliConfigParams -> CliParser data
finishWithoutValidating = \builder, { name, authors ? [], version ? "", description ? "", textStyle ? Color } ->
    { options, parameters, subcommands, parser } =
        builder
        |> Arg.Builder.checkForHelpAndVersion
        |> Arg.Builder.updateParser \data ->
            ensureAllArgsWereParsed data.remainingArgs
            |> Result.map \{} -> data
        |> Arg.Builder.intoParts

    config = {
        name,
        authors,
        version,
        description,
        options,
        parameters,
        subcommands: HasSubcommands subcommands,
    }

    {
        config,
        textStyle,
        parser: \args ->
            parser { args: parseArgs args, subcommandPath: [name] }
            |> mapSuccessfullyParsed \{ data } -> data,
    }

## Assert that a CLI is properly configured, crashing your program if not.
##
## Given that there are some aspects of a CLI that we cannot ensure are
## correct at compile time, the easiest way to ensure that your CLI is properly
## configured is to validate it and crash immediately on failure, following the
## Fail Fast principle.
##
## You can avoid making this assertion by handling the error yourself or
## by finish your CLI with the [finishWithoutValidating] function, but
## the validations we perform (detailed in [finish]'s docs) are important
## for correct parsing.
##
## ```roc
## Opt.num { short: "a" }
## |> Cli.finish { name: "example" }
## |> Cli.assertValid
## ```
assertValid : Result (CliParser data) CliValidationErr -> CliParser data
assertValid = \result ->
    when result is
        Ok cli -> cli
        Err err -> crash (formatCliValidationErr err)

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
##         verbosity: Opt.count { short: "v", long: "verbose" },
##         alpha: Opt.maybeNum { short: "a", long: "alpha" },
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
##           -a, --alpha    Set the alpha level.
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
parseOrDisplayMessage : CliParser data, List Str -> Result data Str
parseOrDisplayMessage = \parser, args ->
    when parser.parser args is
        SuccessfullyParsed data -> Ok data
        ShowHelp { subcommandPath } -> Err (helpText parser.config subcommandPath parser.textStyle)
        ShowVersion -> Err parser.config.version
        IncorrectUsage err { subcommandPath } ->
            usageStr = usageHelp parser.config subcommandPath parser.textStyle
            incorrectUsageStr =
                """
                Error: $(formatArgExtractErr err)

                $(usageStr)
                """

            Err incorrectUsageStr

expect
    Arg.Opt.count { short: "v" }
    |> Arg.Cli.map Verbosity
    |> Arg.Cli.finish { name: "empty" }
    |> Result.isOk

expect
    Arg.Opt.count { short: "" }
    |> Arg.Cli.map Verbosity
    |> Arg.Cli.finish { name: "example" }
    |> Result.isErr

expect
    { Arg.Cli.combine <-
        verbosity: Arg.Opt.count { short: "v" },
        points: Arg.Param.str { name: "points" },
    }
    |> Arg.Cli.finish { name: "test" }
    |> Result.isOk
