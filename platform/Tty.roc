## Provides functionality to change the behaviour of the terminal.
## This is useful for running an app like vim or a game in the terminal.
Tty := [].{
    ## Enable terminal [raw mode](https://en.wikipedia.org/wiki/Terminal_mode) to disable some default terminal bevahiour.
    ##
    ## This leads to the following changes:
    ## - Input will not be echoed to the terminal screen.
    ## - Input will be sent straight to the program instead of being buffered (= collected) until the Enter key is pressed.
    ## - Special keys like Backspace and CTRL+C will not be processed by the terminal driver but will be passed to the program.
    enable_raw_mode! : () => {}

    ## Revert terminal to default behaviour
    disable_raw_mode! : () => {}
}
