Utc := [].{
    ## Get the current UTC time as nanoseconds since the Unix epoch (January 1, 1970).
    now! : {} => U128

    ## Convert nanoseconds since epoch to milliseconds since epoch.
    to_millis_since_epoch : U128 -> U128
    to_millis_since_epoch = |nanos| nanos // 1_000_000

    ## Convert milliseconds since epoch to nanoseconds since epoch.
    from_millis_since_epoch : U128 -> U128
    from_millis_since_epoch = |millis| millis * 1_000_000

    ## Calculate the difference between two timestamps in nanoseconds.
    delta_as_nanos : U128, U128 -> U128
    delta_as_nanos = |a, b| if a > b { a - b } else { b - a }

    ## Calculate the difference between two timestamps in milliseconds.
    delta_as_millis : U128, U128 -> U128
    delta_as_millis = |a, b| {
        nanos = if a > b { a - b } else { b - a }
        nanos // 1_000_000
    }
}
