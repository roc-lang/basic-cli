## Options that your CLI will parse as fields in your config.
module [
    single,
    maybe,
    list,
    flag,
    count,
    str,
    maybeStr,
    strList,
    dec,
    maybeDec,
    decList,
    f32,
    maybeF32,
    f32List,
    f64,
    maybeF64,
    f64List,
    u8,
    maybeU8,
    u8List,
    u16,
    maybeU16,
    u16List,
    u32,
    maybeU32,
    u32List,
    u64,
    maybeU64,
    u64List,
    u128,
    maybeU128,
    u128List,
    i8,
    maybeI8,
    i8List,
    i16,
    maybeI16,
    i16List,
    i32,
    maybeI32,
    i32List,
    i64,
    maybeI64,
    i64List,
    i128,
    maybeI128,
    i128List,
]

import Arg.Builder exposing [CliBuilder, GetOptionsAction]
import Arg.Base exposing [
    ArgExtractErr,
    OptionConfigBaseParams,
    OptionConfigParams,
    OptionConfig,
    strTypeName,
    numTypeName,
]
import Arg.Extract exposing [extractOptionValues]
import Arg.Parser exposing [ArgValue]

builderWithOptionParser : OptionConfig, (List ArgValue -> Result data ArgExtractErr) -> CliBuilder data fromAction toAction
builderWithOptionParser = \option, valueParser ->
    argParser = \args ->
        { values, remainingArgs } <- extractOptionValues { args, option }
            |> Result.try
        data <- valueParser values
            |> Result.try

        Ok { data, remainingArgs }

    Arg.Builder.fromArgParser argParser
    |> Arg.Builder.addOption option

getSingleValue : List ArgValue, OptionConfig -> Result ArgValue ArgExtractErr
getSingleValue = \values, option ->
    when values is
        [] -> Err (MissingOption option)
        [singleValue] -> Ok singleValue
        [..] -> Err (OptionCanOnlyBeSetOnce option)

getMaybeValue : List ArgValue, OptionConfig -> Result (Result ArgValue [NoValue]) ArgExtractErr
getMaybeValue = \values, option ->
    when values is
        [] -> Ok (Err NoValue)
        [singleValue] -> Ok (Ok singleValue)
        [..] -> Err (OptionCanOnlyBeSetOnce option)

## Add a required option that takes a custom type to your CLI builder.
##
## You need to provide a kebab-case type name for your help messages as well as a
## parser for said type. The parser needs to return an `Err (InvalidValue Str)`
## on failure, where the `Str` is the reason the parsing failed that will
## get displayed in the incorrect usage message.
##
## Parsing arguments will fail if the option is not given as an argument
## or a value is not provided to the option.
##
## ```roc
## expect
##     Color : [Green, Red, Blue]
##
##     parseColor : Str -> Result Color [InvalidValue Str]
##     parseColor = \color ->
##         when color is
##             "green" -> Ok Green
##             "red" -> Ok Red
##             "blue" -> Ok Blue
##             other -> Err (InvalidValue "'$(other)' is not a valid color, must be green, red, or blue")
##
##     { parser } =
##         Opt.single { short: "c", parser: parseColor, type: "color" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-c", "green"]
##     == SuccessfullyParsed Green
## ```
single : OptionConfigParams a -> CliBuilder a GetOptionsAction GetOptionsAction
single = \{ parser, type, short ? "", long ? "", help ? "" } ->
    option = { expectedValue: ExpectsValue type, plurality: One, short, long, help }

    valueParser = \values ->
        argValue <- getSingleValue values option
            |> Result.try
        value <- argValue
            |> Result.mapErr \NoValue -> NoValueProvidedForOption option
            |> Result.try

        parser value
        |> Result.mapErr \err -> InvalidOptionValue err option

    builderWithOptionParser option valueParser

