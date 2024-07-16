app [main] {
    cli: platform "platform/main.roc", # TODO use basic-cli 0.13 url
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
## run with: roc ./build.roc
##
## Check basic-cli-build-steps.png for a diagram that shows what the code does.
##
main : Task {} _
main =

    cliParser =
        Arg.Opt.maybeStr { short: "p", long: "roc", help: "Path to the roc executable. Can be just `roc` or a full path."}
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

run : Result Str err -> Task {} _
run = \maybeRoc ->
    # rocCmd may be a path or just roc
    rocCmd = maybeRoc |> Result.withDefault "roc"

    generateGlue! rocCmd

    # target is MacosArm64, LinuxX64,...
    target = getNativeTarget!

    stubLibPath = "platform/libapp.$(stubFileExtension target)"

    buildStubAppLib! rocCmd stubLibPath

    cargoBuildHost!

    copyHostLib! target

    preprocessHost! rocCmd stubLibPath

    info! "Successfully built platform files!"

generateGlue : Str -> Task {} _
generateGlue = \rocCmd ->
    info! "Generating glue for builtins ..."

    rocCmd
        |> Cmd.exec  ["glue", "glue.roc", "crates/", "platform/main.roc"]
        |> Task.mapErr! ErrGeneratingGlue

getNativeTarget : Task RocTarget _
getNativeTarget =
    info! "Getting the native target ..."
    
    Env.platform
    |> Task.await convertNativeTarget

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convertNativeTarget : _ -> Task RocTarget _
convertNativeTarget =\{os, arch} ->
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
        |> Cmd.exec  ["build", "--lib", "platform/libapp.roc", "--output", stubLibPath]
        |> Task.mapErr! ErrBuildingAppStub

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

cargoBuildHost : Task {} _
cargoBuildHost =
    cargoBuildArgs =
        ["build", "--release"]


    info! "Building host in RELEASE mode ..."
    "cargo"
        |> Cmd.exec  cargoBuildArgs
        |> Task.mapErr! ErrBuildingHostBinaries

copyHostLib : RocTarget -> Task {} _
copyHostLib = \target ->
    hostBuildPath = "target/release/libhost.a"
    hostDestPath = "platform/$(prebuiltStaticLibFile target)"

    info! "Moving the prebuilt binary from $(hostBuildPath) to $(hostDestPath) ..."
    "cp"
        |> Cmd.exec  [hostBuildPath, hostDestPath]
        |> Task.mapErr! ErrMovingPrebuiltLegacyBinary

preprocessHost : Str, Str -> Task {} _
preprocessHost = \rocCmd, stubLibPath ->
    info! "Preprocessing surgical host ..."
    surgicalBuildPath = "target/release/host"
    
    rocCmd
        |> Cmd.exec  ["preprocess-host", surgicalBuildPath, "platform/main.roc", stubLibPath]
        |> Task.mapErr! ErrPreprocessingSurgicalBinary

info : Str -> Task {} _
info = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
