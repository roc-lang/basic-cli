module [helpText, usageHelp]

import Arg.Base exposing [
    TextStyle,
    CliConfig,
    OptionConfig,
    ParameterConfig,
    SubcommandConfig,
    SubcommandsConfig,
]
import Arg.Utils exposing [toUpperCase, strLen]

# TODO: use roc-ansi once module params fix importing packages
boldAnsiCode = "\u(001b)[1m"
boldAndUnderlineAnsiCode = "\u(001b)[1m\u(001b)[4m"
resetAnsiCode = "\u(001b)[0m"

## Walks the subcommand tree from the root CLI config and either
## returns the subcommand's config as if it were the root command if a
## subcommand is found, or just the root command's config otherwise.
findSubcommandOrDefault : CliConfig, List Str -> { config : CliConfig, subcommandPath : List Str }
findSubcommandOrDefault = \config, subcommandPath ->
    baseCommand = {
        description: config.description,
        options: config.options,
        parameters: config.parameters,
        subcommands: config.subcommands,
    }

    when findSubcommand baseCommand (List.dropFirst subcommandPath 1) is
        Err KeyNotFound -> { config, subcommandPath }
        Ok c ->
            {
                config: {
                    name: config.name,
                    version: config.version,
                    authors: config.authors,
                    description: c.description,
                    options: c.options,
                    parameters: c.parameters,
                    subcommands: c.subcommands,
                },
                subcommandPath,
            }

## Searches a command's config for subcommands recursively.
findSubcommand : SubcommandConfig, List Str -> Result SubcommandConfig [KeyNotFound]
findSubcommand = \command, path ->
    when path is
        [] -> Ok command
        [first, .. as rest] ->
            when command.subcommands is
                NoSubcommands -> Err KeyNotFound
                HasSubcommands scs ->
                    Dict.get scs first
                    |> Result.try \sc ->
                        findSubcommand sc rest

## Render the help text for a command at or under the root config.
##
## The second argument should be a list of subcommand names, e.g.
## `["example", "subcommand-1", "subcommand-2"]`. If the subcommand
## isn't found, the root command's help page is rendered by default.
##
## ```roc
## exampleCli =
##     Opt.count { short: "v", help: "How verbose our logs should be." }
##     |> Cli.finish {
##         name: "example",
##         version: "v0.1.0",
##         description: "An example CLI.",
##     }
##     |> Cli.assertValid
##
## expect
##     helpText exampleCli.config ["example"]
##     ==
##         """
##         example v0.1.0
##
##         An example CLI.
##
##         Usage:
##           example -v [OPTIONS]
##
##         Options:
##           -v             How verbose our logs should be.
##           -h, --help     Show this help page.
##           -V, --version  Show the version.
##         """
## ```
helpText : CliConfig, List Str, TextStyle -> Str
helpText = \baseConfig, path, textStyle ->
    { config, subcommandPath } = findSubcommandOrDefault baseConfig path
    { version, authors, description, options, parameters, subcommands } = config

    name = subcommandPath |> Str.joinWith " "

    topLine =
        [name, version]
        |> List.dropIf Str.isEmpty
        |> Str.joinWith " "

    authorsText =
        if List.isEmpty authors then
            ""
        else
            Str.concat "\n" (Str.joinWith authors " ")

    descriptionText =
        if Str.isEmpty description then
            ""
        else
            Str.concat "\n\n" description

    subcommandsText =
        when subcommands is
            HasSubcommands scs if !(Dict.isEmpty scs) ->
                commandsHelp subcommands textStyle

            _noSubcommands -> ""

    parametersText =
        if List.isEmpty parameters then
            ""
        else
            parametersHelp parameters textStyle

    optionsText =
        if List.isEmpty options then
            ""
        else
            optionsHelp options textStyle

    bottomSections =
        [subcommandsText, parametersText, optionsText]
        |> List.dropIf Str.isEmpty
        |> Str.joinWith "\n\n"

    (style, reset) =
        when textStyle is
            Color -> (boldAndUnderlineAnsiCode, resetAnsiCode)
            Plain -> ("", "")

    """
    $(style)$(topLine)$(reset)$(authorsText)$(descriptionText)

    $(usageHelp config subcommandPath textStyle)

    $(bottomSections)
    """

