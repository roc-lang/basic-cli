app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    # Get current time
    now = Utc.now!({})

    # Convert to milliseconds since epoch
    millisSinceEpoch = Utc.to_millis_since_epoch(now)
    Stdout.line!("Current time in milliseconds since epoch: $(Num.to_str(millisSinceEpoch))")?

    # Basic sanity: should be non-negative
    err_on_false(millisSinceEpoch >= 0)?
    
    # Convert back from milliseconds since epoch
    timeFromMillis = Utc.from_millis_since_epoch(millisSinceEpoch)
    Stdout.line!("Time reconstructed from milliseconds: $(Utc.to_iso_8601(timeFromMillis))")?

    # Verify exact round-trip via ISO strings
    err_on_false(Utc.to_iso_8601(timeFromMillis) == Utc.to_iso_8601(now))?
    
    # Convert to nanoseconds since epoch
    nanosSinceEpoch = Utc.to_nanos_since_epoch(now)
    Stdout.line!("Current time in nanoseconds since epoch: $(Num.to_str(nanosSinceEpoch))")?

    # Sanity: also non-negative and ≥ millis * 1_000_000
    err_on_false(nanosSinceEpoch >= 0)?
    err_on_false(Num.to_frac(nanosSinceEpoch) >= Num.to_frac(millisSinceEpoch) * 1_000_000)?

    # Convert back from nanoseconds since epoch
    timeFromNanos = Utc.from_nanos_since_epoch(nanosSinceEpoch)
    Stdout.line!("Time reconstructed from nanoseconds: $(Utc.to_iso_8601(timeFromNanos))")?

    # Verify exact round-trip
    err_on_false(Utc.to_iso_8601(timeFromNanos) == Utc.to_iso_8601(now))?

    # Demonstrate time delta calculation
    Stdout.line!("\nTime delta demonstration:")?

    start = Utc.now!({})
    Stdout.line!("Starting time: $(Utc.to_iso_8601(start))")?

    # Sleep for 1.5 seconds
    Sleep.millis!(1500)

    finish = Utc.now!({})
    Stdout.line!("Ending time: $(Utc.to_iso_8601(finish))")?

    # start should be before finish
    err_on_false(Utc.to_millis_since_epoch(finish) > Utc.to_millis_since_epoch(start))?

    # Calculate delta in milliseconds
    deltaMillis = Utc.delta_as_millis(start, finish)
    Stdout.line!("Time elapsed: $(Num.to_str(deltaMillis)) milliseconds")?

    # For comparison, also show delta in nanoseconds
    deltaNanos = Utc.delta_as_nanos(start, finish)
    Stdout.line!("Time elapsed: $(Num.to_str(deltaNanos)) nanoseconds")?

    # Verify both deltas are positive and proportional
    err_on_false(deltaMillis > 0)?
    err_on_false(deltaNanos > 0)?
    err_on_false(Num.to_frac(deltaNanos) >= Num.to_frac(deltaMillis) * 1_000_000)?

    # Verify conversion: nanoseconds to milliseconds
    calculatedMillis = Num.to_frac(deltaNanos) / 1_000_000
    Stdout.line!("Nanoseconds converted to milliseconds: $(Num.to_str(calculatedMillis))")?

    # Check that deltaNanos / 1_000_000 is approximately equal to deltaMillis
    # Allow small rounding error by checking within 1 millisecond
    difference = Num.abs(calculatedMillis - Num.to_frac(deltaMillis))
    err_on_false(difference < 1)?
    Stdout.line!("Verified: deltaMillis and deltaNanos/1_000_000 match within tolerance")?

    Stdout.line!("\nTest completed successfully!")

err_on_false = |bool|
    if bool then
        Ok({})
    else
        Err(StrErr("A Test failed."))