## Add an optional option that takes a custom type to your CLI builder.
##
## You need to provide a kebab-case type name for your help messages as well as a
## parser for said type. The parser needs to return an `Err (InvalidValue Str)`
## on failure, where the `Str` is the reason the parsing failed that will
## get displayed in the incorrect usage message.
##
## Parsing arguments will fail if more than one instance of the argument
## is provided, there is no value given for the option call, or the value
## doesn't parse correctly.
##
## ```roc
## expect
##     Color : [Green, Red, Blue]
##
##     parseColor : Str -> Result Color [InvalidValue Str]
##     parseColor = \color ->
##         when color is
##             "green" -> Ok Green
##             "red" -> Ok Red
##             "blue" -> Ok Blue
##             other -> Err (InvalidValue "'$(other)' is not a valid color, must be green, red, or blue")
##
##     { parser } =
##         Opt.maybe { short: "c", type: "color", parser: parseColor },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybe : OptionConfigParams data -> CliBuilder (Result data [NoValue]) GetOptionsAction GetOptionsAction
maybe = \{ parser, type, short ? "", long ? "", help ? "" } ->
    option = { expectedValue: ExpectsValue type, plurality: Optional, short, long, help }

    valueParser = \values ->
        value <- getMaybeValue values option
            |> Result.try

        when value is
            Err NoValue -> Ok (Err NoValue)
            Ok (Err NoValue) -> Err (NoValueProvidedForOption option)
            Ok (Ok val) ->
                parser val
                |> Result.map Ok
                |> Result.mapErr \err -> InvalidOptionValue err option

    builderWithOptionParser option valueParser

## Add an option that takes a custom type and can be given multiple times
## to your CLI builder.
##
## You need to provide a kebab-case type name for your help messages as well as a
## parser for said type. The parser needs to return an `Err (InvalidValue Str)`
## on failure, where the `Str` is the reason the parsing failed that will
## get displayed in the incorrect usage message.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value or any of the options don't parse correctly.
##
## ```roc
## expect
##     Color : [Green, Red, Blue]
##
##     parseColor : Str -> Result Color [InvalidValue Str]
##     parseColor = \color ->
##         when color is
##             "green" -> Ok Green
##             "red" -> Ok Red
##             "blue" -> Ok Blue
##             other -> Err (InvalidValue "'$(other)' is not a valid color, must be green, red, or blue")
##
##     { parser } =
##         Opt.list { short: "c", type: "color", parser: parseColor },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-c", "green", "--color=red"]
##     == SuccessfullyParsed [Green, Red]
## ```
list : OptionConfigParams data -> CliBuilder (List data) GetOptionsAction GetOptionsAction
list = \{ parser, type, short ? "", long ? "", help ? "" } ->
    option = { expectedValue: ExpectsValue type, plurality: Many, short, long, help }

    valueParser = \values ->
        List.mapTry values \value ->
            when value is
                Err NoValue -> Err (NoValueProvidedForOption option)
                Ok val ->
                    parser val
                    |> Result.mapErr \err -> InvalidOptionValue err option

    builderWithOptionParser option valueParser

## Add an optional flag to your CLI builder.
##
## Parsing arguments will fail if the flag is given more than once
## or if a value is provided to it, e.g. `--flag=value`.
##
## ```roc
## expect
##     { parser } =
##         Opt.flag { short: "f", long: "force" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-f"]
##     == SuccessfullyParsed Bool.true
## ```
flag : OptionConfigBaseParams -> CliBuilder Bool GetOptionsAction GetOptionsAction
flag = \{ short ? "", long ? "", help ? "" } ->
    option = { expectedValue: NothingExpected, plurality: Optional, short, long, help }

    valueParser = \values ->
        value <- getMaybeValue values option
            |> Result.try

        when value is
            Err NoValue -> Ok Bool.false
            Ok (Err NoValue) -> Ok Bool.true
            Ok (Ok _val) -> Err (OptionDoesNotExpectValue option)

    builderWithOptionParser option valueParser

