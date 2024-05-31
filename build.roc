app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.11.0/SY4WWMhWQ9NvQgvIthcv15AUeA7rAIJHAHgiaSHGhdY.tar.br",
    weaver: "https://github.com/smores56/weaver/releases/download/0.2.0/BBDPvzgGrYp-AhIDw0qmwxT0pWZIQP_7KOrUrZfp_xw.tar.br",
}

import cli.Task exposing [Task]
import cli.Cmd
import cli.Stdout
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
            release: <- Opt.flag { short: "r", help: "Release build" },
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

    # generate glue for builtins
    printInfoLine! "generating glue for builtins"
    Cmd.exec "roc" ["glue", "glue.roc", "crates/", "platform/main.roc"]
    |> Task.mapErr! ErrGeneratingGlue

    target = getNativeTarget!

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

    prebuiltLegacyBinaryBuildPath =
        if release then
            "target/release/libhost.a"
        else
            "target/debug/libhost.a"

    prebuiltLegacyBinaryPath = "platform/$(prebuiltBinaryName target)"
    printInfoLine! "moving the prebuilt binary from $(prebuiltLegacyBinaryBuildPath) to $(prebuiltLegacyBinaryPath)"
    Cmd.exec "cp" [prebuiltLegacyBinaryBuildPath, prebuiltLegacyBinaryPath]
    |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

    # SURGICAL LINKER IS NOT YET SUPPORTED need to merge
    # https://github.com/roc-lang/roc/pull/6696

getNativeTarget : Task RocTarget _
getNativeTarget =

    printInfoLine! "geting native target using uname"

    archFromStr = \bytes ->
        when Str.fromUtf8 bytes is
            Ok str if str == "arm64\n" -> Arm64
            Ok str if str == "x86_64\n" -> X64
            Ok str -> UnsupportedArch str
            _ -> crash "invalid utf8 from uname -m"

    arch =
        Cmd.new "uname"
            |> Cmd.arg "-m"
            |> Cmd.output
            |> Task.map .stdout
            |> Task.map archFromStr
            |> Task.mapErr! ErrGettingNativeArch

    osFromStr = \bytes ->
        when Str.fromUtf8 bytes is
            Ok str if str == "Darwin\n" -> Macos
            Ok str if str == "Linux\n" -> Linux
            Ok str -> UnsupportedOS str
            _ -> crash "invalid utf8 from uname -s"

    os =
        Cmd.new "uname"
            |> Cmd.arg "-s"
            |> Cmd.output
            |> Task.map .stdout
            |> Task.map osFromStr
            |> Task.mapErr! ErrGettingNativeOS

    when (os, arch) is
        (Macos, Arm64) -> Task.ok MacosArm64
        (Macos, X64) -> Task.ok MacosX64
        (Linux, Arm64) -> Task.ok LinuxArm64
        (Linux, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

appStubExt : RocTarget -> Str
appStubExt = \target ->
    when target is
        MacosArm64 -> "dylib"
        MacosX64 -> "dylib"
        LinuxArm64 -> "so"
        LinuxX64 -> "so"
        WindowsArm64 -> "dll"
        WindowsX64 -> "dll"

prebuiltBinaryName : RocTarget -> Str
prebuiltBinaryName = \target ->
    when target is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.a"
        WindowsX64 -> "windows-x64"

printInfoLine : Str -> Task {} _
printInfoLine = \msg ->
    Stdout.line! "\u(001b)[34mROC BUILD INFO:\u(001b)[0m $(msg)"
