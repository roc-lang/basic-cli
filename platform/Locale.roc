Locale := [].{
    ## Returns the most preferred locale for the system or application.
    ##
    ## The returned [Str] is a BCP 47 language tag, like `en-US` or `fr-CA`.
    ##
    ## Returns `Err(NotAvailable)` if the locale cannot be determined.
    get! : () => Try(Str, [NotAvailable])

    ## Returns the preferred locales for the system or application.
    ##
    ## The returned [Str] are BCP 47 language tags, like `en-US` or `fr-CA`.
    all! : () => List(Str)
}
