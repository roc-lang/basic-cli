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
main! : _ => Result {} _
main! = \_ ->

    roc_cmd = Env.var! "ROC" |> Result.withDefault "roc"

    debug_mode =
        when Env.var! "DEBUG" is
            Ok str if !(Str.isEmpty str) -> Debug
            _ -> Release

    try roc_version! roc_cmd

    os_and_arch = try get_os_and_arch! {}

    stub_lib_path = "platform/libapp.$(stub_file_extension os_and_arch)"

    try build_stub_app_lib! roc_cmd stub_lib_path

    try cargo_build_host! debug_mode

    rust_target_folder = try get_rust_target_folder! debug_mode

    try copy_host_lib! os_and_arch rust_target_folder

    try preprocess_host! roc_cmd stub_lib_path rust_target_folder

    try info! "Successfully built platform files!"

    Ok {}

roc_version! : Str => Result {} _
roc_version! = \roc_cmd ->
    try info! "Checking provided roc; executing `$(roc_cmd) version`:"

    roc_cmd
    |> Cmd.exec! ["version"]
    |> Result.mapErr RocVersionCheckFailed

get_os_and_arch! : {} => Result OSAndArch _
get_os_and_arch! = \{} ->
    try info! "Getting the native operating system and architecture ..."

    { os, arch } = Env.platform! {}

    convert_os_and_arch!! { os, arch }

OSAndArch : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

convert_os_and_arch! : _ => Result OSAndArch _
convert_os_and_arch! = \{ os, arch } ->
    when (os, arch) is
        (MACOS, AARCH64) -> Ok MacosArm64
        (MACOS, X64) -> Ok MacosX64
        (LINUX, AARCH64) -> Ok LinuxArm64
        (LINUX, X64) -> Ok LinuxX64
        _ -> Err (UnsupportedNative os arch)

build_stub_app_lib! : Str, Str => Result {} _
build_stub_app_lib! = \roc_cmd, stub_lib_path ->
    try info! "Building stubbed app shared library ..."

    roc_cmd
    |> Cmd.exec! ["build", "--lib", "platform/libapp.roc", "--output", stub_lib_path, "--optimize"]
    |> Result.mapErr ErrBuildingAppStub

stub_file_extension : OSAndArch -> Str
stub_file_extension = \os_and_arch ->
    when os_and_arch is
        MacosX64 | MacosArm64 -> "dylib"
        LinuxArm64 | LinuxX64 -> "so"
        WindowsX64 | WindowsArm64 -> "dll"

prebuilt_static_lib_file : OSAndArch -> Str
prebuilt_static_lib_file = \os_and_arch ->
    when os_and_arch is
        MacosArm64 -> "macos-arm64.a"
        MacosX64 -> "macos-x64.a"
        LinuxArm64 -> "linux-arm64.a"
        LinuxX64 -> "linux-x64.a"
        WindowsArm64 -> "windows-arm64.lib"
        WindowsX64 -> "windows-x64.lib"

get_rust_target_folder! : [Debug, Release] => Result Str _
get_rust_target_folder! = \debug_mode ->

    debug_or_release = if debug_mode == Debug then "debug" else "release"

    when Env.var! "CARGO_BUILD_TARGET" is
        Ok target_env_var ->
            if Str.isEmpty target_env_var then
                Ok "target/$(debug_or_release)/"
            else
                Ok "target/$(target_env_var)/$(debug_or_release)/"

        Err e ->
            try info! "Failed to get env var CARGO_BUILD_TARGET with error $(Inspect.toStr e). Assuming default CARGO_BUILD_TARGET (native)..."

            Ok "target/$(debug_or_release)/"

cargo_build_host! : [Debug, Release] => Result {} _
cargo_build_host! = \debug_mode ->
    cargo_build_args =
        when debug_mode is
            Debug -> Result.map (info! "Building rust host in debug mode...") \_ -> ["build"]
            Release -> Result.map (info! "Building rust host ...") \_ -> ["build", "--release"]

    "cargo"
    |> Cmd.exec! (try cargo_build_args)
    |> Result.mapErr ErrBuildingHostBinaries

copy_host_lib! : OSAndArch, Str => Result {} _
copy_host_lib! = \os_and_arch, rust_target_folder ->

    host_build_path = "$(rust_target_folder)libhost.a"

    host_dest_path = "platform/$(prebuilt_static_lib_file os_and_arch)"

    try info! "Moving the prebuilt binary from $(host_build_path) to $(host_dest_path) ..."

    "cp"
    |> Cmd.exec! [host_build_path, host_dest_path]
    |> Result.mapErr ErrMovingPrebuiltLegacyBinary

preprocess_host! : Str, Str, Str => Result {} _
preprocess_host! = \roc_cmd, stub_lib_path, rust_target_folder ->

    try info! "Preprocessing surgical host ..."

    surgical_build_path = "$(rust_target_folder)host"

    roc_cmd
    |> Cmd.exec! ["preprocess-host", surgical_build_path, "platform/main.roc", stub_lib_path]
    |> Result.mapErr ErrPreprocessingSurgicalBinary

info! : Str => Result {} _
info! = \msg ->
    Stdout.line! "\u(001b)[34mINFO:\u(001b)[0m $(msg)"
