module [
    single,
    maybe,
    list,
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

import Arg.Builder exposing [
    CliBuilder,
    GetParamsAction,
    StopCollectingAction,
]
import Arg.Base exposing [
    ArgExtractErr,
    ParameterConfigBaseParams,
    ParameterConfigParams,
    ParameterConfig,
    strTypeName,
    numTypeName,
]
import Arg.Parser exposing [ArgValue]
import Arg.Extract exposing [extractParamValues]

builderWithParameterParser : ParameterConfig, (List Str -> Result data ArgExtractErr) -> CliBuilder data fromAction toAction
builderWithParameterParser = \param, valueParser ->
    argParser = \args ->
        { values, remainingArgs } = extractParamValues? { args, param }
        data = valueParser? values

        Ok { data, remainingArgs }

    Arg.Builder.fromArgParser argParser
    |> Arg.Builder.addParameter param

## Add a required parameter of a custom type to your CLI builder.
##
## You need to provide a kebab-case type name for your help messages as well as a
## parser for said type. The parser needs to return an `Err (InvalidValue Str)`
## on failure, where the `Str` is the reason the parsing failed that will
## get displayed in the incorrect usage message.
##
## Parsing arguments will fail if the parameter fails to parse or
## is not provided.
##
## Parameters must be provided last after any option or subcommand fields,
## as they are parsed last of the three extracted values, and parameter
## list fields cannot be followed by any other fields. This is enforced
## using the type state pattern, where we encode the state of the program
## into its types. If you're curious, check the internal `Builder`
## module to see how this works using the `action` type variable.
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
##         Param.single { name: "answer", type: "color", parser: parseColor },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "blue"]
##     == SuccessfullyParsed Blue
## ```
single : ParameterConfigParams state -> CliBuilder state {}action GetParamsAction
single = \{ parser, type, name, help ? "" } ->
    param = { name, type, help, plurality: One }

    valueParser = \values ->
        when List.first values is
            Err ListWasEmpty -> Err (MissingParam param)
            Ok singleValue ->
                parser singleValue
                |> Result.mapErr \err -> InvalidParamValue err param

    builderWithParameterParser param valueParser

## Add an optional parameter of a custom type to your CLI builder.
##
## You need to provide a kebab-case type name for your help messages as well as a
## parser for said type. The parser needs to return an `Err (InvalidValue Str)`
## on failure, where the `Str` is the reason the parsing failed that will
## get displayed in the incorrect usage message.
##
## Parsing arguments will fail if the parameter fails to parse.
##
## Parameters must be provided last after any option or subcommand fields,
## as they are parsed last of the three extracted values, and parameter
## list fields cannot be followed by any other fields. This is enforced
## using the type state pattern, where we encode the state of the program
## into its types. If you're curious, check the internal `Builder`
## module to see how this works using the `action` type variable.
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
##         Param.maybe { name: "answer", type: "color", parser: parseColor },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybe : ParameterConfigParams data -> CliBuilder (Result data [NoValue]) {}action GetParamsAction
maybe = \{ parser, type, name, help ? "" } ->
    param = { name, type, help, plurality: Optional }

    valueParser = \values ->
        when List.first values is
            Err ListWasEmpty -> Ok (Err NoValue)
            Ok singleValue ->
                parser singleValue
                |> Result.map Ok
                |> Result.mapErr \err -> InvalidParamValue err param

    builderWithParameterParser param valueParser

## Add a parameter of a custom type that can be provided
## multiple times to your CLI builder.
##
## You need to provide a kebab-case type name for your help messages as well as a
## parser for said type. The parser needs to return an `Err (InvalidValue Str)`
## on failure, where the `Str` is the reason the parsing failed that will
## get displayed in the incorrect usage message.
##
## Parsing arguments will fail if any of the values fail to parse.
##
## Parameters must be provided last after any option or subcommand fields,
## as they are parsed last of the three extracted values, and parameter
## list fields cannot be followed by any other fields. This is enforced
## using the type state pattern, where we encode the state of the program
## into its types. If you're curious, check the internal `Builder`
## module to see how this works using the `action` type variable.
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
##         Param.list { name: "answer", type: "color", parser: parseColor },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "blue", "red", "green"]
##     == SuccessfullyParsed [Blue, Red, Green]
## ```
list : ParameterConfigParams data -> CliBuilder (List data) {}action StopCollectingAction
list = \{ parser, type, name, help ? "" } ->
    param = { name, type, help, plurality: Many }

    valueParser = \values ->
        List.mapTry values parser
        |> Result.mapErr \err -> InvalidParamValue err param

    builderWithParameterParser param valueParser

## Add a required string parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided.
##
## ```roc
## expect
##     { parser } =
##         Param.str { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "abc"]
##     == SuccessfullyParsed "abc"
## ```
str : ParameterConfigBaseParams -> CliBuilder Str {}action GetParamsAction
str = \{ name, help ? "" } -> single { parser: Ok, type: strTypeName, name, help }

## Add an optional string parameter to your CLI builder.
##
## Parsing arguments cannot fail because of this parameter.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeStr { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeStr : ParameterConfigBaseParams -> CliBuilder ArgValue {}action GetParamsAction
maybeStr = \{ name, help ? "" } -> maybe { parser: Ok, type: strTypeName, name, help }

## Add a string parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments cannot fail because of this parameter.
##
## ```roc
## expect
##     { parser } =
##         Param.strList { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "abc", "def", "ghi"]
##     == SuccessfullyParsed ["abc", "def", "ghi"]
## ```
strList : ParameterConfigBaseParams -> CliBuilder (List Str) {}action StopCollectingAction
strList = \{ name, help ? "" } -> list { parser: Ok, type: strTypeName, name, help }

## Add a required `Dec` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.dec { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42.5"]
##     == SuccessfullyParsed 42.5
## ```
dec : ParameterConfigBaseParams -> CliBuilder Dec {}action GetParamsAction
dec = \{ name, help ? "" } -> single { parser: Str.toDec, type: numTypeName, name, help }

## Add an optional `Dec` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeDec { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeDec : ParameterConfigBaseParams -> CliBuilder (Result Dec [NoValue]) {}action GetParamsAction
maybeDec = \{ name, help ? "" } -> maybe { parser: Str.toDec, type: numTypeName, name, help }

## Add a `Dec` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.decList { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56.0"]
##     == SuccessfullyParsed [12.0, 34.0, -56.0]
## ```
decList : ParameterConfigBaseParams -> CliBuilder (List Dec) {}action StopCollectingAction
decList = \{ name, help ? "" } -> list { parser: Str.toDec, type: numTypeName, name, help }

## Add a required `F32` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.f32 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42.5"]
##     == SuccessfullyParsed 42.5
## ```
f32 : ParameterConfigBaseParams -> CliBuilder F32 {}action GetParamsAction
f32 = \{ name, help ? "" } -> single { parser: Str.toF32, type: numTypeName, name, help }

## Add an optional `F32` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeF32 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeF32 : ParameterConfigBaseParams -> CliBuilder (Result F32 [NoValue]) {}action GetParamsAction
maybeF32 = \{ name, help ? "" } -> maybe { parser: Str.toF32, type: numTypeName, name, help }

## Add a `F32` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.f32List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56.0"]
##     == SuccessfullyParsed [12.0, 34.0, -56.0]
## ```
f32List : ParameterConfigBaseParams -> CliBuilder (List F32) {}action StopCollectingAction
f32List = \{ name, help ? "" } -> list { parser: Str.toF32, type: numTypeName, name, help }

## Add a required `F64` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.f64 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42.5"]
##     == SuccessfullyParsed 42.5
## ```
f64 : ParameterConfigBaseParams -> CliBuilder F64 {}action GetParamsAction
f64 = \{ name, help ? "" } -> single { parser: Str.toF64, type: numTypeName, name, help }

## Add an optional `F64` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeF64 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeF64 : ParameterConfigBaseParams -> CliBuilder (Result F64 [NoValue]) {}action GetParamsAction
maybeF64 = \{ name, help ? "" } -> maybe { parser: Str.toF64, type: numTypeName, name, help }

## Add a `F64` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.f64List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56.0"]
##     == SuccessfullyParsed [12, 34, -56.0]
## ```
f64List : ParameterConfigBaseParams -> CliBuilder (List F64) {}action StopCollectingAction
f64List = \{ name, help ? "" } -> list { parser: Str.toF64, type: numTypeName, name, help }

## Add a required `U8` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.u8 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
u8 : ParameterConfigBaseParams -> CliBuilder U8 {}action GetParamsAction
u8 = \{ name, help ? "" } -> single { parser: Str.toU8, type: numTypeName, name, help }

## Add an optional `U8` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeU8 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU8 : ParameterConfigBaseParams -> CliBuilder (Result U8 [NoValue]) {}action GetParamsAction
maybeU8 = \{ name, help ? "" } -> maybe { parser: Str.toU8, type: numTypeName, name, help }

## Add a `U8` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.u8List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "56"]
##     == SuccessfullyParsed [12, 34, 56]
## ```
u8List : ParameterConfigBaseParams -> CliBuilder (List U8) {}action StopCollectingAction
u8List = \{ name, help ? "" } -> list { parser: Str.toU8, type: numTypeName, name, help }

## Add a required `U16` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.u16 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
u16 : ParameterConfigBaseParams -> CliBuilder U16 {}action GetParamsAction
u16 = \{ name, help ? "" } -> single { parser: Str.toU16, type: numTypeName, name, help }

## Add an optional `U16` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeU16 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU16 : ParameterConfigBaseParams -> CliBuilder (Result U16 [NoValue]) {}action GetParamsAction
maybeU16 = \{ name, help ? "" } -> maybe { parser: Str.toU16, type: numTypeName, name, help }

## Add a `U16` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.u16List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "56"]
##     == SuccessfullyParsed [12, 34, 56]
## ```
u16List : ParameterConfigBaseParams -> CliBuilder (List U16) {}action StopCollectingAction
u16List = \{ name, help ? "" } -> list { parser: Str.toU16, type: numTypeName, name, help }

## Add a required `U32` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.u32 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
u32 : ParameterConfigBaseParams -> CliBuilder U32 {}action GetParamsAction
u32 = \{ name, help ? "" } -> single { parser: Str.toU32, type: numTypeName, name, help }

## Add an optional `U32` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeU32 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU32 : ParameterConfigBaseParams -> CliBuilder (Result U32 [NoValue]) {}action GetParamsAction
maybeU32 = \{ name, help ? "" } -> maybe { parser: Str.toU32, type: numTypeName, name, help }

## Add a `U32` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.u32List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "56"]
##     == SuccessfullyParsed [12, 34, 56]
## ```
u32List : ParameterConfigBaseParams -> CliBuilder (List U32) {}action StopCollectingAction
u32List = \{ name, help ? "" } -> list { parser: Str.toU32, type: numTypeName, name, help }

## Add a required `U64` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.u64 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
u64 : ParameterConfigBaseParams -> CliBuilder U64 {}action GetParamsAction
u64 = \{ name, help ? "" } -> single { parser: Str.toU64, type: numTypeName, name, help }

## Add an optional `U64` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeU64 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU64 : ParameterConfigBaseParams -> CliBuilder (Result U64 [NoValue]) {}action GetParamsAction
maybeU64 = \{ name, help ? "" } -> maybe { parser: Str.toU64, type: numTypeName, name, help }

## Add a `U64` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.u64List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "56"]
##     == SuccessfullyParsed [12, 34, 56]
## ```
u64List : ParameterConfigBaseParams -> CliBuilder (List U64) {}action StopCollectingAction
u64List = \{ name, help ? "" } -> list { parser: Str.toU64, type: numTypeName, name, help }

## Add a required `U128` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.u128 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
u128 : ParameterConfigBaseParams -> CliBuilder U128 {}action GetParamsAction
u128 = \{ name, help ? "" } -> single { parser: Str.toU128, type: numTypeName, name, help }

## Add an optional `U128` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeU128 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeU128 : ParameterConfigBaseParams -> CliBuilder (Result U128 [NoValue]) {}action GetParamsAction
maybeU128 = \{ name, help ? "" } -> maybe { parser: Str.toU128, type: numTypeName, name, help }

## Add a `U128` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.u128List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "56"]
##     == SuccessfullyParsed [12, 34, 56]
## ```
u128List : ParameterConfigBaseParams -> CliBuilder (List U128) {}action StopCollectingAction
u128List = \{ name, help ? "" } -> list { parser: Str.toU128, type: numTypeName, name, help }

## Add a required `I8` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.i8 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
i8 : ParameterConfigBaseParams -> CliBuilder I8 {}action GetParamsAction
i8 = \{ name, help ? "" } -> single { parser: Str.toI8, type: numTypeName, name, help }

## Add an optional `I8` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeI8 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI8 : ParameterConfigBaseParams -> CliBuilder (Result I8 [NoValue]) {}action GetParamsAction
maybeI8 = \{ name, help ? "" } -> maybe { parser: Str.toI8, type: numTypeName, name, help }

## Add an `I8` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.i8List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56"]
##     == SuccessfullyParsed [12, 34, -56]
## ```
i8List : ParameterConfigBaseParams -> CliBuilder (List I8) {}action StopCollectingAction
i8List = \{ name, help ? "" } -> list { parser: Str.toI8, type: numTypeName, name, help }

## Add a required `I16` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.i16 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
i16 : ParameterConfigBaseParams -> CliBuilder I16 {}action GetParamsAction
i16 = \{ name, help ? "" } -> single { parser: Str.toI16, type: numTypeName, name, help }

## Add an optional `I16` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeI16 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI16 : ParameterConfigBaseParams -> CliBuilder (Result I16 [NoValue]) {}action GetParamsAction
maybeI16 = \{ name, help ? "" } -> maybe { parser: Str.toI16, type: numTypeName, name, help }

## Add an `I16` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.i16List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56"]
##     == SuccessfullyParsed [12, 34, -56]
## ```
i16List : ParameterConfigBaseParams -> CliBuilder (List I16) {}action StopCollectingAction
i16List = \{ name, help ? "" } -> list { parser: Str.toI16, type: numTypeName, name, help }

## Add a required `I32` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.i32 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
i32 : ParameterConfigBaseParams -> CliBuilder I32 {}action GetParamsAction
i32 = \{ name, help ? "" } -> single { parser: Str.toI32, type: numTypeName, name, help }

## Add an optional `I32` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeI32 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI32 : ParameterConfigBaseParams -> CliBuilder (Result I32 [NoValue]) {}action GetParamsAction
maybeI32 = \{ name, help ? "" } -> maybe { parser: Str.toI32, type: numTypeName, name, help }

## Add an `I32` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.i32List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56"]
##     == SuccessfullyParsed [12, 34, -56]
## ```
i32List : ParameterConfigBaseParams -> CliBuilder (List I32) {}action StopCollectingAction
i32List = \{ name, help ? "" } -> list { parser: Str.toI32, type: numTypeName, name, help }

## Add a required `I64` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.i64 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
i64 : ParameterConfigBaseParams -> CliBuilder I64 {}action GetParamsAction
i64 = \{ name, help ? "" } -> single { parser: Str.toI64, type: numTypeName, name, help }

## Add an optional `I64` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeI64 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI64 : ParameterConfigBaseParams -> CliBuilder (Result I64 [NoValue]) {}action GetParamsAction
maybeI64 = \{ name, help ? "" } -> maybe { parser: Str.toI64, type: numTypeName, name, help }

## Add an `I64` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.i64List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56"]
##     == SuccessfullyParsed [12, 34, -56]
## ```
i64List : ParameterConfigBaseParams -> CliBuilder (List I64) {}action StopCollectingAction
i64List = \{ name, help ? "" } -> list { parser: Str.toI64, type: numTypeName, name, help }

## Add a required `I128` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not provided
## or it is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.i128 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "42"]
##     == SuccessfullyParsed 42
## ```
i128 : ParameterConfigBaseParams -> CliBuilder I128 {}action GetParamsAction
i128 = \{ name, help ? "" } -> single { parser: Str.toI128, type: numTypeName, name, help }

## Add an optional `I128` parameter to your CLI builder.
##
## Parsing arguments will fail if the parameter is not a valid number.
##
## ```roc
## expect
##     { parser } =
##         Param.maybeI128 { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example"]
##     == SuccessfullyParsed (Err NoValue)
## ```
maybeI128 : ParameterConfigBaseParams -> CliBuilder (Result I128 [NoValue]) {}action GetParamsAction
maybeI128 = \{ name, help ? "" } -> maybe { parser: Str.toI128, type: numTypeName, name, help }

## Add an `I128` parameter that can be provided multiple times
## to your CLI builder.
##
## Parsing arguments will fail if any of the parameters are
## not valid numbers.
##
## ```roc
## expect
##     { parser } =
##         Param.i128List { name: "answer" },
##         |> Cli.finish { name: "example" }
##         |> Cli.assertValid
##
##     parser ["example", "12", "34", "--", "-56"]
##     == SuccessfullyParsed [12, 34, -56]
## ```
i128List : ParameterConfigBaseParams -> CliBuilder (List I128) {}action StopCollectingAction
i128List = \{ name, help ? "" } -> list { parser: Str.toI128, type: numTypeName, name, help }
