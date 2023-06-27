## Provides functionality to work with the terminal
##
## Note: we plan on moving this file away from basic-cli in the future, see github.com/roc-lang/basic-cli/issues/73
##
interface Tty
    exposes [
        disableRawMode,
        enableRawMode,
    ]
    imports [Effect, Task.{ Task }, InternalTask]

## Enable terminal raw mode which disables some default terminal bevahiour.
##
## The following modes are disabled:
## - Input will not be echo to the terminal screen
## - Input will not be buffered until Enter key is pressed
## - Input will not be line buffered (input sent byte-by-byte to input buffer)
## - Special keys like Backspace and CTRL+C will not be processed by terminal driver
##
## Note: we plan on moving this function away from basic-cli in the future, see github.com/roc-lang/basic-cli/issues/73
##
enableRawMode : Task {} *
enableRawMode =
    Effect.ttyModeRaw
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Revert terminal to default behaviour
##
## Note: we plan on moving this function away from basic-cli in the future, see github.com/roc-lang/basic-cli/issues/73
##
disableRawMode : Task {} *
disableRawMode =
    Effect.ttyModeCanonical
    |> Effect.map Ok
    |> InternalTask.fromEffect
