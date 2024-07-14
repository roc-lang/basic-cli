app [main] {
    cli: platform "platform/main.roc",
}

import cli.Task exposing [Task]
import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import cli.Arg.Opt
import cli.Arg.Cli

## Builds the basic-cli [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc --release
##
main : Task {} _
main =

    cliParser =
        { Arg.Cli.combine <-
            releaseMode: Arg.Opt.flag { short: "r", long: "release", help: "Release build. Passes `--release` to `cargo build`." },
            maybeRoc: Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path."},
        }
        |> Arg.Cli.finish {
            name: "basic-cli-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-cli platform.",
        }
        |> Arg.Cli.assertValid

    when Arg.Cli.parseOrDisplayMessage cliParser (Arg.list! {}) is
        Ok args -> run args
        Err errMsg -> Task.err (Exit 1 errMsg)

run : { releaseMode : Bool, maybeRoc : Result Str err} -> Task {} _
run = \{ releaseMode, maybeRoc } ->

    roc = maybeRoc |> Result.withDefault "roc"

    info! "Generating glue for builtins ..."
    roc
        |> Cmd.exec  ["glue", "glue.roc", "crates/", "platform/main.roc"]
        |> Task.mapErr! ErrGeneratingGlue

    # target is MacosArm64, LinuxX64,...
    info! "Getting the native target ..."
    target =
        Env.platform
        |> Task.await! getNativeTarget

    stubPath = "platform/libapp.$(stubFileExtension target)"

    info! "Building stubbed app shared library ..."
    roc
        |> Cmd.exec  ["build", "--lib", "platform/libapp.roc", "--output", stubPath]
        |> Task.mapErr! ErrBuildingAppStub

    (cargoBuildArgs, infoMessage) =
        if releaseMode then
            (["build", "--release"], "Building host in RELEASE mode ...")
        else
            (["build"], "Building host in DEBUG mode ...")

    info! infoMessage
    "cargo"
        |> Cmd.exec  cargoBuildArgs
        |> Task.mapErr! ErrBuildingHostBinaries

    hostBuildPath = if releaseMode then "target/release/libhost.a" else "target/debug/libhost.a"
    hostDestPath = "platform/$(prebuiltStaticLibFile target)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec  [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

    info! "Preprocessing surgical host ..."
    surgicalBuildPath = if releaseMode then "target/release/host" else "target/debug/host"
    roc
        |> Cmd.exec  ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubPath]
        |> Task.mapErr! ErrPreprocessingSurgicalBinary

    info! "Successfully completed building platform binaries."

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

getNativeTarget : _ -> Task RocTarget _
getNativeTarget =\{os, arch} ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

stubFileExtension : RocTarget -> Str
stubFileExtension = \target ->
    when target is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64-> "so"
        WindowsX64| WindowsArm64 -> "dll"

prebuiltStaticLibFile : RocTarget -> Str
prebuiltStaticLibFile = \target ->
    when target is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
