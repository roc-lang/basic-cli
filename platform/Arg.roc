module [list!]

import PlatformTasks

## Gives a list of the program's command-line arguments.
list! : {} => List Str
list! = \{} ->
    PlatformTasks.args! {}
