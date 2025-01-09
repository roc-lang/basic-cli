# This file isn't used per-se, I have left it here to help with generating rust glue for the platform
# In future glue types may be all generated from the platform file, but for now these are semi-automated.
#
# You can generate "glue" types using the following, though this feature is a WIP so things will need to
# be manually adjusted after generation.
#
# ```
# $ roc glue ../roc/crates/glue/src/RustGlue.roc asdf/ platform/glue-internal-arg.roc
# ```
platform "glue-types"
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [main_for_host]

import InternalArg

main_for_host : InternalArg.ArgToAndFromHost
main_for_host = main
