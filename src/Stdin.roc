interface Stdin
    exposes [line]
    imports [Task.{ Task }]

## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
##
## Note that this task will block the program from continuing until `stdin` receives a newline character
## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
## programming having gotten stuck. It's often helpful to print a prompt first, so
## the user knows it's necessary to enter something before the program will continue.
line : Task Str *
line = Task.fromOp (StdinLine (\s -> Task.succeed s))