## Render just the usage text for a command at or under the root config.
##
## The second argument should be a list of subcommand names, e.g.
## `["example", "subcommand-1", "subcommand-2"]`. If the subcommand
## isn't found, the root command's usage text is rendered by default.
##
## ```roc
## exampleCli =
##     Opt.count { short: "v", help: "How verbose our logs should be." }
##     |> Cli.finish {
##         name: "example",
##         version: "v0.1.0",
##         description: "An example CLI.",
##     }
##     |> Cli.assertValid
##
## expect
##     helpText exampleCli.config ["example"]
##     ==
##         """
##         Usage:
##           example -v [OPTIONS]
##         """
## ```
usageHelp : CliConfig, List Str, TextStyle -> Str
usageHelp = \config, path, textStyle ->
    { config: { options, parameters, subcommands }, subcommandPath } = findSubcommandOrDefault config path

    name = Str.joinWith subcommandPath " "

    requiredOptions =
        options
        |> List.dropIf \opt -> opt.expectedValue == NothingExpected
        |> List.map optionSimpleNameFormatter

    otherOptions =
        if List.len requiredOptions == List.len options then
            []
        else
            ["[options]"]

    paramsStrings =
        parameters
        |> List.map \{ name: paramName, plurality } ->
            ellipsis =
                when plurality is
                    Optional | One -> ""
                    Many -> "..."

            "<$(paramName)$(ellipsis)>"

    firstLine =
        requiredOptions
        |> List.concat otherOptions
        |> List.concat paramsStrings
        |> Str.joinWith " "

    subcommandUsage =
        when subcommands is
            HasSubcommands sc if !(Dict.isEmpty sc) -> "\n  $(name) <COMMAND>"
            _other -> ""

    (style, reset) =
        when textStyle is
            Color -> (boldAndUnderlineAnsiCode, resetAnsiCode)
            Plain -> ("", "")

    """
    $(style)Usage:$(reset)
      $(name) $(firstLine)$(subcommandUsage)
    """

commandsHelp : SubcommandsConfig, TextStyle -> Str
commandsHelp = \subcommands, textStyle ->
    commands =
        when subcommands is
            NoSubcommands -> []
            HasSubcommands sc -> Dict.toList sc

    alignedCommands =
        commands
        |> List.map \(name, subConfig) ->
            (name, subConfig.description)
        |> alignTwoColumns textStyle

    (style, reset) =
        when textStyle is
            Color -> (boldAndUnderlineAnsiCode, resetAnsiCode)
            Plain -> ("", "")

    """
    $(style)Commands:$(reset)
    $(Str.joinWith alignedCommands "\n")
    """

parametersHelp : List ParameterConfig, TextStyle -> Str
parametersHelp = \params, textStyle ->
    formattedParams =
        params
        |> List.map \param ->
            ellipsis =
                when param.plurality is
                    Optional | One -> ""
                    Many -> "..."

            ("<$(param.name)$(ellipsis)>", param.help)
        |> alignTwoColumns textStyle

    (style, reset) =
        when textStyle is
            Color -> (boldAndUnderlineAnsiCode, resetAnsiCode)
            Plain -> ("", "")

    """
    $(style)Arguments:$(reset)
    $(Str.joinWith formattedParams "\n")
    """

optionNameFormatter : OptionConfig -> Str
optionNameFormatter = \{ short, long, expectedValue } ->
    shortName =
        if short != "" then
            "-$(short)"
        else
            ""

    longName =
        if long != "" then
            "--$(long)"
        else
            ""

    typeName =
        when expectedValue is
            NothingExpected -> ""
            ExpectsValue name -> " $(toUpperCase name)"

    [shortName, longName]
    |> List.dropIf Str.isEmpty
    |> List.map \name -> Str.concat name typeName
    |> Str.joinWith ", "

optionSimpleNameFormatter : OptionConfig -> Str
optionSimpleNameFormatter = \{ short, long, expectedValue } ->
    shortName =
        if short != "" then
            "-$(short)"
        else
            ""

    longName =
        if long != "" then
            "--$(long)"
        else
            ""

    typeName =
        when expectedValue is
            NothingExpected -> ""
            ExpectsValue name -> " $(toUpperCase name)"

    [shortName, longName]
    |> List.dropIf Str.isEmpty
    |> Str.joinWith "/"
    |> Str.concat typeName

optionsHelp : List OptionConfig, TextStyle -> Str
optionsHelp = \options, textStyle ->
    formattedOptions =
        options
        |> List.map \option ->
            (optionNameFormatter option, option.help)
        |> alignTwoColumns textStyle

    (style, reset) =
        when textStyle is
            Color -> (boldAndUnderlineAnsiCode, resetAnsiCode)
            Plain -> ("", "")

    """
    $(style)Options:$(reset)
    $(Str.joinWith formattedOptions "\n")
    """

indentMultilineStringBy : Str, U64 -> Str
indentMultilineStringBy = \string, indentAmount ->
    indentation = Str.repeat " " indentAmount

    string
    |> Str.split "\n"
    |> List.mapWithIndex \line, index ->
        if index == 0 then
            line
        else
            Str.concat indentation line
    |> Str.joinWith "\n"

alignTwoColumns : List (Str, Str), TextStyle -> List Str
alignTwoColumns = \columns, textStyle ->
    maxFirstColumnLen =
        columns
        |> List.map \(first, _second) -> strLen first
        |> List.max
        |> Result.withDefault 0

    (style, reset) =
        when textStyle is
            Color -> (boldAnsiCode, resetAnsiCode)
            Plain -> ("", "")

    List.map columns \(first, second) ->
        buffer =
            Str.repeat " " (maxFirstColumnLen - strLen first)
        secondShifted =
            indentMultilineStringBy second (maxFirstColumnLen + 4)

        "  $(style)$(first)$(buffer)$(reset)  $(secondShifted)"
