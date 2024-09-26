module [cwd, dict, var, decode, exePath, setCwd, platform, tempDir]

import Path exposing [Path]
import InternalPath
import EnvDecoding
import PlatformTasks
import path.Path as Path2

## Reads the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
## from the environment. File operations on relative [Path]s are relative to this directory.
cwd : Task Path [CwdUnavailable]
cwd =
    bytes =
        PlatformTasks.cwd
            |> Task.result!
            |> Result.withDefault []

    if List.isEmpty bytes then
        Task.err CwdUnavailable
    else
        Task.ok (InternalPath.fromArbitraryBytes bytes)

## Sets the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
## in the environment. After changing it, file operations on relative [Path]s will be relative
## to this directory.
setCwd : Path -> Task {} [InvalidCwd]
setCwd = \path ->
    PlatformTasks.setCwd (InternalPath.toBytes path)
    |> Task.mapErr \{} -> InvalidCwd

## Gets the path to the currently-running executable.
exePath : Task Path2.Path [ExePathUnavailable]
exePath =
    result = PlatformTasks.exePath |> Task.result!
    when result is
        Ok rawPath -> Task.ok (Path2.fromRaw rawPath)
        Err {} -> Task.err ExePathUnavailable

## Reads the given environment variable.
##
## If the value is invalid Unicode, the invalid parts will be replaced with the
## [Unicode replacement character](https://unicode.org/glossary/#replacement_character) ('�').
var : Str -> Task Str [VarNotFound]
var = \name ->
    PlatformTasks.envVar name
    |> Task.mapErr \{} -> VarNotFound

## Reads the given environment variable and attempts to decode it.
##
## The type being decoded into will be determined by type inference. For example,
## if this ends up being used like a `Task U16 _` then the environment variable
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
## getU16Var : Str -> Task U16 [VarNotFound, DecodeErr DecodeError] [Read [Env]]
## getU16Var = \var -> Env.decode var
## ```
##
## If `NUM_THINGS=123` then `getU16Var` succeeds with the value of `123u16`.
## However if `NUM_THINGS=123456789`, then `getU16Var` will
## fail with [DecodeErr](https://www.roc-lang.org/builtins/Decode#DecodeError)
## because `123456789` is too large to fit in a [U16](https://www.roc-lang.org/builtins/Num#U16).
##
decode : Str -> Task val [VarNotFound, DecodeErr DecodeError] where val implements Decoding
decode = \name ->
    result = PlatformTasks.envVar name |> Task.result!
    when result is
        Err {} -> Task.err VarNotFound
        Ok varStr ->
            Str.toUtf8 varStr
            |> Decode.fromBytes (EnvDecoding.format {})
            |> Result.mapErr (\_ -> DecodeErr TooShort)
            |> Task.fromResult

## Reads all the process's environment variables into a [Dict].
##
## If any key or value contains invalid Unicode, the [Unicode replacement character](https://unicode.org/glossary/#replacement_character)
## will be used in place of any parts of keys or values that are invalid Unicode.
dict : {} -> Task (Dict Str Str) *
dict = \{} ->
    PlatformTasks.envDict
    |> Task.map Dict.fromList
    |> Task.mapErr \_ -> crash "unreachable"

# ## Walks over the process's environment variables as key-value arguments to the walking function.
# ##
# ##     Env.walk "Vars:\n" \state, key, value ->
# ##         "- $(key): $(value)\n"
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
# walk : state, (state, Str, Str -> state) -> Task state [NonUnicodeEnv state] [Read [Env]]
# walk = \state, walker ->
#     Effect.envWalk state walker
#     |> InternalTask.fromEffect
# TODO could potentially offer something like walkNonUnicode which takes (state, Result Str Str, Result Str Str) so it
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
# decodeAll : Task val [] [EnvDecodingFailed Str] [Env] where val implements Decoding

ARCH : [X86, X64, ARM, AARCH64, OTHER Str]
OS : [LINUX, MACOS, WINDOWS, OTHER Str]

## Returns the current Achitecture and Operating System.
##
## `ARCH : [X86, X64, ARM, AARCH64, OTHER Str]`
## `OS : [LINUX, MACOS, WINDOWS, OTHER Str]`
##
## Note these values are constants from when the platform is built.
##
platform : Task { arch : ARCH, os : OS } *
platform =
    fromRust =
        PlatformTasks.currentArchOS
            |> Task.result!
            |> Result.withDefault { arch: "", os: "" }

    arch =
        when fromRust.arch is
            "x86" -> X86
            "x86_64" -> X64
            "arm" -> ARM
            "aarch64" -> AARCH64
            _ -> OTHER fromRust.arch

    os =
        when fromRust.os is
            "linux" -> LINUX
            "macos" -> MACOS
            "windows" -> WINDOWS
            _ -> OTHER fromRust.os

    Task.ok { arch, os }

## This uses rust's [`std::env::temp_dir()`](https://doc.rust-lang.org/std/env/fn.temp_dir.html)
##
## !! From the Rust documentation:
##
## The temporary directory may be shared among users, or between processes with different privileges;
## thus, the creation of any files or directories in the temporary directory must use a secure method
## to create a uniquely named file. Creating a file or directory with a fixed or predictable name may
## result in “insecure temporary file” security vulnerabilities.
##
tempDir : {} -> Task Path *
tempDir = \{} ->
    PlatformTasks.tempDir
    |> Task.map \pathOSStringBytes -> InternalPath.fromOsBytes pathOSStringBytes
    |> Task.mapErr \_ -> crash "unreachable"
