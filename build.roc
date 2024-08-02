app [main] {
    cli: platform "platform/main.roc", # TODO use basic-cli 0.13 url
}

import cli.Task exposing [Task]
import cli.Cmd
import cli.Stdout
import cli.Env
import cli.Arg
import cli.Arg.Opt as Opt
import cli.Arg.Cli as Cli

## Builds the basic-cli [platform](https://www.roc-lang.org/platforms).
##
## run with: roc ./build.roc
##
## Check basic-cli-build-steps.png for a diagram that shows what the code does.
##
main : Task {} _
main =

    cliParser =
        { Cli.combine <-
            debugMode: Opt.flag { short: "d", long: "debug", help: "Runs `cargo build` without `--release`." },
            maybeRoc: Opt.maybeStr { short: "r", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path." },
        }
        |> Cli.finish {
            name: "basic-cli-builder",
            version: "",
            authors: ["Luke Boswell <https://github.com/lukewilliamboswell>"],
            description: "Generates all files needed by Roc to use this basic-cli platform.",
        }
        |> Cli.assertValid

    when Cli.parseOrDisplayMessage cliParser (Arg.list! {}) is
        Ok args -> run args
        Err errMsg -> Task.err (Exit 1 errMsg)

run : {debugMode: Bool, maybeRoc: Result Str err} -> Task {} _
run = \{debugMode, maybeRoc} ->
    # rocCmd may be a path or just roc
    rocCmd = maybeRoc |> Result.withDefault "roc"

    rocVersion! rocCmd

    generateGlue! rocCmd

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
        |> Cmd.exec  ["version"]
        |> Task.mapErr! RocVersionCheckFailed

generateGlue : Str -> Task {} _
generateGlue = \rocCmd ->
    info! "Generating glue for builtins ..."

    rocCmd
        |> Cmd.exec  ["glue", "glue.roc", "crates/", "platform/main.roc"]
        |> Task.mapErr! ErrGeneratingGlue

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
convertOSAndArch =\{os, arch} ->
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
        |> Cmd.exec  ["build", "--lib", "platform/libapp.roc", "--output", stubLibPath, "--optimize"]
        |> Task.mapErr! ErrBuildingAppStub

stubFileExtension : OSAndArch -> Str
stubFileExtension = \osAndArch ->
    when osAndArch is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64-> "so"
        WindowsX64| WindowsArm64 -> "dll"

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
            info! "Failed to get env var CARGO_BUILD_TARGET with error \(Inspect.toStr e). Assuming default CARGO_BUILD_TARGET (native)..."
            
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
        |> Cmd.exec  cargoBuildArgsT!
        |> Task.mapErr! ErrBuildingHostBinaries

copyHostLib : OSAndArch, Str -> Task {} _
copyHostLib = \osAndArch, rustTargetFolder ->
    hostBuildPath =
        "$(rustTargetFolder)libhost.a"

    hostDestPath = "platform/$(prebuiltStaticLibFile osAndArch)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec  [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

preprocessHost : Str, Str, Str -> Task {} _
preprocessHost = \rocCmd, stubLibPath, rustTargetFolder ->
    info! "Preprocessing surgical host ..."
    surgicalBuildPath = "$(rustTargetFolder)host"
    
    rocCmd
        |> Cmd.exec  ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubLibPath]
        |> Task.mapErr! ErrPreprocessingSurgicalBinary

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
