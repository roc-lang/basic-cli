module [parseArgs, Arg, ArgValue]

Arg : [
    Short Str,
    ShortGroup { names : List Str, complete : [Complete, Partial] },
    Long { name : Str, value : Result Str [NoValue] },
    Parameter Str,
]

ArgValue : Result Str [NoValue]

parseArgs : List Str -> List Arg
parseArgs = \args ->
    startingState = { parsedArgs: [], passThrough: KeepParsing }

    stateAfter =
        args
        |> List.dropFirst 1
        |> List.walk startingState \{ parsedArgs, passThrough }, arg ->
            when passThrough is
                KeepParsing ->
                    parsedArg = parseArg arg
                    when parsedArg is
                        Parameter "--" ->
                            { passThrough: PassThrough, parsedArgs }

                        _other ->
                            { passThrough: KeepParsing, parsedArgs: parsedArgs |> List.append parsedArg }

                PassThrough ->
                    {
                        passThrough: PassThrough,
                        parsedArgs: parsedArgs |> List.append (Parameter arg),
                    }

    stateAfter.parsedArgs

parseArg : Str -> Arg
parseArg = \arg ->
    when Str.splitFirst arg "-" is
        Ok { before: "", after } ->
            if after == "" then
                Parameter "-"
            else
                when Str.splitFirst after "-" is
                    Ok { before: "", after: rest } ->
                        if rest == "" || Str.startsWith rest "-" then
                            Parameter arg
                        else
                            parseLongArg rest

                    _other -> constructSetOfOptions after

        _other ->
            Parameter arg

parseLongArg : Str -> Arg
parseLongArg = \arg ->
    when Str.splitFirst arg "=" is
        Ok { before: option, after: value } ->
            Long { name: option, value: Ok value }

        _other ->
            Long { name: arg, value: Err NoValue }

constructSetOfOptions : Str -> Arg
constructSetOfOptions = \combined ->
    options =
        combined
        |> Str.toUtf8
        |> List.keepOks \c -> Str.fromUtf8 [c]

    when options is
        [alone] -> Short alone
        other -> ShortGroup { names: other, complete: Complete }

expect
    parsed = parseArg "-"

    parsed == Parameter "-"

expect
    parsed = parseArg "-a"

    parsed == Short "a"

expect
    parsed = parseArg "-abc"

    parsed == ShortGroup { names: ["a", "b", "c"], complete: Complete }

expect
    parsed = parseArg "--abc"

    parsed == Long { name: "abc", value: Err NoValue }

expect
    parsed = parseArg "--abc=xyz"

    parsed == Long { name: "abc", value: Ok "xyz" }

expect
    parsed = parseArg "123"

    parsed == Parameter "123"

expect
    parsed = parseArgs ["this-wont-show", "-a", "123", "--passed", "-bcd", "xyz", "--", "--subject=world"]

    parsed
    == [
        Short "a",
        Parameter "123",
        Long { name: "passed", value: Err NoValue },
        ShortGroup { names: ["b", "c", "d"], complete: Complete },
        Parameter "xyz",
        Parameter "--subject=world",
    ]
