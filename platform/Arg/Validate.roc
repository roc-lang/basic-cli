module [validateCli, CliValidationErr]

import Arg.Utils exposing [strLen, isKebabCase]
import Arg.Base exposing [
    OptionConfig,
    helpOption,
    versionOption,
    ParameterConfig,
    SubcommandsConfig,
    CliConfig,
]

OptionAtSubcommand : { option : OptionConfig, subcommandPath : List Str }

## The types of errors that might be found in a misconfigured CLI.
CliValidationErr : [
    OverlappingParameterNames { first : Str, second : Str, subcommandPath : List Str },
    OverlappingOptionNames OptionAtSubcommand OptionAtSubcommand,
    InvalidShortFlagName { name : Str, subcommandPath : List Str },
    InvalidLongFlagName { name : Str, subcommandPath : List Str },
    InvalidCommandName { name : Str, subcommandPath : List Str },
    InvalidParameterName { name : Str, subcommandPath : List Str },
    OptionMustHaveShortOrLongName { subcommandPath : List Str },
    InvalidOptionValueType { option : OptionConfig, subcommandPath : List Str },
    InvalidParameterValueType { param : ParameterConfig, subcommandPath : List Str },
    OverrodeSpecialHelpFlag { option : OptionConfig, subcommandPath : List Str },
    OverrodeSpecialVersionFlag { option : OptionConfig, subcommandPath : List Str },
]

## Ensure that a CLI's configuration is valid.
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
## - No options can overlap, even between different subcommands, so long
##   as the options between the subcommands are ambiguous.
##   - For example, a CLI with a `-t` option at the root level and also
##     a `-t` option in the subcommand `sub` would fail validation since
##     we wouldn't know who should get the `-t` option.
##   - However, a CLI with two subcommands that each have a `-t` option
##     would not fail validation since only one subcommand can be called
##     at once.
validateCli : CliConfig -> Result {} CliValidationErr
validateCli = \{ name, options, parameters, subcommands } ->
    validateCommand {
        name,
        options,
        parentOptions: [],
        parameters,
        subcommands,
        subcommandPath: [name],
    }

validateCommand :
    {
        name : Str,
        options : List OptionConfig,
        parentOptions : List OptionAtSubcommand,
        parameters : List ParameterConfig,
        subcommands : SubcommandsConfig,
        subcommandPath : List Str,
    }
    -> Result {} CliValidationErr
validateCommand = \{ name, options, parentOptions, parameters, subcommands, subcommandPath } ->

    ensureCommandIsWellNamed? { name, subcommandPath }

    _ =
        options
        |> List.mapTry? \option ->
            ensureOptionIsWellNamed? { option, subcommandPath }
            ensureOptionValueTypeIsWellNamed? { option, subcommandPath }

            Ok {}

    _ =
        parameters
        |> List.mapTry? \param ->
            ensureParamIsWellNamed? { name: param.name, subcommandPath }
            ensureParamValueTypeIsWellNamed? { param, subcommandPath }

            Ok {}

    checkIfThereAreOverlappingParameters? parameters subcommandPath

    when subcommands is
        HasSubcommands subcommandConfigs if !(Dict.isEmpty subcommandConfigs) ->
            subcommandConfigs
            |> Dict.toList
            |> List.mapTry \(subcommandName, subcommand) ->
                updatedParentOptions =
                    options
                    |> List.map \option -> { option, subcommandPath }
                    |> List.concat parentOptions

                validateCommand {
                    name: subcommandName,
                    options: subcommand.options,
                    parentOptions: updatedParentOptions,
                    parameters: subcommand.parameters,
                    subcommands: subcommand.subcommands,
                    subcommandPath: subcommandPath |> List.append subcommandName,
                }
            |> Result.map \_successes -> {}

        _noSubcommands ->
            allOptionsToCheck =
                options
                |> List.map \option -> { option, subcommandPath }
                |> List.concat parentOptions

            checkIfThereAreOverlappingOptions allOptionsToCheck

ensureCommandIsWellNamed : { name : Str, subcommandPath : List Str } -> Result {} CliValidationErr
ensureCommandIsWellNamed = \{ name, subcommandPath } ->
    if isKebabCase name then
        Ok {}
    else
        Err (InvalidCommandName { name, subcommandPath })