## Add a flag that can be given multiple times to your CLI builder.
##
## Parsing arguments will fail if this flag is ever given a value,
## e.g. `--flag=value`.
##
## ```roc
## expect
##     { parser } =
##         Opt.count { short: "f", long: "force" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-f", "--force", "-fff"]
##     == SuccessfullyParsed 5
## ```
count : OptionConfigBaseParams -> CliBuilder U64 GetOptionsAction GetOptionsAction
count = \{ short ? "", long ? "", help ? "" } ->
    option = { expectedValue: NothingExpected, plurality: Many, short, long, help }

    valueParser = \values ->
        if values |> List.any Result.isOk then
            Err (OptionDoesNotExpectValue option)
        else
            Ok (List.len values)

    builderWithOptionParser option valueParser

## Add a required option that takes a string to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument
## or a value is not provided to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.str { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=abc"]
##     == SuccessfullyParsed "abc"
## ```
str : OptionConfigBaseParams -> CliBuilder Str GetOptionsAction GetOptionsAction
str = \{ short ? "", long ? "", help ? "" } -> single { parser: Ok, type: strTypeName, short, long, help }

## Add an optional option that takes a string to your CLI builder.
##
## Parsing arguments will fail if more than one instance of the argument
## is provided or there is no value given for the option call.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeStr { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeStr : OptionConfigBaseParams -> CliBuilder (Result Str [NoValue]) GetOptionsAction GetOptionsAction
maybeStr = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Ok, type: strTypeName, short, long, help }

## Add an option that takes a string and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value.
##
## ```roc
## expect
##     { parser } =
##         Opt.strList { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "abc", "--answer", "def", "--answer=ghi"]
##     == SuccessfullyParsed ["abc", "def", "ghi"]
## ```
strList : OptionConfigBaseParams -> CliBuilder (List Str) GetOptionsAction GetOptionsAction
strList = \{ short ? "", long ? "", help ? "" } -> list { parser: Ok, type: strTypeName, short, long, help }

## Add a required option that takes a `Dec` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.dec { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42.5"]
##     == SuccessfullyParsed 42.5
## ```
dec : OptionConfigBaseParams -> CliBuilder Dec GetOptionsAction GetOptionsAction
dec = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toDec, type: numTypeName, short, long, help }

## Add an optional option that takes a `Dec` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeDec { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeDec : OptionConfigBaseParams -> CliBuilder (Result Dec [NoValue]) GetOptionsAction GetOptionsAction
maybeDec = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toDec, type: numTypeName, short, long, help }

## Add an option that takes a `Dec` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.decList { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "-3.0"]
##     == SuccessfullyParsed [1.0, 2.0, -3.0]
## ```
decList : OptionConfigBaseParams -> CliBuilder (List Dec) GetOptionsAction GetOptionsAction
decList = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toDec, type: numTypeName, short, long, help }

## Add a required option that takes a `F32` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.f32 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42.5"]
##     == SuccessfullyParsed 42.5
## ```
f32 : OptionConfigBaseParams -> CliBuilder F32 GetOptionsAction GetOptionsAction
f32 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toF32, type: numTypeName, short, long, help }

## Add an optional option that takes a `F32` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeF32 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeF32 : OptionConfigBaseParams -> CliBuilder (Result F32 [NoValue]) GetOptionsAction GetOptionsAction
maybeF32 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toF32, type: numTypeName, short, long, help }

## Add an option that takes a `F32` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.f32List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "-3.0"]
##     == SuccessfullyParsed [1.0, 2.0, -3.0]
## ```
f32List : OptionConfigBaseParams -> CliBuilder (List F32) GetOptionsAction GetOptionsAction
f32List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toF32, type: numTypeName, short, long, help }

## Add a required option that takes a `F64` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.f64 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42.5"]
##     == SuccessfullyParsed 42.5
## ```
f64 : OptionConfigBaseParams -> CliBuilder F64 GetOptionsAction GetOptionsAction
f64 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toF64, type: numTypeName, short, long, help }

## Add an optional option that takes a `F64` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeF64 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeF64 : OptionConfigBaseParams -> CliBuilder (Result F64 [NoValue]) GetOptionsAction GetOptionsAction
maybeF64 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toF64, type: numTypeName, short, long, help }

