module [
    GetOptionsAction,
    GetParamsAction,
    StopCollectingAction,
    CliBuilder,
    fromArgParser,
    fromFullParser,
    addOption,
    addParameter,
    addSubcommands,
    updateParser,
    map,
    combine,
    intoParts,
    checkForHelpAndVersion,
]

import Arg.Base exposing [
    ArgParser,
    onSuccessfulArgParse,
    mapSuccessfullyParsed,
    ArgExtractErr,
    OptionConfig,
    helpOption,
    versionOption,
    ParameterConfig,
    SubcommandConfig,
]
import Arg.Parser exposing [Arg]

GetOptionsAction : { getOptions : {} }
GetParamsAction : { getParams : {} }
StopCollectingAction : []

CliBuilder data fromAction toAction := {
    parser : ArgParser data,
    options : List OptionConfig,
    parameters : List ParameterConfig,
    subcommands : Dict Str SubcommandConfig,
}

fromArgParser : (List Arg -> Result { data : data, remainingArgs : List Arg } ArgExtractErr) -> CliBuilder data fromAction toAction
fromArgParser = \parser ->
    newParser = \{ args, subcommandPath } ->
        when parser args is
            Ok { data, remainingArgs } -> SuccessfullyParsed { data, remainingArgs, subcommandPath }
            Err err -> IncorrectUsage err { subcommandPath }

    @CliBuilder {
        parser: newParser,
        options: [],
        parameters: [],
        subcommands: Dict.empty {},
    }

fromFullParser : ArgParser data -> CliBuilder data fromAction toAction
fromFullParser = \parser ->
    @CliBuilder {
        parser,
        options: [],
        parameters: [],
        subcommands: Dict.empty {},
    }

addOption : CliBuilder state fromAction toAction, OptionConfig -> CliBuilder state fromAction toAction
addOption = \@CliBuilder builder, newOption ->
    @CliBuilder { builder & options: List.append builder.options newOption }

addParameter : CliBuilder state fromAction toAction, ParameterConfig -> CliBuilder state fromAction toAction
addParameter = \@CliBuilder builder, newParameter ->
    @CliBuilder { builder & parameters: List.append builder.parameters newParameter }

addSubcommands : CliBuilder state fromAction toAction, Dict Str SubcommandConfig -> CliBuilder state fromAction toAction
addSubcommands = \@CliBuilder builder, newSubcommands ->
    @CliBuilder { builder & subcommands: Dict.insertAll builder.subcommands newSubcommands }

setParser : CliBuilder state fromAction toAction, ArgParser nextState -> CliBuilder nextState fromAction toAction
setParser = \@CliBuilder builder, parser ->
    @CliBuilder {
        options: builder.options,
        parameters: builder.parameters,
        subcommands: builder.subcommands,
        parser,
    }

updateParser : CliBuilder state fromAction toAction, ({ data : state, remainingArgs : List Arg } -> Result { data : nextState, remainingArgs : List Arg } ArgExtractErr) -> CliBuilder nextState fromAction toAction
updateParser = \@CliBuilder builder, updater ->
    newParser =
        onSuccessfulArgParse builder.parser \{ data, remainingArgs, subcommandPath } ->
            when updater { data, remainingArgs } is
                Err err -> IncorrectUsage err { subcommandPath }
                Ok { data: updatedData, remainingArgs: restOfArgs } ->
                    SuccessfullyParsed { data: updatedData, remainingArgs: restOfArgs, subcommandPath }

    setParser (@CliBuilder builder) newParser

intoParts :
    CliBuilder state fromAction toAction
    -> {
        parser : ArgParser state,
        options : List OptionConfig,
        parameters : List ParameterConfig,
        subcommands : Dict Str SubcommandConfig,
    }
intoParts = \@CliBuilder builder -> builder

map : CliBuilder a fromAction toAction, (a -> b) -> CliBuilder b fromAction toAction
map = \@CliBuilder builder, mapper ->
    combinedParser = \input ->
        builder.parser input
        |> mapSuccessfullyParsed \{ data, remainingArgs, subcommandPath } ->
            { data: mapper data, remainingArgs, subcommandPath }

    @CliBuilder {
        parser: combinedParser,
        options: builder.options,
        parameters: builder.parameters,
        subcommands: builder.subcommands,
    }

combine : CliBuilder a action1 action2, CliBuilder b action2 action3, (a, b -> c) -> CliBuilder c action1 action3
combine = \@CliBuilder left, @CliBuilder right, combiner ->
    combinedParser =
        onSuccessfulArgParse left.parser \firstResult ->
            innerParser =
                onSuccessfulArgParse right.parser \{ data: secondData, remainingArgs, subcommandPath } ->
                    SuccessfullyParsed {
                        data: combiner firstResult.data secondData,
                        remainingArgs,
                        subcommandPath,
                    }

            innerParser { args: firstResult.remainingArgs, subcommandPath: firstResult.subcommandPath }

    @CliBuilder {
        parser: combinedParser,
        options: List.concat left.options right.options,
        parameters: List.concat left.parameters right.parameters,
        subcommands: Dict.insertAll left.subcommands right.subcommands,
    }

flagWasPassed : OptionConfig, List Arg -> Bool
flagWasPassed = \option, args ->
    List.any args \arg ->
        when arg is
            Short short -> short == option.short
            ShortGroup sg -> List.any sg.names \n -> n == option.short
            Long long -> long.name == option.long
            Parameter _p -> Bool.false

checkForHelpAndVersion : CliBuilder state fromAction toAction -> CliBuilder state fromAction toAction
checkForHelpAndVersion = \@CliBuilder builder ->
    newParser = \{ args, subcommandPath } ->
        when builder.parser { args, subcommandPath } is
            ShowHelp sp -> ShowHelp sp
            ShowVersion -> ShowVersion
            other ->
                if flagWasPassed helpOption args then
                    ShowHelp { subcommandPath }
                else if flagWasPassed versionOption args then
                    ShowVersion
                else
                    other

    @CliBuilder {
        options: builder.options |> List.concat [helpOption, versionOption],
        parameters: builder.parameters,
        subcommands: builder.subcommands,
        parser: newParser,
    }

expect
    { parser } =
        fromArgParser \args -> Ok { data: Inspect.toStr args, remainingArgs: [] }
        |> map Inspected
        |> intoParts

    out = parser { args: [Parameter "123"], subcommandPath: [] }

    out
    == SuccessfullyParsed {
        data: Inspected "[(Parameter \"123\")]",
        remainingArgs: [],
        subcommandPath: [],
    }

expect
    args = [Parameter "-h"]

    flagWasPassed helpOption args |> Bool.not

expect
    args = [Short "h"]

    flagWasPassed helpOption args

expect
    args = [Long { name: "help", value: Err NoValue }]

    flagWasPassed helpOption args

expect
    args = [Long { name: "help", value: Ok "123" }]

    flagWasPassed helpOption args
