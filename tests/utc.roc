app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    # Test basic time operations
    test_time_conversion!({})?
    
    # Test time delta operations
    test_time_delta!({})?

    Stdout.line!("\nAll tests executed.")

test_time_conversion! : {} => Result {} _
test_time_conversion! = |{}|
    # Get current time
    now = Utc.now!({})

    millis_since_epoch = Utc.to_millis_since_epoch(now)
    Stdout.line!("Current time in milliseconds since epoch: ${Num.to_str(millis_since_epoch)}")?

    # Basic sanity: should be non-negative
    err_on_false(millis_since_epoch >= 0)?

    time_from_millis = Utc.from_millis_since_epoch(millis_since_epoch)
    Stdout.line!("Time reconstructed from milliseconds: ${Utc.to_iso_8601(time_from_millis)}")?

    # Verify exact round-trip via ISO strings
    err_on_false(Utc.to_iso_8601(time_from_millis) == Utc.to_iso_8601(now))?

    nanos_since_epoch = Utc.to_nanos_since_epoch(now)
    Stdout.line!("Current time in nanoseconds since epoch: ${Num.to_str(nanos_since_epoch)}")?

    # Sanity: also non-negative and ≥ millis * 1_000_000
    err_on_false(nanos_since_epoch >= 0)?
    err_on_false(Num.to_frac(nanos_since_epoch) >= Num.to_frac(millis_since_epoch) * 1_000_000)?

    time_from_nanos = Utc.from_nanos_since_epoch(nanos_since_epoch)
    Stdout.line!("Time reconstructed from nanoseconds: ${Utc.to_iso_8601(time_from_nanos)}")?

    # Verify exact round-trip
    err_on_false(Utc.to_iso_8601(time_from_nanos) == Utc.to_iso_8601(now))?

    Ok({})

test_time_delta! : {} => Result {} _
test_time_delta! = |{}|
    Stdout.line!("\nTime delta demonstration:")?

    start = Utc.now!({})
    Stdout.line!("Starting time: ${Utc.to_iso_8601(start)}")?

    Sleep.millis!(1500)

    finish = Utc.now!({})
    Stdout.line!("Ending time: ${Utc.to_iso_8601(finish)}")?

    # start should be before finish
    err_on_false(Utc.to_millis_since_epoch(finish) > Utc.to_millis_since_epoch(start))?

    delta_millis = Utc.delta_as_millis(start, finish)
    Stdout.line!("Time elapsed: ${Num.to_str(delta_millis)} milliseconds")?

    # For comparison, also show delta in nanoseconds
    delta_nanos = Utc.delta_as_nanos(start, finish)
    Stdout.line!("Time elapsed: ${Num.to_str(delta_nanos)} nanoseconds")?

    # Verify both deltas are positive and proportional
    err_on_false(delta_millis > 0)?
    err_on_false(delta_nanos > 0)?
    err_on_false(Num.to_frac(delta_nanos) >= Num.to_frac(delta_millis) * 1_000_000)?

    # Verify conversion: nanoseconds to milliseconds
    calculated_millis = Num.to_frac(delta_nanos) / 1_000_000
    Stdout.line!("Nanoseconds converted to milliseconds: ${Num.to_str(calculated_millis)}")?

    # Check that deltaNanos / 1_000_000 is approximately equal to deltaMillis
    difference = Num.abs(calculated_millis - Num.to_frac(delta_millis))
    err_on_false(difference < 1)?

    Stdout.line!("Verified: deltaMillis and deltaNanos/1_000_000 match within tolerance")?

    Ok({})

err_on_false = |bool|
    if bool then
        Ok({})
    else
        Err(StrErr("A Test failed."))