app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.12.0/cf_TpThUd4e69C7WzHxCbgsagnDmk3xlb_HmEKXTICw.tar.br",
    weaver: "https://github.com/smores56/weaver/releases/download/0.2.0/BBDPvzgGrYp-AhIDw0qmwxT0pWZIQP_7KOrUrZfp_xw.tar.br",
}

import cli.Task exposing [Task]
import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import weaver.Opt
import weaver.Cli

main =

    cliParser =
        Cli.weave {
            release: <- Opt.flag { short: "r", long: "release", help: "Release build" },
            maybeRoc: <- Opt.maybeStr { short: "c", long: "cli", help: "Path to the roc cli"},
        }
        |> Cli.finish {
            name: "basic-webserver",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "This build script generates the binaries and packages the platform for distribution.",
        }
        |> Cli.assertValid

    when Cli.parseOrDisplayMessage cliParser (Arg.list!) is
        Ok args -> run args
        Err message -> Task.err (Exit 1 message)

run = \{ release, maybeRoc } ->

    roc = maybeRoc |> Result.withDefault "roc"

    info! "Generating glue for builtins ..."
    roc
        |> Cmd.exec  ["glue", "glue.roc", "crates/", "platform/main.roc"]
        |> Task.mapErr! ErrGeneratingGlue

    info! "Getting the native target ..."
    target =
        Env.platform
        |> Task.await! getNativeTarget

    stubPath = "platform/libapp.$(stubExt target)"

    info! "Building stubbed app shared library ..."
    roc
        |> Cmd.exec  ["build", "--lib", "platform/libapp.roc", "--output", stubPath]
        |> Task.mapErr! ErrBuildingAppStub

    (cargoBuildArgs, message) =
        if release then
            (["build", "--release"], "Building host in RELEASE mode ...")
        else
            (["build"], "Building host in DEBUG mode ...")

    info! message
    "cargo"
        |> Cmd.exec  cargoBuildArgs
        |> Task.mapErr! ErrBuildingHostBinaries

    hostBuildPath = if release then "target/release/libhost.a" else "target/debug/libhost.a"
    hostDestPath = "platform/$(prebuiltStaticLibrary target)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec  [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

    info! "Preprocessing surgical host ..."
    surgicalBuildPath = if release then "target/release/host" else "target/debug/host"
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

stubExt : RocTarget -> Str
stubExt = \target ->
    when target is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64-> "so"
        WindowsX64| WindowsArm64 -> "dll"

prebuiltStaticLibrary : RocTarget -> Str
prebuiltStaticLibrary = \target ->
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
