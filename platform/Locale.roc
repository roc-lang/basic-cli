module [get, all]

import PlatformTasks

## Returns the most preferred locale for the system or application, or `NotAvailable` if the locale could not be obtained.
##
## The returned [Str] is a BCP 47 language tag, like `en-US` or `fr-CA`.
get : Task Str [NotAvailable]
get =
    PlatformTasks.getLocale
    |> Task.mapErr \{} -> NotAvailable

## Returns the preferred locales for the system or application.
##
## The returned [Str] are BCP 47 language tags, like `en-US` or `fr-CA`.
all : Task (List Str) *
all =
    PlatformTasks.getLocales
    |> Task.mapErr \{} -> crash "unreachable Locale.all"
