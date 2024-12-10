platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

import PlatformTasks

InternalIOErr : PlatformTasks.InternalIOErr

mainForHost : InternalIOErr
mainForHost = main
