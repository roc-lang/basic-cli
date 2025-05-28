## Provides functionality to liberate the terminal from its default behaviour.
## This is useful for making a terminal app like vim or a game.
##
## Note: we plan on moving this file away from basic-cli in the future, see github.com/roc-lang/basic-cli/issues/73
##
module [
    disable_raw_mode!,
    enable_raw_mode!,
]

import Host

## Enable terminal [raw mode](https://en.wikipedia.org/wiki/Terminal_mode) to disable some default terminal bevahiour.
##
## The following modes are disabled:
## - Input will not be echoed to the terminal screen
## - Input will not be buffered until Enter key is pressed
## - Input will not be line buffered (input sent byte-by-byte to input buffer)
## - Special keys like Backspace and CTRL+C will not be processed by terminal driver
##
## Note: we plan on moving this function away from basic-cli in the future, see github.com/roc-lang/basic-cli/issues/73
##
enable_raw_mode! : {} => {}
enable_raw_mode! = |{}|
    Host.tty_mode_raw!({})

## Revert terminal to default behaviour
##
## Note: we plan on moving this function away from basic-cli in the future, see github.com/roc-lang/basic-cli/issues/73
##
disable_raw_mode! : {} => {}
disable_raw_mode! = |{}|
    Host.tty_mode_canonical!({})
