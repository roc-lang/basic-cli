## Provides functionality to change the behaviour of the terminal.
## This is useful for running an app like vim or a game in the terminal.
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
## This leads to the following changes:
## - Input will not be echoed to the terminal screen.
## - Input will be sent straight to the program instead of being buffered (= collected) until the Enter key is pressed.
## - Special keys like Backspace and CTRL+C will not be processed by the terminal driver but will be passed to the program.
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
