app [main!] {
    cli: platform "platform/main.roc",
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
main! : List Str => Result {} _
main! = \_args ->

    rocCmd = Env.var! "ROC" |> Result.withDefault "roc"

    debugMode =
        when Env.var! "DEBUG" is
            Ok str if !(Str.isEmpty str) -> Debug
            _ -> Release

    try rocVersion! rocCmd

    osAndArch = try getOSAndArch! {}

    stubLibPath = "platform/libapp.$(stubFileExtension osAndArch)"

    try buildStubAppLib! rocCmd stubLibPath

    try cargoBuildHost! debugMode

    rustTargetFolder = try getRustTargetFolder! debugMode

    try copyHostLib! osAndArch rustTargetFolder

    try preprocessHost! rocCmd stubLibPath rustTargetFolder

    try info! "Successfully built platform files!"

    Ok {}

rocVersion! : Str => Result {} _
rocVersion! = \rocCmd ->
    try info! "Checking provided roc; executing `$(rocCmd) version`:"

    rocCmd
    |> Cmd.exec! ["version"]
    |> Result.mapErr RocVersionCheckFailed

getOSAndArch! : {} => Result OSAndArch _
getOSAndArch! = \{} ->
    try info! "Getting the native operating system and architecture ..."

    { os, arch } = Env.platform! {}

    convertOSAndArch! { os, arch }

OSAndArch : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convertOSAndArch! : _ => Result OSAndArch _
convertOSAndArch! = \{ os, arch } ->
    when (os, arch) is
        (MACOS, AARCH64) -> Ok MacosArm64
        (MACOS, X64) -> Ok MacosX64
        (LINUX, AARCH64) -> Ok LinuxArm64
        (LINUX, X64) -> Ok LinuxX64
        _ -> Err (UnsupportedNative os arch)

buildStubAppLib! : Str, Str => Result {} _
buildStubAppLib! = \rocCmd, stubLibPath ->
    try info! "Building stubbed app shared library ..."

    rocCmd
    |> Cmd.exec! ["build", "--lib", "platform/libapp.roc", "--output", stubLibPath, "--optimize"]
    |> Result.mapErr ErrBuildingAppStub

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

getRustTargetFolder! : [Debug, Release] => Result Str _
getRustTargetFolder! = \debugMode ->

    debugOrRelease = if debugMode == Debug then "debug" else "release"

    when Env.var! "CARGO_BUILD_TARGET" is
        Ok targetEnvVar ->
            if Str.isEmpty targetEnvVar then
                Ok "target/$(debugOrRelease)/"
            else
                Ok "target/$(targetEnvVar)/$(debugOrRelease)/"

        Err e ->
            try info! "Failed to get env var CARGO_BUILD_TARGET with error $(Inspect.toStr e). Assuming default CARGO_BUILD_TARGET (native)..."

            Ok "target/$(debugOrRelease)/"

cargoBuildHost! : [Debug, Release] => Result {} _
cargoBuildHost! = \debugMode ->
    cargoBuildArgs =
        when debugMode is
            Debug -> Result.map (info! "Building rust host in debug mode...") \_ -> ["build"]
            Release -> Result.map (info! "Building rust host ...") \_ -> ["build", "--release"]

    "cargo"
    |> Cmd.exec! (try cargoBuildArgs)
    |> Result.mapErr ErrBuildingHostBinaries

copyHostLib! : OSAndArch, Str => Result {} _
copyHostLib! = \osAndArch, rustTargetFolder ->

    hostBuildPath = "$(rustTargetFolder)libhost.a"

    hostDestPath = "platform/$(prebuiltStaticLibFile osAndArch)"

    try info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."

    "cp"
    |> Cmd.exec! [hostBuildPath, hostDestPath]
    |> Result.mapErr ErrMovingPrebuiltLegacyBinary

preprocessHost! : Str, Str, Str => Result {} _
preprocessHost! = \rocCmd, stubLibPath, rustTargetFolder ->

    try info! "Preprocessing surgical host ..."

    surgicalBuildPath = "$(rustTargetFolder)host"

    rocCmd
    |> Cmd.exec! ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubLibPath]
    |> Result.mapErr ErrPreprocessingSurgicalBinary

info! : Str => Result {} _
info! = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
