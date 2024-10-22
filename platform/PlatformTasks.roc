hosted PlatformTasks
    exposes [
        TcpStream,
        FileReader,
        args!,
        dirList!,
        dirCreate!,
        dirCreateAll!,
        dirDeleteEmpty!,
        dirDeleteAll!,
        envDict!,
        envVar!,
        cwd!,
        setCwd!,
        exePath!,
        stdoutLine!,
        stdoutWrite!,
        stderrLine!,
        stderrWrite!,
        stdinLine!,
        stdinBytes!,
        ttyModeCanonical!,
        ttyModeRaw!,
        sendRequest!,
        fileReadBytes!,
        fileDelete!,
        fileWriteUtf8!,
        fileWriteBytes!,
        fileReader!,
        fileReadLine!,
        pathType!,
        posixTime!,
        tcpConnect!,
        tcpReadUpTo!,
        tcpReadExactly!,
        tcpReadUntil!,
        tcpWrite!,
        sleepMillis!,
        commandStatus!,
        commandOutput!,
        currentArchOS!,
        tempDir!,
    ]
    imports [
        InternalHttp.{ Request, InternalResponse },
        InternalCommand,
        InternalPath,
    ]

stdoutLine! : Str => Result {} Str
stdoutWrite! : Str => Result {} Str
stderrLine! : Str => Result {} Str
stderrWrite! : Str => Result {} Str
stdinLine! : {} => Result Str Str
stdinBytes! : {} => List U8
ttyModeCanonical! : {} => {}
ttyModeRaw! : {} => {}

fileWriteBytes! : List U8, List U8 => Result {} Str
fileWriteUtf8! : List U8, Str => Result {} Str
fileDelete! : List U8 => Result {} Str
fileReadBytes! : List U8 => Result (List U8) Str

FileReader := Box {}
fileReader! : List U8, U64 => Result FileReader Str
fileReadLine! : FileReader => Result (List U8) Str

envDict! : {} => List (Str, Str)
envVar! : Str => Result Str {}
exePath! : {} => Result (List U8) {}
setCwd! : List U8 => Result {} {}

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args! : {} => List Str

cwd! : {} => Result (List U8) {}

sendRequest! : Box Request => InternalResponse

TcpStream := Box {}
tcpConnect! : Str, U16 => Result TcpStream Str
tcpReadUpTo! : TcpStream, U64 => Result (List U8) Str
tcpReadExactly! : TcpStream, U64 => Result (List U8) Str
tcpReadUntil! : TcpStream, U8 => Result (List U8) Str
tcpWrite! : TcpStream, List U8 => Result {} Str

pathType! : List U8 => Result InternalPath.InternalPathType (List U8)

posixTime! : {} => Result U128 {}
sleepMillis! : U64 => {}

commandStatus! : Box InternalCommand.Command => Result {} (List U8)
commandOutput! : Box InternalCommand.Command => InternalCommand.Output

dirList! : List U8 => Result (List (List U8)) Str
dirCreate! : List U8 => Result {} Str
dirCreateAll! : List U8 => Result {} Str
dirDeleteEmpty! : List U8 => Result {} Str
dirDeleteAll! : List U8 => Result {} Str

currentArchOS! : {} => { arch : Str, os : Str }

tempDir! : {} => List U8
