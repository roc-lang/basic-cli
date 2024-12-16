hosted Host
    exposes [
        TcpStream,
        FileReader,
        InternalIOErr,
        args!,
        dirList!,
        dirCreate!,
        dirCreateAll!,
        dirDeleteEmpty!,
        dirDeleteAll!,
        hardLink!,
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
        stdinReadToEnd!,
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
        getLocale!,
        getLocales!,
    ]
    imports []

import InternalHttp
import InternalCommand
import InternalPath

InternalIOErr : {
    tag : [
        EndOfFile,
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other,
    ],
    msg : Str,
}

# COMMAND
commandStatus! : Box InternalCommand.Command => Result {} (List U8)
commandOutput! : Box InternalCommand.Command => InternalCommand.Output

# FILE
fileWriteBytes! : List U8, List U8 => Result {} InternalIOErr
fileWriteUtf8! : List U8, Str => Result {} InternalIOErr
fileDelete! : List U8 => Result {} InternalIOErr
fileReadBytes! : List U8 => Result (List U8) InternalIOErr

FileReader := Box {}
fileReader! : List U8, U64 => Result FileReader InternalIOErr
fileReadLine! : FileReader => Result (List U8) InternalIOErr

dirList! : List U8 => Result (List (List U8)) InternalIOErr
dirCreate! : List U8 => Result {} InternalIOErr
dirCreateAll! : List U8 => Result {} InternalIOErr
dirDeleteEmpty! : List U8 => Result {} InternalIOErr
dirDeleteAll! : List U8 => Result {} InternalIOErr

hardLink! : List U8 => Result {} InternalIOErr
pathType! : List U8 => Result InternalPath.InternalPathType InternalIOErr
cwd! : {} => Result (List U8) {}
tempDir! : {} => List U8

# STDIO
stdoutLine! : Str => Result {} InternalIOErr
stdoutWrite! : Str => Result {} InternalIOErr
stderrLine! : Str => Result {} InternalIOErr
stderrWrite! : Str => Result {} InternalIOErr
stdinLine! : {} => Result Str InternalIOErr
stdinBytes! : {} => Result (List U8) InternalIOErr
stdinReadToEnd! : {} => Result (List U8) InternalIOErr

# TCP
sendRequest! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

TcpStream := Box {}
tcpConnect! : Str, U16 => Result TcpStream Str
tcpReadUpTo! : TcpStream, U64 => Result (List U8) Str
tcpReadExactly! : TcpStream, U64 => Result (List U8) Str
tcpReadUntil! : TcpStream, U8 => Result (List U8) Str
tcpWrite! : TcpStream, List U8 => Result {} Str

# OTHERS
currentArchOS! : {} => { arch : Str, os : Str }

getLocale! : {} => Result Str {}
getLocales! : {} => List Str

posixTime! : {} => U128 # TODO why is this a U128 but then getting converted to a I128 in Utc.roc?

sleepMillis! : U64 => {}

ttyModeCanonical! : {} => {}
ttyModeRaw! : {} => {}

envDict! : {} => List (Str, Str)
envVar! : Str => Result Str {}
exePath! : {} => Result (List U8) {}
setCwd! : List U8 => Result {} {}

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args! : {} => List Str
