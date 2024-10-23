module [list!]

import PlatformTasks

#import Arg.Cli exposing [CliParser]
#import Arg.ErrorFormatter
#import Arg.Help

## Gives a list of the program's command-line arguments.
list! : {} => List Str
list! = \{} ->
    PlatformTasks.args! {}

# TODO
# I deleted the Arg parser as a workaround for issues it was causing when upgrading to purity inference.
# The plan is for people so use Weaver or simmilar in future. We can discuss putting it back in if we still
# want the "batteries included" experience, but either way that will need to be upgraded/tested with
# purity-inference.
