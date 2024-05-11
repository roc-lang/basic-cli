module [finish, optional, required, SubcommandParserConfig]

import Arg.Base exposing [
    ArgParser,
    ArgParserState,
    ArgParserResult,
    onSuccessfulArgParse,
    SubcommandConfig,
]
import Arg.Builder exposing [
    CliBuilder,
    GetOptionsAction,
    GetParamsAction,
]

SubcommandParserConfig subState : {
    name : Str,
    parser : ArgParser subState,
    config : SubcommandConfig,
}

## Bundle a CLI builder into a subcommand.
##
## Subcommands use the same CLI builder that top-level CLIs do,
## so they are composed using the same tools. The difference lies in
## how subcommands are prepared for usage by parents. In addition to
## providing a `name` and a `description`, you also provide a `mapper`,
## which is a function that converts the subcommand's data into a common
## type that all subcommands under a parent command need to share. This
## is required since the parent command will have a field (added with
## the [field] function) that must have a unified type.
##
## ```roc
## fooSubcommand =
##     Cli.build {
##         foo: <- Opt.str { short: "f" },
##     }
##     |> Subcommand.finish { name: "foo", description: "Foo subcommand", mapper: Foo }
## ```
finish : CliBuilder state action, { name : Str, description ? Str, mapper : state -> commonState } -> { name : Str, parser : ArgParser commonState, config : SubcommandConfig }
finish = \builder, { name, description ? "", mapper } ->
    { options, parameters, subcommands, parser } =
        builder
        |> Arg.Builder.checkForHelpAndVersion
        |> Arg.Builder.updateParser \{ data, remainingArgs } ->
            Ok { data: mapper data, remainingArgs }
        |> Arg.Builder.intoParts

    config = {
        description,
        options,
        parameters,
        subcommands: HasSubcommands subcommands,
    }

    { name, config, parser }

## Check the first parameter passed to see if a subcommand was called.
getFirstArgToCheckForSubcommandCall :
    ArgParserState x,
    List (SubcommandParserConfig subState),
    (Result (SubcommandParserConfig subState) [NotFound] -> ArgParserResult (ArgParserState state))
    -> ArgParserResult (ArgParserState state)
getFirstArgToCheckForSubcommandCall = \{ remainingArgs, subcommandPath }, subcommandParsers, callback ->
    findSubcommand = \param ->
        subcommandParsers
        |> List.findFirst \sc -> Ok sc.name == param

    when List.first remainingArgs is
        Err ListWasEmpty -> callback (findSubcommand (Err NoValue))
        Ok firstArg ->
            when firstArg is
                Short short -> IncorrectUsage (UnrecognizedShortArg short) { subcommandPath }
                Long long -> IncorrectUsage (UnrecognizedLongArg long.name) { subcommandPath }
                ShortGroup sg -> IncorrectUsage (UnrecognizedShortArg (sg.names |> List.first |> Result.withDefault "")) { subcommandPath }
                Parameter p -> callback (findSubcommand (Ok p))

