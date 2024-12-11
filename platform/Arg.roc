module [list!]

import Host

## Gives a list of the program's command-line arguments.
list! : {} => List Str
list! = \{} ->
    Host.args! {}
