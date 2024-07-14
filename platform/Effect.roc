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
        fileReader,
        fileReadLine,
        closeFile,
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
        InternalHttp,
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

fileWriteBytes : List U8, List U8 -> Effect (Result {} Str)
fileWriteUtf8 : List U8, Str -> Effect (Result {} Str)
fileDelete : List U8 -> Effect (Result {} Str)
fileReadBytes : List U8 -> Effect (Result (List U8) Str)

fileReader : List U8 -> Effect (Result U64 Str)
fileReadLine : U64 -> Effect (Result (List U8) Str)
closeFile : U64 -> Effect {}

envDict : Effect (List (Str, Str))
envVar : Str -> Effect (Result Str {})
exePath : Effect (Result (List U8) {})
setCwd : List U8 -> Effect (Result {} {})

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args : Effect (List Str)

cwd : Effect (List U8)

sendRequest : Box InternalHttp.Request -> Effect InternalHttp.InternalResponse

tcpConnect : Str, U16 -> Effect (Result U64 Str)
tcpClose : U64 -> Effect {}
tcpReadUpTo : U64, U64 -> Effect (Result (List U8) Str)
tcpReadExactly : U64, U64 -> Effect (Result (List U8) Str)
tcpReadUntil : U64, U8 -> Effect (Result (List U8) Str)
tcpWrite : U64, List U8 -> Effect (Result {} Str)

pathType : List U8 -> Effect (Result InternalPath.InternalPathType (List U8))

posixTime : Effect U128
sleepMillis : U64 -> Effect {}

commandStatus : Box InternalCommand.Command -> Effect (Result {} (List U8))
commandOutput : Box InternalCommand.Command -> Effect InternalCommand.Output

dirList : List U8 -> Effect (Result (List (List U8)) Str)
dirCreate : List U8 -> Effect (Result {} Str)
dirCreateAll : List U8 -> Effect (Result {} Str)
dirDeleteEmpty : List U8 -> Effect (Result {} Str)
dirDeleteAll : List U8 -> Effect (Result {} Str)

currentArchOS : Effect { arch : Str, os : Str }
