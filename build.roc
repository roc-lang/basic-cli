app [main] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.16.0/O00IPk-Krg_diNS2dVWlI0ZQP794Vctxzv0ha96mK0E.tar.br",
}

import cli.Cmd
import cli.Stdout
import cli.Env

## Builds the basic-cli [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc
##
## Check basic-cli-build-steps.png for a diagram that shows what the code does.
##
main : Task {} _
main =

    rocCmd =
        Env.var "ROC"
        |> Task.result!
        |> Result.withDefault "roc"

    debugMode =
        Env.var "DEBUG"
        |> Task.result!
        |> \result ->
            when result is
                Ok str if !(Str.isEmpty str) -> Bool.true
                _ -> Bool.false

    run { debugMode, rocCmd }

run : { debugMode : Bool, rocCmd : Str } -> Task {} _
run = \{ debugMode, rocCmd } ->

    rocVersion! rocCmd

    osAndArch = getOSAndArch!

    stubLibPath = "platform/libapp.$(stubFileExtension osAndArch)"

    buildStubAppLib! rocCmd stubLibPath

    cargoBuildHost! debugMode

    rustTargetFolder = getRustTargetFolder! debugMode

    copyHostLib! osAndArch rustTargetFolder

    preprocessHost! rocCmd stubLibPath rustTargetFolder

    info! "Successfully built platform files!"

rocVersion : Str -> Task {} _
rocVersion = \rocCmd ->
    info! "Checking provided roc; executing `$(rocCmd) version`:"

    rocCmd
        |> Cmd.exec ["version"]
        |> Task.mapErr! RocVersionCheckFailed

getOSAndArch : Task OSAndArch _
getOSAndArch =
    info! "Getting the native operating system and architecture ..."

    Env.platform
    |> Task.await convertOSAndArch

OSAndArch : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convertOSAndArch : _ -> Task OSAndArch _
convertOSAndArch = \{ os, arch } ->
    when (os, arch) is
        (MACOS, AARCH64) -> Task.ok MacosArm64
        (MACOS, X64) -> Task.ok MacosX64
        (LINUX, AARCH64) -> Task.ok LinuxArm64
        (LINUX, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

buildStubAppLib : Str, Str -> Task {} _
buildStubAppLib = \rocCmd, stubLibPath ->
    info! "Building stubbed app shared library ..."
    rocCmd
        |> Cmd.exec ["build", "--lib", "platform/libapp.roc", "--output", stubLibPath, "--optimize"]
        |> Task.mapErr! ErrBuildingAppStub

stubFileExtension : OSAndArch -> Str
stubFileExtension = \osAndArch ->
    when osAndArch is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64 -> "so"
        WindowsX64 | WindowsArm64 -> "dll"

prebuiltStaticLibFile : OSAndArch -> Str
prebuiltStaticLibFile = \osAndArch ->
    when osAndArch is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

getRustTargetFolder : Bool -> Task Str _
getRustTargetFolder = \debugMode ->
    debugOrRelease =
        if debugMode then
            "debug"
        else
            "release"

    when Env.var "CARGO_BUILD_TARGET" |> Task.result! is
        Ok targetEnvVar ->
            if Str.isEmpty targetEnvVar then
                Task.ok "target/$(debugOrRelease)/"
            else
                Task.ok "target/$(targetEnvVar)/$(debugOrRelease)/"

        Err e ->
            info! "Failed to get env var CARGO_BUILD_TARGET with error $(Inspect.toStr e). Assuming default CARGO_BUILD_TARGET (native)..."

            Task.ok "target/$(debugOrRelease)/"

cargoBuildHost : Bool -> Task {} _
cargoBuildHost = \debugMode ->
    cargoBuildArgsT =
        if debugMode then
            Task.map
                (info "Building rust host in debug mode...")
                \_ -> ["build"]
        else
            Task.map
                (info "Building rust host ...")
                \_ -> ["build", "--release"]

    "cargo"
        |> Cmd.exec cargoBuildArgsT!
        |> Task.mapErr! ErrBuildingHostBinaries

copyHostLib : OSAndArch, Str -> Task {} _
copyHostLib = \osAndArch, rustTargetFolder ->
    hostBuildPath =
        "$(rustTargetFolder)libhost.a"

    hostDestPath = "platform/$(prebuiltStaticLibFile osAndArch)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

preprocessHost : Str, Str, Str -> Task {} _
preprocessHost = \rocCmd, stubLibPath, rustTargetFolder ->
    info! "Preprocessing surgical host ..."
    surgicalBuildPath = "$(rustTargetFolder)host"

    rocCmd
        |> Cmd.exec ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubLibPath]
        |> Task.mapErr! ErrPreprocessingSurgicalBinary

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
