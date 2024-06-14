module [
    GetOptionsAction,
    GetParamsAction,
    StopCollectingAction,
    CliBuilder,
    fromState,
    addOptions,
    addParameters,
    addSubcommands,
    updateParser,
    bindParser,
    intoParts,
    checkForHelpAndVersion,
]

import Arg.Base exposing [
    ArgParser,
    ArgParserState,
    ArgParserResult,
    onSuccessfulArgParse,
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

CliBuilder state action := {
    parser : ArgParser state,
    options : List OptionConfig,
    parameters : List ParameterConfig,
    subcommands : Dict Str SubcommandConfig,
}

fromState : base -> CliBuilder base GetOptionsAction
fromState = \base ->
    @CliBuilder {
        parser: \{ args, subcommandPath } -> SuccessfullyParsed { data: base, remainingArgs: args, subcommandPath },
        options: [],
        parameters: [],
        subcommands: Dict.empty {},
    }

addOptions : CliBuilder state action, List OptionConfig -> CliBuilder state action
addOptions = \@CliBuilder builder, newOptions ->
    @CliBuilder { builder & options: List.concat builder.options newOptions }

addParameters : CliBuilder state action, List ParameterConfig -> CliBuilder state action
addParameters = \@CliBuilder builder, newParameters ->
    @CliBuilder { builder & parameters: List.concat builder.parameters newParameters }

addSubcommands : CliBuilder state action, Dict Str SubcommandConfig -> CliBuilder state action
addSubcommands = \@CliBuilder builder, newSubcommands ->
    @CliBuilder { builder & subcommands: Dict.insertAll builder.subcommands newSubcommands }

setParser : CliBuilder state action, ArgParser nextState -> CliBuilder nextState nextAction
setParser = \@CliBuilder builder, parser ->
    @CliBuilder {
        options: builder.options,
        parameters: builder.parameters,
        subcommands: builder.subcommands,
        parser,
    }

updateParser : CliBuilder state action, ({ data : state, remainingArgs : List Arg } -> Result { data : nextState, remainingArgs : List Arg } ArgExtractErr) -> CliBuilder nextState nextAction
updateParser = \@CliBuilder builder, updater ->
    newParser =
        { data, remainingArgs, subcommandPath } <- onSuccessfulArgParse builder.parser
        when updater { data, remainingArgs } is
            Err err -> IncorrectUsage err { subcommandPath }
            Ok { data: updatedData, remainingArgs: restOfArgs } ->
                SuccessfullyParsed { data: updatedData, remainingArgs: restOfArgs, subcommandPath }

    setParser (@CliBuilder builder) newParser

bindParser : CliBuilder state action, (ArgParserState state -> ArgParserResult (ArgParserState nextState)) -> CliBuilder nextState nextAction
bindParser = \@CliBuilder builder, updater ->
    newParser : ArgParser nextState
    newParser =
        { data, remainingArgs, subcommandPath } <- onSuccessfulArgParse builder.parser
        updater { data, remainingArgs, subcommandPath }

    setParser (@CliBuilder builder) newParser

intoParts :
    CliBuilder state action
    -> {
        parser : ArgParser state,
        options : List OptionConfig,
        parameters : List ParameterConfig,
        subcommands : Dict Str SubcommandConfig,
    }
intoParts = \@CliBuilder builder -> builder

flagWasPassed : OptionConfig, List Arg -> Bool
flagWasPassed = \option, args ->
    List.any args \arg ->
        when arg is
            Short short -> short == option.short
            ShortGroup sg -> List.any sg.names \n -> n == option.short
            Long long -> long.name == option.long
            Parameter _p -> Bool.false

checkForHelpAndVersion : CliBuilder state action -> CliBuilder state action
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
        fromState (\x -> { x })
        |> updateParser \{ data, remainingArgs } -> Ok { data: data (Inspect.toStr remainingArgs), remainingArgs: [] }
        |> intoParts

    out = parser { args: [Parameter "123"], subcommandPath: [] }

    out
    == SuccessfullyParsed {
        data: { x: "[(Parameter \"123\")]" },
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
