platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

import Host

InternalIOErr : Host.InternalIOErr

mainForHost : InternalIOErr
mainForHost = main
