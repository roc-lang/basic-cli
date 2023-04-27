interface Stdout
    exposes [Op, Info, line, write]
    imports [Task.{ Task }]

# These would be interface that could be defined in a pure Roc library.
# It is not really need for this platform, but this is just to show how the api would be split.
Op a : [
    Stdout (Info a),
    Done a,
]

Info a : [
    Line Str ({} -> Op a),
    Write Str ({} -> Op a),
]


# This could then go in a dependent module.

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
## followed by a newline.
##
## (To write to `stdout` without the newline, see [Stdout.write].)
line : Str -> Task {} * [Stdout [Line Str ({} -> Op a)]]
line = \s -> Task.fromInner \toNext -> Stdout (Line s \{} -> (toNext (Ok {})))

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
##
## Note that many terminals will not actually display strings that are written to them until they receive a newline,
## so this may appear to do nothing until you write a newline!
##
## (To write to `stdout` with a newline at the end, see [Stdout.line].)
write : Str -> Task {} * [Stdout [Write Str ({} -> Op a)]]
write = \s -> Task.fromInner \toNext -> Stdout (Write s \{} -> (toNext (Ok {})))
