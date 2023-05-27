interface Stdout
    exposes [line, write]
    imports [Task.{ Task }]

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
## followed by a newline.
##
## (To write to `stdout` without the newline, see [Stdout.write].)
line : Str -> Task {} *
line = \str ->
    toNext <- Task.fromInner
    {} <- StdoutLine str
    toNext (Ok {})

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
##
## Note that many terminals will not actually display strings that are written to them until they receive a newline,
## so this may appear to do nothing until you write a newline!
##
## (To write to `stdout` with a newline at the end, see [Stdout.line].)
write : Str -> Task {} *
write = \str ->
    toNext <- Task.fromInner
    {} <- StdoutWrite str
    toNext (Ok {})