## Add an option that takes a `F64` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.f64List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "-3.0"]
##     == SuccessfullyParsed [1.0, 2.0, -3.0]
## ```
f64List : OptionConfigBaseParams -> CliBuilder (List F64) GetOptionsAction GetOptionsAction
f64List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toF64, type: numTypeName, short, long, help }

## Add a required option that takes a `U8` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.u8 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
u8 : OptionConfigBaseParams -> CliBuilder U8 GetOptionsAction GetOptionsAction
u8 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toU8, type: numTypeName, short, long, help }

## Add an optional option that takes a `U8` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeU8 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU8 : OptionConfigBaseParams -> CliBuilder (Result U8 [NoValue]) GetOptionsAction GetOptionsAction
maybeU8 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toU8, type: numTypeName, short, long, help }

## Add an option that takes a `U8` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.u8List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
u8List : OptionConfigBaseParams -> CliBuilder (List U8) GetOptionsAction GetOptionsAction
u8List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toU8, type: numTypeName, short, long, help }

## Add a required option that takes a `U16` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.u16 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
u16 : OptionConfigBaseParams -> CliBuilder U16 GetOptionsAction GetOptionsAction
u16 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toU16, type: numTypeName, short, long, help }

## Add an optional option that takes a `U16` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeU16 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU16 : OptionConfigBaseParams -> CliBuilder (Result U16 [NoValue]) GetOptionsAction GetOptionsAction
maybeU16 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toU16, type: numTypeName, short, long, help }

## Add an option that takes a `U16` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.u16List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
u16List : OptionConfigBaseParams -> CliBuilder (List U16) GetOptionsAction GetOptionsAction
u16List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toU16, type: numTypeName, short, long, help }

## Add a required option that takes a `U32` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.u32 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
u32 : OptionConfigBaseParams -> CliBuilder U32 GetOptionsAction GetOptionsAction
u32 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toU32, type: numTypeName, short, long, help }

## Add an optional option that takes a `U32` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeU32 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU32 : OptionConfigBaseParams -> CliBuilder (Result U32 [NoValue]) GetOptionsAction GetOptionsAction
maybeU32 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toU32, type: numTypeName, short, long, help }

## Add an option that takes a `U32` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.u32List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
u32List : OptionConfigBaseParams -> CliBuilder (List U32) GetOptionsAction GetOptionsAction
u32List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toU32, type: numTypeName, short, long, help }

## Add a required option that takes a `U64` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.u64 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
u64 : OptionConfigBaseParams -> CliBuilder U64 GetOptionsAction GetOptionsAction
u64 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toU64, type: numTypeName, short, long, help }

## Add an optional option that takes a `U64` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeU64 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU64 : OptionConfigBaseParams -> CliBuilder (Result U64 [NoValue]) GetOptionsAction GetOptionsAction
maybeU64 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toU64, type: numTypeName, short, long, help }

## Add an option that takes a `U64` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.u64List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
u64List : OptionConfigBaseParams -> CliBuilder (List U64) GetOptionsAction GetOptionsAction
u64List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toU64, type: numTypeName, short, long, help }

## Add a required option that takes a `U128` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.u128 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
u128 : OptionConfigBaseParams -> CliBuilder U128 GetOptionsAction GetOptionsAction
u128 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toU128, type: numTypeName, short, long, help }

## Add an optional option that takes a `U128` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeU128 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU128 : OptionConfigBaseParams -> CliBuilder (Result U128 [NoValue]) GetOptionsAction GetOptionsAction
maybeU128 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toU128, type: numTypeName, short, long, help }

## Add an option that takes a `U128` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.u128List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
u128List : OptionConfigBaseParams -> CliBuilder (List U128) GetOptionsAction GetOptionsAction
u128List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toU128, type: numTypeName, short, long, help }

## Add a required option that takes an `I8` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.i8 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
i8 : OptionConfigBaseParams -> CliBuilder I8 GetOptionsAction GetOptionsAction
i8 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toI8, type: numTypeName, short, long, help }

## Add an optional option that takes an `I8` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeI8 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI8 : OptionConfigBaseParams -> CliBuilder (Result I8 [NoValue]) GetOptionsAction GetOptionsAction
maybeI8 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toI8, type: numTypeName, short, long, help }

