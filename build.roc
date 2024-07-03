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

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

main =

    cliParser =
        Cli.weave {
            release: <- Opt.flag { short: "r", long: "release", help: "Release build" },
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

run = \{ release } ->

    printInfoLine! "generating glue for builtins"
    Cmd.exec "roc" ["glue", "glue.roc", "crates/", "platform/main.roc"]
    |> Task.mapErr! ErrGeneratingGlue

    printInfoLine! "getting the native target"
    target = Env.platform |> Task.await! getNativeTarget

    printInfoLine! "building the app stub shared library for surgical linker"
    appStubBuildPath = "platform/libapp.$(appStubExt target)"
    printInfoLine! "roc build the app stub shared library at $(appStubBuildPath)"
    Cmd.exec "roc" ["build", "--lib", "platform/libapp.roc"]
    |> Task.mapErr! ErrBuildingAppStub

    (cargoBuildArgs, message) =
        if release then
            (["build", "--release"], "building roc host binaries in release mode")
        else
            (["build"], "building roc host binaries in debug mode")

    printInfoLine! message
    Cmd.exec "cargo" cargoBuildArgs
    |> Task.mapErr! ErrBuildingRocHostBinaries

    # move the prebuilt binary to the platform directory
    prebuiltLegacyBinaryBuildPath =
        if release then
            "target/release/libhost.a"
        else
            "target/debug/libhost.a"

    prebuiltLegacyBinaryPath = "platform/$(prebuiltBinaryName target)"
    printInfoLine! "moving the prebuilt binary from $(prebuiltLegacyBinaryBuildPath) to $(prebuiltLegacyBinaryPath)"
    Cmd.exec "cp" [prebuiltLegacyBinaryBuildPath, prebuiltLegacyBinaryPath]
    |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

    #SURGICAL LINKER IS NOT YET SUPPORTED need to merge https://github.com/roc-lang/roc/pull/6808
    #prebuiltSurgicalBinaryBuildPath =
    #    if release then
    #        "target/release/host"
    #    else
    #        "target/debug/host"
    #Cmd.exec "roc" ["preprocess-host", prebuiltSurgicalBinaryBuildPath, "platform/main.roc", "platform/libapp.$(appStubExt target)"]
    #|> Task.mapErr! ErrPreprocessingSurgicalBinary

getNativeTarget : _ -> Task RocTarget _
getNativeTarget =\{os, arch} ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

appStubExt : RocTarget -> Str
appStubExt = \target ->
    when target is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64-> "so"
        WindowsX64| WindowsArm64 -> "dll"

prebuiltBinaryName : RocTarget -> Str
prebuiltBinaryName = \target ->
    when target is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

printInfoLine : Str -> Task {} _
printInfoLine = \msg ->
    Stdout.line! "\u(001b)[34mROC BUILD INFO:\u(001b)[0m $(msg)"
