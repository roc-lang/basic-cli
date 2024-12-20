module [
    Arg,
    display,
    to_os_raw,
    from_os_raw,
]

import InternalArg

# os_str's are not necessarily valid utf-8 or utf-16
# so we store as raw bytes internally to avoid
# common mistakes
Arg := InternalArg.ArgToAndFromHost

## Unwrap the raw bytes for decoding, typically this is
## consumed by a package and not an end user
to_os_raw : Arg -> [Unix (List U8), Windows (List U16)]
to_os_raw = \@Arg inner ->
    when inner.type is
        Unix -> Unix inner.unix
        Windows -> Windows inner.windows

from_os_raw : InternalArg.ArgToAndFromHost -> Arg
from_os_raw = \raw -> @Arg raw

## Convert an Arg to a `Str` for display purposes
##
## NB: this will currently crash if there is invalid utf8 bytes, in future this will be lossy and replace any invalid bytes with the [Unicode Replacement Character U+FFFD �](https://en.wikipedia.org/wiki/Specials_(Unicode_block))
display : Arg -> Str
display = \@Arg inner ->
    when inner.type is
        Unix ->
            # TODO replace with Str.from_utf8_lossy : List U8 -> Str
            # see https://github.com/roc-lang/roc/issues/7390
            when Str.fromUtf8 inner.unix is
                Ok str -> str
                Err _ -> crash "tried to display invalid utf-8"

        Windows ->
            # TODO replace with Str.from_utf16_lossy : List U16 -> Str
            # see https://github.com/roc-lang/roc/issues/7390
            crash "display for utf-16 not yet supported"