## Add an option that takes an `I8` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.i8List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
i8List : OptionConfigBaseParams -> CliBuilder (List I8) GetOptionsAction GetOptionsAction
i8List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toI8, type: numTypeName, short, long, help }

## Add a required option that takes an `I16` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.i16 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
i16 : OptionConfigBaseParams -> CliBuilder I16 GetOptionsAction GetOptionsAction
i16 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toI16, type: numTypeName, short, long, help }

## Add an optional option that takes an `I16` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeI16 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI16 : OptionConfigBaseParams -> CliBuilder (Result I16 [NoValue]) GetOptionsAction GetOptionsAction
maybeI16 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toI16, type: numTypeName, short, long, help }

## Add an option that takes an `I16` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.i16List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
i16List : OptionConfigBaseParams -> CliBuilder (List I16) GetOptionsAction GetOptionsAction
i16List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toI16, type: numTypeName, short, long, help }

## Add a required option that takes an `I32` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.i32 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
i32 : OptionConfigBaseParams -> CliBuilder I32 GetOptionsAction GetOptionsAction
i32 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toI32, type: numTypeName, short, long, help }

## Add an optional option that takes an `I32` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeI32 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI32 : OptionConfigBaseParams -> CliBuilder (Result I32 [NoValue]) GetOptionsAction GetOptionsAction
maybeI32 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toI32, type: numTypeName, short, long, help }

## Add an option that takes an `I32` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.i32List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
i32List : OptionConfigBaseParams -> CliBuilder (List I32) GetOptionsAction GetOptionsAction
i32List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toI32, type: numTypeName, short, long, help }

## Add a required option that takes an `I64` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.i64 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
i64 : OptionConfigBaseParams -> CliBuilder I64 GetOptionsAction GetOptionsAction
i64 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toI64, type: numTypeName, short, long, help }

## Add an optional option that takes an `I64` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeI64 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI64 : OptionConfigBaseParams -> CliBuilder (Result I64 [NoValue]) GetOptionsAction GetOptionsAction
maybeI64 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toI64, type: numTypeName, short, long, help }

## Add an option that takes an `I64` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.i64List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
i64List : OptionConfigBaseParams -> CliBuilder (List I64) GetOptionsAction GetOptionsAction
i64List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toI64, type: numTypeName, short, long, help }

## Add a required option that takes an `I128` to your CLI builder.
##
## Parsing arguments will fail if the option is not given as an argument,
## a value is not provided to the option, or the value is not a number.
##
## ```roc
## expect
##     { parser } =
##         Opt.i128 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "--answer=42"]
##     == SuccessfullyParsed 42
## ```
i128 : OptionConfigBaseParams -> CliBuilder I128 GetOptionsAction GetOptionsAction
i128 = \{ short ? "", long ? "", help ? "" } -> single { parser: Str.toI128, type: numTypeName, short, long, help }

## Add an optional option that takes an `I128` to your CLI builder.
##
## Parsing arguments will fail if a value is not provided to the option,
## the value is not a number, or there is more than one call to the option.
##
## ```roc
## expect
##     { parser } =
##         Opt.maybeI128 { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI128 : OptionConfigBaseParams -> CliBuilder (Result I128 [NoValue]) GetOptionsAction GetOptionsAction
maybeI128 = \{ short ? "", long ? "", help ? "" } -> maybe { parser: Str.toI128, type: numTypeName, short, long, help }

## Add an option that takes an `I128` and can be given multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any calls of the option don't provide
## a value, or the values are not all numbers.
##
## ```roc
## expect
##     { parser } =
##         Opt.i128List { long: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "-a", "1", "--answer=2", "--answer", "3"]
##     == SuccessfullyParsed [1, 2, 3]
## ```
i128List : OptionConfigBaseParams -> CliBuilder (List I128) GetOptionsAction GetOptionsAction
i128List = \{ short ? "", long ? "", help ? "" } -> list { parser: Str.toI128, type: numTypeName, short, long, help }