ensureParamIsWellNamed : { name : Str, subcommandPath : List Str } -> Result {} CliValidationErr
ensureParamIsWellNamed = \{ name, subcommandPath } ->
    if isKebabCase name then
        Ok {}
    else
        Err (InvalidParameterName { name, subcommandPath })

ensureOptionIsWellNamed : { option : OptionConfig, subcommandPath : List Str } -> Result {} CliValidationErr
ensureOptionIsWellNamed = \{ option, subcommandPath } ->
    when (option.short, option.long) is
        ("", "") -> Err (OptionMustHaveShortOrLongName { subcommandPath })
        (short, "") -> ensureShortFlagIsWellNamed { name: short, subcommandPath }
        ("", long) -> ensureLongFlagIsWellNamed { name: long, subcommandPath }
        (short, long) ->
            ensureShortFlagIsWellNamed { name: short, subcommandPath }
            |> Result.try \{} -> ensureLongFlagIsWellNamed { name: long, subcommandPath }

ensureOptionValueTypeIsWellNamed : { option : OptionConfig, subcommandPath : List Str } -> Result {} CliValidationErr
ensureOptionValueTypeIsWellNamed = \{ option, subcommandPath } ->
    when option.expectedValue is
        ExpectsValue typeName ->
            if isKebabCase typeName then
                Ok {}
            else
                Err (InvalidOptionValueType { option, subcommandPath })

        NothingExpected ->
            Ok {}

ensureParamValueTypeIsWellNamed : { param : ParameterConfig, subcommandPath : List Str } -> Result {} CliValidationErr
ensureParamValueTypeIsWellNamed = \{ param, subcommandPath } ->
    if isKebabCase param.type then
        Ok {}
    else
        Err (InvalidParameterValueType { param, subcommandPath })

ensureShortFlagIsWellNamed : { name : Str, subcommandPath : List Str } -> Result {} CliValidationErr
ensureShortFlagIsWellNamed = \{ name, subcommandPath } ->
    if strLen name != 1 then
        Err (InvalidShortFlagName { name, subcommandPath })
    else
        Ok {}

ensureLongFlagIsWellNamed : { name : Str, subcommandPath : List Str } -> Result {} CliValidationErr
ensureLongFlagIsWellNamed = \{ name, subcommandPath } ->
    if strLen name > 1 && isKebabCase name then
        Ok {}
    else
        Err (InvalidLongFlagName { name, subcommandPath })

ensureOptionNamesDoNotOverlap : OptionAtSubcommand, OptionAtSubcommand -> Result {} CliValidationErr
ensureOptionNamesDoNotOverlap = \left, right ->
    sameCommand = left.subcommandPath == right.subcommandPath
    eitherNameMatches =
        (left.option.short != "" && left.option.short == right.option.short)
        || (left.option.long != "" && left.option.long == right.option.long)

    matchesHelp =
        left.option.short == helpOption.short || left.option.long == helpOption.long
    matchesVersion =
        left.option.short == versionOption.short || left.option.long == versionOption.long

    if eitherNameMatches then
        if matchesHelp then
            if sameCommand then
                Err (OverrodeSpecialHelpFlag left)
            else
                Ok {}
        else if matchesVersion then
            if sameCommand then
                Err (OverrodeSpecialVersionFlag right)
            else
                Ok {}
        else
            Err (OverlappingOptionNames left right)
    else
        Ok {}

checkIfThereAreOverlappingOptions : List OptionAtSubcommand -> Result {} CliValidationErr
checkIfThereAreOverlappingOptions = \options ->
    List.range { start: At 1, end: Before (List.len options) }
    |> List.map \offset ->
        List.map2 options (List.dropFirst options offset) Pair
    |> List.mapTry \pairs ->
        pairs
        |> List.mapTry \Pair left right ->
            ensureOptionNamesDoNotOverlap left right
    |> Result.map \_sucesses -> {}

checkIfThereAreOverlappingParameters : List ParameterConfig, List Str -> Result {} CliValidationErr
checkIfThereAreOverlappingParameters = \parameters, subcommandPath ->
    List.range { start: At 1, end: Before (List.len parameters) }
    |> List.map \offset ->
        List.map2 parameters (List.dropFirst parameters offset) Pair
    |> List.mapTry \pairs ->
        pairs
        |> List.mapTry \Pair first second ->
            if first.name == second.name then
                Err (OverlappingParameterNames { first: first.name, second: second.name, subcommandPath })
            else
                Ok {}
    |> Result.map \_sucesses -> {}
