module [
    EnvFormat,
    format,
]

EnvFormat := {} implements [
        DecoderFormatting {
            u8: env_u8,
            u16: env_u16,
            u32: env_u32,
            u64: env_u64,
            u128: env_u128,
            i8: env_i8,
            i16: env_i16,
            i32: env_i32,
            i64: env_i64,
            i128: env_i128,
            f32: env_f32,
            f64: env_f64,
            dec: env_dec,
            bool: env_bool,
            string: env_string,
            list: env_list,
            record: env_record,
            tuple: env_tuple,
        },
    ]

format : {} -> EnvFormat
format = |{}| @EnvFormat({})

decode_bytes_to_num = |bytes, transformer|
    when Str.from_utf8(bytes) is
        Ok(s) ->
            when transformer(s) is
                Ok(n) -> { result: Ok(n), rest: [] }
                Err(_) -> { result: Err(TooShort), rest: bytes }

        Err(_) -> { result: Err(TooShort), rest: bytes }

env_u8 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_u8))
env_u16 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_u16))
env_u32 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_u32))
env_u64 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_u64))
env_u128 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_u128))
env_i8 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_i8))
env_i16 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_i16))
env_i32 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_i32))
env_i64 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_i64))
env_i128 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_i128))
env_f32 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_f32))
env_f64 = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_f64))
env_dec = Decode.custom(|bytes, @EnvFormat({})| decode_bytes_to_num(bytes, Str.to_dec))

env_bool = Decode.custom(
    |bytes, @EnvFormat({})|
        when Str.from_utf8(bytes) is
            Ok("true") -> { result: Ok(Bool.true), rest: [] }
            Ok("false") -> { result: Ok(Bool.false), rest: [] }
            _ -> { result: Err(TooShort), rest: bytes },
)

env_string = Decode.custom(
    |bytes, @EnvFormat({})|
        when Str.from_utf8(bytes) is
            Ok(s) -> { result: Ok(s), rest: [] }
            Err(_) -> { result: Err(TooShort), rest: bytes },
)

env_list = |decode_elem|
    Decode.custom(
        |bytes, @EnvFormat({})|
            # Per our supported methods of decoding, this is either a list of strings or
            # a list of numbers; in either case, the list of bytes must be Utf-8
            # decodable. So just parse it as a list of strings and pass each chunk to
            # the element decoder. By construction, our element decoders expect to parse
            # a whole list of bytes anyway.
            decode_elems = |all_bytes, accum|
                { to_parse, remainder } =
                    when List.split_first(all_bytes, Num.to_u8(',')) is
                        Ok({ before, after }) ->
                            { to_parse: before, remainder: Some(after) }

                        Err(NotFound) ->
                            { to_parse: all_bytes, remainder: None }

                when Decode.decode_with(to_parse, decode_elem, @EnvFormat({})) is
                    { result, rest } ->
                        when result is
                            Ok(val) ->
                                when remainder is
                                    Some(rest_bytes) -> decode_elems(rest_bytes, List.append(accum, val))
                                    None -> Done(List.append(accum, val))

                            Err(e) -> Errored(e, rest)

            when decode_elems(bytes, []) is
                Errored(e, rest) -> { result: Err(e), rest }
                Done(vals) ->
                    { result: Ok(vals), rest: [] },
    )

# TODO: we must currently annotate the arrows here so that the lambda sets are
# exercised, and the solver can find an ambient lambda set for the
# specialization.
env_record : _, (_, _ -> [Keep (Decoder _ _), Skip]), (_, _ -> _) -> Decoder _ _
env_record = |_initial_state, _step_field, _finalizer|
    Decode.custom(
        |bytes, @EnvFormat({})|
            { result: Err(TooShort), rest: bytes },
    )

# TODO: we must currently annotate the arrows here so that the lambda sets are
# exercised, and the solver can find an ambient lambda set for the
# specialization.
env_tuple : _, (_, _ -> [Next (Decoder _ _), TooLong]), (_ -> _) -> Decoder _ _
env_tuple = |_initial_state, _step_elem, _finalizer|
    Decode.custom(
        |bytes, @EnvFormat({})|
            { result: Err(TooShort), rest: bytes },
    )
