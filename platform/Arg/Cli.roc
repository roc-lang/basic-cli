## Build a CLI parser using the `: <- ` builder notation!
##
## This module is the entry point for creating CLIs.
## To get started, call the [build] method and pass a
## [record builder](https://www.roc-lang.org/examples/RecordBuilder/README.html)
## to it. You can pass `Opt`s, `Param`s, or `Subcommand`s as fields,
## and they will be automatically registered in the config as
## well as rolled into a parser with the inferred types of the
## fields you use.
##
## ```roc
## Cli.build {
##     alpha: <- Opt.u64 { short: "a", help: "Set the alpha level" },
##     verbosity: <- Opt.count { short: "v", long: "verbose", help: "How loud we should be." },
##     files: <- Param.strList { name: "files", help: "The files to process." },
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
##     Cli.build {
##         alpha: <- Opt.u64 {
##             short: "a",
##             help: "Set the alpha level",
##         },
##     }
##     |> Subcommand.finish {
##         name: "foo",
##         description: "Foo some stuff."
##         mapper: Foo,
##     }
##
## barSubcommand =
##     Cli.build {
##         # We allow two subcommands of the same parent to have overlapping
##         # fields since only one can ever be parsed at a time.
##         alpha: <- Opt.u64 {
##             short: "a",
##             help: "Set the alpha level",
##         },
##     }
##     |> Subcommand.finish {
##         name: "bar",
##         description: "Bar some stuff."
##         mapper: Bar,
##     }
##
## Cli.build {
##     sc: <- Subcommand.optional [fooSubcommand, barSubcommand],
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
##     Cli.build {
##         alpha: <- Opt.u64 { short: "a", help: "Set the alpha level" },
##         verbosity: <- Opt.count { short: "v", long: "verbose", help: "How loud we should be." },
##         files: <- Param.strList { name: "files", help: "The files to process." },
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
    build,
    finish,
    finishWithoutValidating,
    assertValid,
]

import Arg.Opt
import Arg.Base exposing [
    TextStyle,
    ArgParserResult,
    ArgExtractErr,
    CliConfig,
    CliConfigParams,
    mapSuccessfullyParsed,
]
import Arg.Parser exposing [Arg, parseArgs]
import Arg.Builder exposing [CliBuilder, GetOptionsAction]
import Arg.Validate exposing [validateCli, CliValidationErr]
import Arg.ErrorFormatter exposing [formatCliValidationErr]

## A parser that interprets command line arguments and returns well-formed data.
CliParser state : {
    config : CliConfig,
    parser : List Str -> ArgParserResult state,
    textStyle : TextStyle,
}

## Initialize a CLI builder using the `: <- ` builder notation.
##
## Check the module-level documentation for general usage instructions.
##
## ```roc
## expect
##     { parser } =
##         Cli.build {
##             verbosity: <- Opt.count { short: "v", long: "verbose" },
##         }
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##    parser ["example", "-vvv"]
##    == SuccessfullyParsed { verbosity: 3 }
## ```
build : base -> CliBuilder base GetOptionsAction
build = \base -> Arg.Builder.fromState base

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
##     Cli.build {
##         verbosity: <- Opt.count { short: "v", long: "verbose" },
##     }
##     |> Cli.finish { name: "example" }
##     |> Result.isOk
##
## expect
##     Cli.build {
##         verbosity: <- Opt.count { short: "" },
##     }
##     |> Cli.finish { name: "example" }
##     |> Result.isErr
## ```
finish : CliBuilder state action, CliConfigParams -> Result (CliParser state) CliValidationErr
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
##         Cli.build {
##             verbosity: <- Opt.count { short: "v", long: "verbose" },
##         }
##         |> Cli.finishWithoutValidating { name: "example" }
##
##     parser ["example", "-v", "-v"]
##     == SuccessfullyParsed { verbosity: 2 }
## ```
finishWithoutValidating : CliBuilder state action, CliConfigParams -> CliParser state
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
## Cli.build {
##     a: <- Opt.num { short: "a" }
## }
## |> Cli.finish { name: "example" }
## |> Cli.assertValid
## ```
assertValid : Result (CliParser state) CliValidationErr -> CliParser state
assertValid = \result ->
    when result is
        Ok cli -> cli
        Err err -> crash (formatCliValidationErr err)

expect
    build {
        verbosity: <- Arg.Opt.count { short: "v" },
    }
    |> finish { name: "empty" }
    |> Result.isOk

expect
    build {
        verbosity: <- Arg.Opt.count { short: "" },
    }
    |> finish { name: "example" }
    |> Result.isErr
