import Host

## Convert a duration in seconds into whole milliseconds for the host.
##
## `to_u64_try` rejects negative, `NaN`, and too-large values alike, so a
## positive value here is one that overflowed the millisecond range.
millis_from_seconds : F64 -> U64
millis_from_seconds = |seconds|
	match F64.to_u64_try(seconds * 1000) {
		Ok(milliseconds) => milliseconds
		Err(OutOfRange) => if (seconds > 0) U64.highest else 0
	}

## Convert whole milliseconds into the nanoseconds the host sleeps for,
## saturating at [U64.highest] nanoseconds (about 584 years).
nanos_from_millis : U64 -> U64
nanos_from_millis = |milliseconds| milliseconds.times_saturated(1_000_000)

## Pause the current process for a requested duration.
Sleep :: [].{

	## Sleep for the specified number of milliseconds.
	millis! : U64 => Try({}, [Interrupted])
	millis! = |milliseconds| widen_interrupted(Host.sleep_nanos!(nanos_from_millis(milliseconds)))

	## Sleep for the specified number of seconds.
	##
	## The duration is truncated to whole milliseconds, so `Sleep.seconds!(1.5)`
	## sleeps for 1500 ms. Negative and `NaN` durations return immediately, and
	## durations too long for the host to count saturate at about 584 years.
	seconds! : F64 => Try({}, [Interrupted])
	seconds! = |seconds| widen_interrupted(Host.sleep_nanos!(nanos_from_millis(millis_from_seconds(seconds))))
}

expect millis_from_seconds(1) == 1000
expect millis_from_seconds(1.5) == 1500
expect millis_from_seconds(0.25) == 250
expect millis_from_seconds(0) == 0

# Sub-millisecond durations truncate toward zero rather than rounding up.
expect millis_from_seconds(0.0004) == 0

# Negative and NaN durations return immediately instead of crashing.
expect millis_from_seconds(-5) == 0
expect millis_from_seconds(F64.nan) == 0

# Durations beyond the host's millisecond counter saturate.
expect millis_from_seconds(F64.infinity) == U64.highest
expect millis_from_seconds(1.0e30) == U64.highest

# Milliseconds become nanoseconds for the host, saturating instead of wrapping.
expect nanos_from_millis(0) == 0
expect nanos_from_millis(250) == 250_000_000
expect nanos_from_millis(U64.highest) == U64.highest
expect nanos_from_millis(millis_from_seconds(1.5)) == 1_500_000_000
expect nanos_from_millis(millis_from_seconds(F64.infinity)) == U64.highest

# Rebuild the hosted closed row for application error composition.
widen_interrupted = |result| match result {
	Ok({}) => Ok({})
	Err(Interrupted) => Err(Interrupted)
}
