app "build-platform-prebuilt-binaries"
    packages {
        cli: "https://github.com/roc-lang/basic-cli/releases/download/0.10.0/vNe6s9hWzoTZtFmNkvEICPErI9ptji_ySjicO6CkucY.tar.br",
    }
    imports [
        cli.Task.{Task},
        cli.Stdout,
        cli.Cmd,
    ]
    provides [main] to cli

RocTarget : [
    MacosArm64,
    MacosX64,
    LinuxArm64,
    LinuxX64,
    WindowsArm64,
    WindowsX64,
]

mode : [DEBUG, RELEASE]
mode = DEBUG

main = 
    native = getNativeTarget!
    removePrebuiltBinary! native
    buildRustTarget! native
    copyBinaryToPlatform! native
    Stdout.line! "COMPLETE"

    Task.ok {}

getNativeTarget : Task RocTarget _
getNativeTarget = 

    Stdout.line! "Geting native target..."

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
        |> Task.mapErr! \err -> ErrGettingNativeArch (Inspect.toStr err) 

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
        |> Task.mapErr! \err -> ErrGettingNativeOS (Inspect.toStr err) 

    when (os, arch) is 
        (Macos, Arm64) -> Task.ok MacosArm64
        (Macos, X64) -> Task.ok MacosX64
        (Linux, Arm64) -> Task.ok LinuxArm64
        (Linux, X64) -> Task.ok LinuxX64
        _ -> Task.err (UnsupportedNative os arch)

prebuiltBinaryPath : RocTarget -> Str 
prebuiltBinaryPath = \target ->
    when target is 
        MacosArm64 -> "platform/macos-arm64.a"
        MacosX64 -> "platform/macos-x64"
        LinuxArm64 -> "platform/linux-arm64.a"
        LinuxX64 -> "platform/linux-x64.a"
        WindowsArm64 -> "platform/windows-arm64.a"
        WindowsX64 -> "platform/windows-x64"

removePrebuiltBinary : RocTarget -> Task {} _
removePrebuiltBinary = \target ->

    Stdout.line! "Removing prebuilt binary $(Inspect.toStr target)..."

    Cmd.new "rm" 
    |> Cmd.args ["-f", prebuiltBinaryPath target] 
    |> Cmd.status
    |> Task.mapErr! ErrRemovingPrebuiltBinary
        
rustupTarget : RocTarget -> Str
rustupTarget = \target ->
    when target is
        MacosArm64 -> "aarch64-apple-darwin"
        MacosX64 -> "x86_64-apple-darwin"
        LinuxArm64 -> "aarch64-unknown-linux-musl"
        LinuxX64 -> "x86_64-unknown-linux-musl"
        WindowsArm64 -> "aarch64-pc-windows-msvc"
        WindowsX64 -> "x86_64-pc-windows-msvc"

buildRustTarget : RocTarget -> Task {} _
buildRustTarget = \target -> 

    Stdout.line! "Building rust target $(Inspect.toStr target)..."

    args =
        when mode is 
            DEBUG -> ["build", "--target=$(rustupTarget target)"]
            RELEASE -> ["build", "--release", "--target=$(rustupTarget target)"]

    Cmd.new "cargo"
    |> Cmd.args args
    |> Cmd.status
    |> Task.mapErr! ErrBuildingRustTarget

cargoTargetPath : RocTarget -> Str
cargoTargetPath = \target ->
    when mode is 
        DEBUG -> "target/$(rustupTarget target)/debug/libhost.a" 
        RELEASE -> "target/$(rustupTarget target)/release/libhost.a" 

copyBinaryToPlatform : RocTarget -> Task {} _
copyBinaryToPlatform = \target ->

    from = cargoTargetPath target
    to = prebuiltBinaryPath target

    Stdout.line! "Copy prebuilt binary from $(from) to $(to)..."

    Cmd.new "cp"
    |> Cmd.args ["-f", from, to]
    |> Cmd.status
    |> Task.mapErr! ErrCopyingPrebuiltBinary
