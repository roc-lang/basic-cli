import Host

## Convert a duration in seconds into whole milliseconds for the host.
##
## `to_u64_try` rejects negative, `NaN`, and too-large values alike, so a
## positive value here is one that overflowed the millisecond range.
millis_from_seconds : F64 -> U64
millis_from_seconds = |seconds|
	match F64.to_u64_try(seconds * 1000) {
		Ok(milliseconds) => milliseconds
		Err(OutOfRange) => if seconds > 0 U64.highest else 0
	}

## Pause the current process for a requested duration.
Sleep :: [].{

	## Sleep for the specified number of milliseconds.
	millis! : U64 => {}
	millis! = |milliseconds| Host.sleep_millis!(milliseconds)

	## Sleep for the specified number of seconds.
	##
	## The duration is truncated to whole milliseconds, so `Sleep.seconds!(1.5)`
	## sleeps for 1500 ms. Negative and `NaN` durations return immediately, and
	## durations past [U64.highest] milliseconds saturate there.
	seconds! : F64 => {}
	seconds! = |seconds| Host.sleep_millis!(millis_from_seconds(seconds))
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
