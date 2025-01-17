module [
    get!,
    all!,
]

import Host

## Returns the most preferred locale for the system or application, or `NotAvailable` if the locale could not be obtained.
##
## The returned [Str] is a BCP 47 language tag, like `en-US` or `fr-CA`.
get! : {} => Result Str [NotAvailable]
get! = |{}|
    Host.get_locale!({})
    |> Result.map_err(|{}| NotAvailable)

## Returns the preferred locales for the system or application.
##
## The returned [Str] are BCP 47 language tags, like `en-US` or `fr-CA`.
all! : {} => List Str
all! = Host.get_locales!
