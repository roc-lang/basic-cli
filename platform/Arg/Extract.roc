module [extractParamValues, extractOptionValues]

import Arg.Base exposing [ArgExtractErr, OptionConfig, ParameterConfig]
import Arg.Parser exposing [Arg, ArgValue]

ExtractParamValuesParams : {
    args : List Arg,
    param : ParameterConfig,
}

ExtractParamValuesState : {
    action : [GetParam, StopParsing],
    values : List Str,
    remainingArgs : List Arg,
}

ExtractParamValuesOutput : {
    values : List Str,
    remainingArgs : List Arg,
}

extractParamValues : ExtractParamValuesParams -> Result ExtractParamValuesOutput ArgExtractErr
extractParamValues = \{ args, param } ->
    startingState = {
        action: GetParam,
        values: [],
        remainingArgs: [],
    }

    stateAfter =
        args
        |> List.walkTry startingState \state, arg ->
            when state.action is
                GetParam -> extractSingleParam state param arg
                StopParsing -> Ok { state & remainingArgs: state.remainingArgs |> List.append arg }

    Result.map stateAfter \{ values, remainingArgs } ->
        { values, remainingArgs }

extractSingleParam : ExtractParamValuesState, ParameterConfig, Arg -> Result ExtractParamValuesState ArgExtractErr
extractSingleParam = \state, param, arg ->
    when arg is
        Short short ->
            Err (UnrecognizedShortArg short)

        ShortGroup group ->
            name =
                group.names
                |> List.first
                |> Result.withDefault ""

            Err (UnrecognizedShortArg name)

        Long long ->
            Err (UnrecognizedLongArg long.name)

        Parameter p ->
            when param.plurality is
                Optional | One -> Ok { state & action: StopParsing, values: state.values |> List.append p }
                Many -> Ok { state & values: state.values |> List.append p }

ExtractOptionValuesParams : {
    args : List Arg,
    option : OptionConfig,
}

ExtractOptionValuesOutput : {
    values : List ArgValue,
    remainingArgs : List Arg,
}

ExtractOptionValueWalkerState : {
    action : [FindOption, GetValue],
    values : List ArgValue,
    remainingArgs : List Arg,
}

extractOptionValues : ExtractOptionValuesParams -> Result ExtractOptionValuesOutput ArgExtractErr
extractOptionValues = \{ args, option } ->
    startingState = {
        action: FindOption,
        values: [],
        remainingArgs: [],
    }

    stateAfter = List.walkTry args startingState \state, arg ->
        when state.action is
            FindOption -> findOptionForExtraction state arg option
            GetValue -> getValueForExtraction state arg option

    when stateAfter is
        Err err -> Err err
        Ok { action, values, remainingArgs } ->
            when action is
                GetValue -> Err (NoValueProvidedForOption option)
                FindOption -> Ok { values, remainingArgs }

findOptionForExtraction : ExtractOptionValueWalkerState, Arg, OptionConfig -> Result ExtractOptionValueWalkerState ArgExtractErr
findOptionForExtraction = \state, arg, option ->
    when arg is
        Short short ->
            if short == option.short then
                if option.expectedValue == NothingExpected then
                    Ok { state & values: state.values |> List.append (Err NoValue) }
                else
                    Ok { state & action: GetValue }
            else
                Ok { state & remainingArgs: state.remainingArgs |> List.append arg }

        ShortGroup shortGroup ->
            findOptionsInShortGroup state option shortGroup

        Long long ->
            if long.name == option.long then
                if option.expectedValue == NothingExpected then
                    when long.value is
                        Ok _val -> Err (OptionDoesNotExpectValue option)
                        Err NoValue -> Ok { state & values: state.values |> List.append (Err NoValue) }
                else
                    when long.value is
                        Ok val -> Ok { state & values: state.values |> List.append (Ok val) }
                        Err NoValue -> Ok { state & action: GetValue }
            else
                Ok { state & remainingArgs: state.remainingArgs |> List.append arg }

        _nothingFound ->
            Ok { state & remainingArgs: state.remainingArgs |> List.append arg }

findOptionsInShortGroup : ExtractOptionValueWalkerState, OptionConfig, { names : List Str, complete : [Partial, Complete] } -> Result ExtractOptionValueWalkerState ArgExtractErr
findOptionsInShortGroup = \state, option, shortGroup ->
    stateAfter =
        shortGroup.names
        |> List.walkTry { action: FindOption, remaining: [], values: [] } \sgState, name ->
            when sgState.action is
                GetValue -> Err (CannotUsePartialShortGroupAsValue option shortGroup.names)
                FindOption ->
                    if name == option.short then
                        if option.expectedValue == NothingExpected then
                            Ok { sgState & values: sgState.values |> List.append (Err NoValue) }
                        else
                            Ok { sgState & action: GetValue }
                    else
                        Ok sgState

    when stateAfter is
        Err err -> Err err
        Ok { action, remaining, values } ->
            restOfGroup =
                if List.isEmpty values then
                    Ok (ShortGroup shortGroup)
                else if List.isEmpty remaining then
                    Err NoValue
                else
                    Ok (ShortGroup { complete: Partial, names: remaining })

            Ok
                { state &
                    action,
                    remainingArgs: state.remainingArgs |> List.appendIfOk restOfGroup,
                    values: state.values |> List.concat values,
                }

getValueForExtraction : ExtractOptionValueWalkerState, Arg, OptionConfig -> Result ExtractOptionValueWalkerState ArgExtractErr
getValueForExtraction = \state, arg, option ->
    value =
        when arg is
            Short s -> Ok "-$(s)"
            ShortGroup { names, complete: Complete } -> Ok "-$(Str.joinWith names "")"
            ShortGroup { names, complete: Partial } -> Err (CannotUsePartialShortGroupAsValue option names)
            Long { name, value: Ok val } -> Ok "--$(name)=$(val)"
            Long { name, value: Err NoValue } -> Ok "--$(name)"
            Parameter p -> Ok p

    Result.map value \val ->
        { state & action: FindOption, values: state.values |> List.append (Ok val) }
