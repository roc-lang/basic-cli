module [
    Arg,
    display,
    to_os_raw,
    from_os_raw,
]

## An OS-aware (see below) representation of a command-line argument.
##
## Though we tend to think of args as Unicode strings, **most operating systems
## represent command-line arguments as lists of bytes** that aren't necessarily
## UTF-8 encoded. Windows doesn't even use bytes, but U16s.
##
## Most of the time, you will pass these to packages and they will handle the
## encoding for you, but for quick-and-dirty code you can use [display] to
## convert these to [Str] in a lossy way.
Arg := [Unix (List U8), Windows (List U16)]
    implements [Eq, Inspect { to_inspector: arg_inspector }]

arg_inspector : Arg -> Inspector f where f implements InspectFormatter
arg_inspector = |arg| Inspect.str(display(arg))

test_hello : Arg
test_hello = Arg.from_os_raw(Unix([72, 101, 108, 108, 111]))

expect Arg.display(test_hello) == "Hello"
expect Inspect.to_str(test_hello) == "\"Hello\""

## Unwrap an [Arg] into a raw, OS-aware numeric list.
##
## This is a good way to pass [Arg]s to Roc packages.
to_os_raw : Arg -> [Unix (List U8), Windows (List U16)]
to_os_raw = |@Arg(inner)| inner

## Wrap a raw, OS-aware numeric list into an [Arg].
from_os_raw : [Unix (List U8), Windows (List U16)] -> Arg
from_os_raw = @Arg

## Convert an Arg to a `Str` for display purposes.
##
## NB: this will currently crash if there is invalid utf8 bytes, in future this will be lossy and replace any invalid bytes with the [Unicode Replacement Character U+FFFD �](https://en.wikipedia.org/wiki/Specials_(Unicode_block))
display : Arg -> Str
display = |@Arg(inner)|
    when inner is
        Unix(bytes) ->
            # TODO replace with Str.from_utf8_lossy : List U8 -> Str
            # see https://github.com/roc-lang/roc/issues/7390
            when Str.from_utf8(bytes) is
                Ok(str) -> str
                Err(_) -> crash("tried to display Arg containing invalid utf-8")

        Windows(_) ->
            # TODO replace with Str.from_utf16_lossy : List U16 -> Str
            # see https://github.com/roc-lang/roc/issues/7390
            crash("display for utf-16 Arg not yet supported")
