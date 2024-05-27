module [
    ArgParserResult,
    ArgParserParams,
    ArgParserState,
    ArgParser,
    onSuccessfulArgParse,
    mapSuccessfullyParsed,
    ArgExtractErr,
    strTypeName,
    numTypeName,
    TextStyle,
    ExpectedValue,
    Plurality,
    SpecialFlags,
    InvalidValue,
    ValueParser,
    OptionConfigBaseParams,
    OptionConfigParams,
    OptionConfig,
    helpOption,
    versionOption,
    ParameterConfigBaseParams,
    ParameterConfigParams,
    ParameterConfig,
    CliConfigParams,
    CliConfig,
    SubcommandConfigParams,
    SubcommandConfig,
    SubcommandsConfig,
]

import Arg.Parser exposing [Arg]

## The result of attempting to parse args into config data.
ArgParserResult a : [
    ShowHelp { subcommandPath : List Str },
    ShowVersion,
    IncorrectUsage ArgExtractErr { subcommandPath : List Str },
    SuccessfullyParsed a,
]

## The parameters that an [ArgParser] takes to extract data
## from args.
ArgParserParams : { args : List Arg, subcommandPath : List Str }

## The intermediate state that an [ArgParser] passes between
## different parsing steps.
ArgParserState a : { data : a, remainingArgs : List Arg, subcommandPath : List Str }

## A function that takes command line arguments and a subcommand,
## and attempts to extract configuration data from said arguments.
ArgParser a : ArgParserParams -> ArgParserResult (ArgParserState a)

## A bind operation for [ArgParserState].
##
## If an [ArgParser] successfully parses some data, then said data
## is provided to a callback and the resulting [ArgParserResult] is
## passed along in the newly bound [ArgParser].
onSuccessfulArgParse : ArgParser a, (ArgParserState a -> ArgParserResult (ArgParserState b)) -> ArgParser b
onSuccessfulArgParse = \result, mapper ->
    \input ->
        when result input is
            ShowVersion -> ShowVersion
            ShowHelp { subcommandPath } -> ShowHelp { subcommandPath }
            IncorrectUsage argExtractErr { subcommandPath } -> IncorrectUsage argExtractErr { subcommandPath }
            SuccessfullyParsed { data, remainingArgs, subcommandPath } ->
                mapper { data, remainingArgs, subcommandPath }

## Maps successfully parsed data that was parsed by an [ArgParser]
## by a user-defined operation.
mapSuccessfullyParsed : ArgParserResult a, (a -> b) -> ArgParserResult b
mapSuccessfullyParsed = \result, mapper ->
    when result is
        ShowVersion -> ShowVersion
        ShowHelp { subcommandPath } -> ShowHelp { subcommandPath }
        IncorrectUsage argExtractErr { subcommandPath } -> IncorrectUsage argExtractErr { subcommandPath }
        SuccessfullyParsed parsed ->
            SuccessfullyParsed (mapper parsed)

## Errors that can occur while extracting values from command line arguments.
ArgExtractErr : [
    NoSubcommandCalled,
    MissingOption OptionConfig,
    OptionCanOnlyBeSetOnce OptionConfig,
    NoValueProvidedForOption OptionConfig,
    OptionDoesNotExpectValue OptionConfig,
    CannotUsePartialShortGroupAsValue OptionConfig (List Str),
    InvalidOptionValue InvalidValue OptionConfig,
    InvalidParamValue InvalidValue ParameterConfig,
    MissingParam ParameterConfig,
    UnrecognizedShortArg Str,
    UnrecognizedLongArg Str,
    ExtraParamProvided Str,
]

strTypeName = "str"
numTypeName = "num"

## Whether help text should have fancy styling.
TextStyle : [Color, Plain]

## The type of value that an option expects to parse.
ExpectedValue : [ExpectsValue Str, NothingExpected]

## How many values an option/parameter can take.
Plurality : [Optional, One, Many]

## The two built-in flags that we parse automatically.
SpecialFlags : { help : Bool, version : Bool }

InvalidValue : [InvalidNumStr, InvalidValue Str]

## A parser that extracts an argument value from a string.
ValueParser a : Str -> Result a InvalidValue

OptionConfigBaseParams : {
    short ? Str,
    long ? Str,
    help ? Str,
}

## Default-value options for creating an option.
OptionConfigParams a : {
    short ? Str,
    long ? Str,
    help ? Str,
    type : Str,
    parser : ValueParser a,
}

## Metadata for options in our CLI building system.
OptionConfig : {
    expectedValue : ExpectedValue,
    plurality : Plurality,
    short : Str,
    long : Str,
    help : Str,
}

## Metadata for the `-h/--help` option that we parse automatically.
helpOption : OptionConfig
helpOption = {
    short: "h",
    long: "help",
    help: "Show this help page.",
    expectedValue: NothingExpected,
    plurality: Optional,
}

## Metadata for the `-V/--version` option that we parse automatically.
versionOption : OptionConfig
versionOption = {
    short: "V",
    long: "version",
    help: "Show the version.",
    expectedValue: NothingExpected,
    plurality: Optional,
}

ParameterConfigBaseParams : {
    name : Str,
    help ? Str,
}

## Default-value options for creating an parameter.
ParameterConfigParams a : {
    name : Str,
    help ? Str,
    type : Str,
    parser : ValueParser a,
}

## Metadata for parameters in our CLI building system.
ParameterConfig : {
    name : Str,
    help : Str,
    type : Str,
    plurality : Plurality,
}

## Default-value options for bundling an CLI.
CliConfigParams : {
    name : Str,
    authors ? List Str,
    version ? Str,
    description ? Str,
    textStyle ? TextStyle,
}

## Metadata for a root-level CLI.
CliConfig : {
    name : Str,
    authors : List Str,
    version : Str,
    description : Str,
    subcommands : SubcommandsConfig,
    options : List OptionConfig,
    parameters : List ParameterConfig,
}

## Default-value options for bundling a subcommand.
SubcommandConfigParams : {
    name : Str,
    description ? Str,
}

## Metadata for a set of subcommands under a parent command.
##
## Since subcommands can have their own sub-subcommands,
## this type alias needs to be an enum with an empty variant
## to avoid infinite recursion.
SubcommandsConfig : [
    NoSubcommands,
    HasSubcommands
        (Dict Str {
            description : Str,
            subcommands : SubcommandsConfig,
            options : List OptionConfig,
            parameters : List ParameterConfig,
        }),
]

## Metadata for a subcommand.
SubcommandConfig : {
    description : Str,
    subcommands : SubcommandsConfig,
    options : List OptionConfig,
    parameters : List ParameterConfig,
}
