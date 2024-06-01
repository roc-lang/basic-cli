hosted Effect
    exposes [
        Effect,
        after,
        args,
        map,
        always,
        forever,
        loop,
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
        udpBind,
        udpReceiveUpTo,
        sleepMillis,
        commandStatus,
        commandOutput,
    ]
    imports [
        InternalHttp.{ Request, InternalResponse },
        InternalFile,
        InternalTcp,
        InternalUdp,
        InternalCommand,
        InternalPath,
    ]
    generates Effect with [after, map, always, forever, loop]

stdoutLine : Str -> Effect (Result {} Str)
stdoutWrite : Str -> Effect (Result {} Str)
stderrLine : Str -> Effect (Result {} Str)
stderrWrite : Str -> Effect (Result {} Str)
stdinLine : Effect (Result Str Str)
stdinBytes : Effect (List U8)
ttyModeCanonical : Effect {}
ttyModeRaw : Effect {}

fileWriteBytes : List U8, List U8 -> Effect (Result {} InternalFile.WriteErr)
fileWriteUtf8 : List U8, Str -> Effect (Result {} InternalFile.WriteErr)
fileDelete : List U8 -> Effect (Result {} InternalFile.WriteErr)
fileReadBytes : List U8 -> Effect (Result (List U8) InternalFile.ReadErr)

envDict : Effect (Dict Str Str)
envVar : Str -> Effect (Result Str {})
exePath : Effect (Result (List U8) {})
setCwd : List U8 -> Effect (Result {} {})

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args : Effect (List Str)

cwd : Effect (List U8)

sendRequest : Box Request -> Effect InternalResponse

tcpConnect : Str, U16 -> Effect InternalTcp.ConnectResult
tcpClose : InternalTcp.Stream -> Effect {}
tcpReadUpTo : U64, InternalTcp.Stream -> Effect InternalTcp.ReadResult
tcpReadExactly : U64, InternalTcp.Stream -> Effect InternalTcp.ReadExactlyResult
tcpReadUntil : U8, InternalTcp.Stream -> Effect InternalTcp.ReadResult
tcpWrite : List U8, InternalTcp.Stream -> Effect InternalTcp.WriteResult

udpBind : Str, U16 -> Effect InternalUdp.BindResult
udpReceiveUpTo : U64, InternalUdp.Socket -> Effect InternalUdp.ReceiveResult


pathType : List U8 -> Effect (Result InternalPath.InternalPathType InternalPath.GetMetadataErr)

posixTime : Effect U128
sleepMillis : U64 -> Effect {}

commandStatus : Box InternalCommand.Command -> Effect (Result {} InternalCommand.CommandErr)
commandOutput : Box InternalCommand.Command -> Effect InternalCommand.Output

dirList : List U8 -> Effect (Result (List (List U8)) Str)
dirCreate : List U8 -> Effect (Result {} Str)
dirCreateAll : List U8 -> Effect (Result {} Str)
dirDeleteEmpty : List U8 -> Effect (Result {} Str)
dirDeleteAll : List U8 -> Effect (Result {} Str)