## Use previously defined subcommands as data in a parent CLI builder.
##
## Once all options have been parsed, we then check the first parameter
## passed to see if it's one of the provided subcommands. If so, we parse
## the remaining arguments as that subcommand's data, and otherwise continue
## parsing the current command.
##
## The [optional] function can only be used after all  `Opt` fields have been
## registered (if any) as we don't want to parse options for a subcommand
## instead of a parent, and cannot be used after any parameters have been
## registered. This is enforced using the type state pattern, where we encode
## the state of the program into its types. If you're curious, check the
## internal `Builder` module to see how this works using the `action` type
## variable.
##
## ```roc
## expect
##     fooSubcommand =
##         Cli.build {
##             foo: <- Opt.str { short: "f" },
##         }
##         |> Subcommand.finish { name: "foo", description: "Foo subcommand", mapper: Foo }
##
##     barSubcommand =
##         Cli.build {
##             bar: <- Opt.str { short: "b" },
##         }
##         |> Subcommand.finish { name: "bar", description: "Bar subcommand", mapper: Bar }
##
##     Cli.build {
##         sc: <- Subcommand.optional [fooSubcommand, barSubcommand],
##     }
##     |> Cli.finish { name: "example" }
##     |> Cli.assertValid
##     |> Cli.parseOrDisplayMessage ["example", "bar", "-b", "abc"]
##     == Ok { sc: Ok (Bar { b: "abc" }) }
## ```
optional : List (SubcommandParserConfig subState) -> (CliBuilder (Result subState [NoSubcommand] -> state) GetOptionsAction -> CliBuilder state GetParamsAction)
optional = \subcommandConfigs ->
    subcommands =
        subcommandConfigs
        |> List.map \{ name, config } -> (name, config)
        |> Dict.fromList

    \builder ->
        builder
        |> Arg.Builder.addSubcommands subcommands
        |> Arg.Builder.bindParser \{ data, remainingArgs, subcommandPath } ->
            subcommandFound <- getFirstArgToCheckForSubcommandCall { data, remainingArgs, subcommandPath } subcommandConfigs

            when subcommandFound is
                Err NotFound ->
                    SuccessfullyParsed { data: data (Err NoSubcommand), remainingArgs, subcommandPath }

                Ok subcommand ->
                    subParser =
                        { data: subData, remainingArgs: subRemainingArgs, subcommandPath: subSubcommandPath } <- onSuccessfulArgParse subcommand.parser
                        SuccessfullyParsed { data: data (Ok subData), remainingArgs: subRemainingArgs, subcommandPath: subSubcommandPath }

                    subParser {
                        args: List.dropFirst remainingArgs 1,
                        subcommandPath: subcommandPath |> List.append subcommand.name,
                    }

## Use previously defined subcommands as data in a parent CLI builder.
##
## Once all options have been parsed, we then check the first parameter
## passed to see if it's one of the provided subcommands. If so, we parse
## the remaining arguments as that subcommand's data, and otherwise we
## fail parsing.
##
## The [required] function can only be used after all  `Opt` fields have been
## registered (if any) as we don't want to parse options for a subcommand
## instead of a parent, and cannot be used after any parameters have been
## registered. This is enforced using the type state pattern, where we encode
## the state of the program into its types. If you're curious, check the
## internal `Builder` module to see how this works using the `action` type
## variable.
##
## ```roc
## expect
##     fooSubcommand =
##         Cli.build {
##             foo: <- Opt.str { short: "f" },
##         }
##         |> Subcommand.finish { name: "foo", description: "Foo subcommand", mapper: Foo }
##
##     barSubcommand =
##         Cli.build {
##             bar: <- Opt.str { short: "b" },
##         }
##         |> Subcommand.finish { name: "bar", description: "Bar subcommand", mapper: Bar }
##
##     Cli.build {
##         sc: <- Subcommand.required [fooSubcommand, barSubcommand],
##     }
##     |> Cli.finish { name: "example" }
##     |> Cli.assertValid
##     |> Cli.parseOrDisplayMessage ["example", "bar", "-b", "abc"]
##     == Ok { sc: Bar { b: "abc" } }
## ```
required : List (SubcommandParserConfig subState) -> (CliBuilder (subState -> state) GetOptionsAction -> CliBuilder state GetParamsAction)
required = \subcommandConfigs ->
    subcommands =
        subcommandConfigs
        |> List.map \{ name, config } -> (name, config)
        |> Dict.fromList

    \builder ->
        builder
        |> Arg.Builder.addSubcommands subcommands
        |> Arg.Builder.bindParser \{ data, remainingArgs, subcommandPath } ->
            subcommandFound <- getFirstArgToCheckForSubcommandCall { data, remainingArgs, subcommandPath } subcommandConfigs

            when subcommandFound is
                Err NotFound ->
                    IncorrectUsage NoSubcommandCalled { subcommandPath }

                Ok subcommand ->
                    subParser =
                        { data: subData, remainingArgs: subRemainingArgs, subcommandPath: subSubcommandPath } <- onSuccessfulArgParse subcommand.parser
                        SuccessfullyParsed { data: data subData, remainingArgs: subRemainingArgs, subcommandPath: subSubcommandPath }

                    subParser {
                        args: List.dropFirst remainingArgs 1,
                        subcommandPath: subcommandPath |> List.append subcommand.name,
                    }
