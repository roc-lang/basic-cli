platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

import Host

mainForHost : Host.InternalIOErr
mainForHost = main
