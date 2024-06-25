hosted PlatformTask
    exposes [
        args,
        dirList,
        dirCreate,
        dirCreateAll,
        dirDeleteEmpty,
        dirDeleteAll,
        envDict,
        envVar,
        cwd,
        setCwd,
        exePath,
        stdoutLine,
        stdoutWrite,
        stderrLine,
        stderrWrite,
        stdinLine,
        stdinBytes,
        ttyModeCanonical,
        ttyModeRaw,
        sendRequest,
        fileReadBytes,
        fileDelete,
        fileWriteUtf8,
        fileWriteBytes,
        pathType,
        posixTime,
        tcpConnect,
        tcpClose,
        tcpReadUpTo,
        tcpReadExactly,
        tcpReadUntil,
        tcpWrite,
        sleepMillis,
        commandStatus,
        commandOutput,
        currentArchOS,
    ]
    imports [
        InternalHttp.{ Request, InternalResponse },
        InternalFile,
        InternalTcp,
        InternalCommand,
        InternalPath,
    ]

stdoutLine : Str -> Task {} Str
stdoutWrite : Str -> Task {} Str
stderrLine : Str -> Task {} Str
stderrWrite : Str -> Task {} Str
stdinLine :  Result Str Str
stdinBytes : Task (List U8) *
ttyModeCanonical : Task {} *
ttyModeRaw : Task {} *

fileWriteBytes : List U8, List U8 -> Task {} InternalFile.WriteErr
fileWriteUtf8 : List U8, Str -> Task {} InternalFile.WriteErr
fileDelete : List U8 -> Task {} InternalFile.WriteErr
fileReadBytes : List U8 -> Task (List U8) InternalFile.ReadErr

envDict : Task (Dict Str Str) *
envVar : Str -> Task Str {}
exePath : Task (List U8) {}
setCwd : List U8 -> Task {} {}

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args : Task (List Str) *

cwd : Task (List U8) *

sendRequest : Box Request -> Task InternalResponse *

# TODO: split up InternalTcp.*Result into ok and err values
tcpConnect : Str, U16 -> Task InternalTcp.ConnectResult *
tcpClose : InternalTcp.Stream -> Task {} *
tcpReadUpTo : U64, InternalTcp.Stream -> Task InternalTcp.ReadResult *
tcpReadExactly : U64, InternalTcp.Stream -> Task InternalTcp.ReadExactlyResult *
tcpReadUntil : U8, InternalTcp.Stream -> Task InternalTcp.ReadResult *
tcpWrite : List U8, InternalTcp.Stream -> Task InternalTcp.WriteResult *

pathType : List U8 -> Task InternalPath.InternalPathType InternalPath.GetMetadataErr

posixTime : Task U128 *
sleepMillis : U64 -> Task {} *

commandStatus : Box InternalCommand.Command -> Task {} InternalCommand.CommandErr
commandOutput : Box InternalCommand.Command -> Task InternalCommand.Output *

dirList : List U8 -> Task (List (List U8)) Str
dirCreate : List U8 -> Task {} Str
dirCreateAll : List U8 -> Task {} Str
dirDeleteEmpty : List U8 -> Task {} Str
dirDeleteAll : List U8 -> Task {} Str

currentArchOS : Task { arch : Str, os : Str } *
