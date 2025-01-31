module [
    cwd!,
    dict!,
    var!,
    decode!,
    exe_path!,
    set_cwd!,
    platform!,
    temp_dir!,
]

import Path exposing [Path]
import InternalPath
import EnvDecoding
import Host

## Reads the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
## from the environment. File operations on relative [Path]s are relative to this directory.
cwd! : {} => Result Path [CwdUnavailable]
cwd! = |{}|
    bytes = Host.cwd!({}) |> Result.with_default([])

    if List.is_empty(bytes) then
        Err(CwdUnavailable)
    else
        Ok(InternalPath.from_arbitrary_bytes(bytes))

## Sets the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
## in the environment. After changing it, file operations on relative [Path]s will be relative
## to this directory.
set_cwd! : Path => Result {} [InvalidCwd]
set_cwd! = |path|
    Host.set_cwd!(InternalPath.to_bytes(path))
    |> Result.map_err(|{}| InvalidCwd)

## Gets the path to the currently-running executable.
exe_path! : {} => Result Path [ExePathUnavailable]
exe_path! = |{}|
    when Host.exe_path!({}) is
        Ok(bytes) -> Ok(InternalPath.from_os_bytes(bytes))
        Err({}) -> Err(ExePathUnavailable)

## Reads the given environment variable.
##
## If the value is invalid Unicode, the invalid parts will be replaced with the
## [Unicode replacement character](https://unicode.org/glossary/#replacement_character) ('�').
var! : Str => Result Str [VarNotFound]
var! = |name|
    Host.env_var!(name)
    |> Result.map_err(|{}| VarNotFound)

## Reads the given environment variable and attempts to decode it.
##
## The type being decoded into will be determined by type inference. For example,
## if this ends up being used like a `Result U16 _` then the environment variable
## will be decoded as a string representation of a `U16`. Trying to decode into
## any other type will fail with a `DecodeErr`.
##
## Supported types include;
## - Strings,
## - Numbers, as long as they contain only numeric digits, up to one `.`, and an optional `-` at the front for negative numbers, and
## - Comma-separated lists (of either strings or numbers), as long as there are no spaces after the commas.
##
## For example, consider we want to decode the environment variable `NUM_THINGS`;
##
## ```
## # Reads "NUM_THINGS" and decodes into a U16
## get_u16_var! : Str => Result U16 [VarNotFound, DecodeErr DecodeError] [Read [Env]]
## get_u16_var! = |var|
##     Env.decode!(var)
## ```
##
## If `NUM_THINGS=123` then `get_u16_var` succeeds with the value of `123u16`.
## However if `NUM_THINGS=123456789`, then `get_u16_var` will
## fail with [DecodeErr](https://www.roc-lang.org/builtins/Decode#DecodeError)
## because `123456789` is too large to fit in a [U16](https://www.roc-lang.org/builtins/Num#U16).
##
decode! : Str => Result val [VarNotFound, DecodeErr DecodeError] where val implements Decoding
decode! = |name|
    when Host.env_var!(name) is
        Err({}) -> Err(VarNotFound)
        Ok(var_str) ->
            Str.to_utf8(var_str)
            |> Decode.from_bytes(EnvDecoding.format({}))
            |> Result.map_err(|_| DecodeErr(TooShort))

## Reads all the process's environment variables into a [Dict].
##
## If any key or value contains invalid Unicode, the [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
## will be used in place of any parts of keys or values that are invalid Unicode.
dict! : {} => Dict Str Str
dict! = |{}|
    Host.env_dict!({})
    |> Dict.from_list

# ## Walks over the process's environment variables as key-value arguments to the walking function.
# ##
# ##     Env.walk "Vars:\n" \state, key, value ->
# ##         "- ${key}: ${value}\n"
# ##     # This might produce a string such as:
# ##     #
# ##     #     """
# ##     #     Vars:
# ##     #     - FIRST_VAR: first value
# ##     #     - SECOND_VAR: second value
# ##     #     - THIRD_VAR: third value
# ##     #
# ##     #     """
# ##
# ## If any key or value contains invalid Unicode, the [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
# ## (`�`) will be used in place of any parts of keys or values that are invalid Unicode.
# walk! : state, (state, Str, Str -> state) => Result state [NonUnicodeEnv state] [Read [Env]]
# walk! = |state, walker|
#     Host.env_walk! state walker
# TODO could potentially offer something like walk_non_unicode which takes (state, Result Str Str, Result Str Str) so it
# tells you when there's invalid Unicode. This is both faster than (and would give you more accurate info than)
# using regular `walk` and searching for the presence of the replacement character in the resulting
# strings. However, it's unclear whether anyone would use it. What would the use case be? Reporting
# an error that the provided command-line args weren't valid Unicode? Does that still happen these days?
# TODO need to figure out clear rules for how to convert from camelCase to SCREAMING_SNAKE_CASE.
# Note that all the env vars decoded in this way become effectively *required* vars, since if any
# of them are missing, decoding will fail. For this reason, it might make sense to use this to
# decode all the required vars only, and then decode the optional ones separately some other way.
# Alternatively, it could make sense to have some sort of tag union convention here, e.g.
# if decoding into a tag union of [Present val, Missing], then it knows what to do.
# decode_all : Result val [] [EnvDecodingFailed Str] [Env] where val implements Decoding

ARCH : [X86, X64, ARM, AARCH64, OTHER Str]
OS : [LINUX, MACOS, WINDOWS, OTHER Str]

## Returns the current Achitecture and Operating System.
##
## `ARCH : [X86, X64, ARM, AARCH64, OTHER Str]`
## `OS : [LINUX, MACOS, WINDOWS, OTHER Str]`
##
## Note these values are constants from when the platform is built.
##
platform! : {} => { arch : ARCH, os : OS }
platform! = |{}|

    from_rust = Host.current_arch_os!({})

    arch =
        when from_rust.arch is
            "x86" -> X86
            "x86_64" -> X64
            "arm" -> ARM
            "aarch64" -> AARCH64
            _ -> OTHER(from_rust.arch)

    os =
        when from_rust.os is
            "linux" -> LINUX
            "macos" -> MACOS
            "windows" -> WINDOWS
            _ -> OTHER(from_rust.os)

    { arch, os }

## This uses rust's [`std::env::temp_dir()`](https://doc.rust-lang.org/std/env/fn.temp_dir.html)
##
## !! From the Rust documentation:
##
## The temporary directory may be shared among users, or between processes with different privileges;
## thus, the creation of any files or directories in the temporary directory must use a secure method
## to create a uniquely named file. Creating a file or directory with a fixed or predictable name may
## result in “insecure temporary file” security vulnerabilities.
##
temp_dir! : {} => Path
temp_dir! = |{}|
    Host.temp_dir!({})
    |> InternalPath.from_os_bytes
