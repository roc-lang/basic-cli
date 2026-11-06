import Duration
import Host
import InternalDateTime

nanos_per_milli : I128
nanos_per_milli = 1_000_000

## A point in calendar time: signed nanoseconds since the Unix epoch,
## 1970-01-01T00:00:00Z. Instants before 1970 are negative.
##
## `Utc` values support `==` and the ordering operators and sort with
## `List.sort`. The time between two of them is a [Duration], from
## [Utc.since]. To measure how long something took, prefer [Monotonic], which
## is unaffected by changes to the wall clock.
##
## This platform supplies clock effects and signed epoch conversions. Use a
## package such as [roc-time](https://github.com/lukewilliamboswell/roc-time)
## for timestamp parsing, calendar operations and richer formatting. Its
## [supported profiles](https://lukewilliamboswell.github.io/roc-time/profiles.html#profiles)
## describe the accepted formats and precision; roc-time 0.3 uses microseconds,
## while `Utc` stores nanoseconds. Convert units explicitly at that boundary.
## [Utc.to_iso_8601] is a convenience display at whole-second precision.
## Use [Utc.to_nanos_since_epoch] and [Utc.from_nanos_since_epoch] for exact
## timestamp storage. Parsing and richer formatting are outside this module's
## scope rather than planned additions to the native host.
##
## Every result is clamped to what its type holds, so nothing here crashes on
## overflow: a `Utc` to the [I128] range, a [Duration] to zero and its maximum.
Utc :: { nanos : I128 }.{

	## Read the current time from the system clock.
	##
	## A clock set before 1970 gives a negative instant rather than an error or
	## the epoch.
	now! : () => Utc
	now! = ||
		match Host.utc_now!() {
			Ok(nanos) => Utc.{ nanos }
			# Only a clock more than 10^21 years from 1970 is out of range.
			Err(ClockOutOfRange) => Utc.{ nanos: I128.highest }
		}

	## The instant a number of nanoseconds after the Unix epoch, or before it
	## when negative.
	from_nanos_since_epoch : I128 -> Utc
	from_nanos_since_epoch = |nanos| Utc.{ nanos }

	## Nanoseconds from the Unix epoch to this instant, negative before 1970.
	to_nanos_since_epoch : Utc -> I128
	to_nanos_since_epoch = |utc| utc.nanos

	## The instant a number of milliseconds after the Unix epoch, or before it
	## when negative, clamped to the representable range.
	from_millis_since_epoch : I128 -> Utc
	from_millis_since_epoch = |millis| Utc.{ nanos: millis.times_saturated(nanos_per_milli) }

	## Whole milliseconds from the Unix epoch to this instant, negative before
	## 1970. A partial millisecond is floored, so one nanosecond before the epoch
	## is millisecond -1.
	to_millis_since_epoch : Utc -> I128
	to_millis_since_epoch = |utc| InternalDateTime.floor_div(utc.nanos, nanos_per_milli)

	## The time from an earlier instant to this one: `later.since(earlier)`.
	##
	## The arguments are directional. When `earlier` is in fact the later
	## instant the result is [Duration.zero], and a span too long for a
	## [Duration] is clamped to the longest one.
	##
	## ```roc
	## stale = Utc.now!().since(path.time_modified!()?) > Duration.minutes(5)
	## ```
	since : Utc, Utc -> Duration
	since = |later, earlier| {
		span = later.nanos.minus_saturated(earlier.nanos)

		match I128.to_u64_try(span) {
			Ok(nanos) => Duration.nanos(nanos)
			Err(OutOfRange) => if (span > 0) Duration.nanos(U64.highest) else Duration.zero
		}
	}

	## Format this instant as an ISO 8601 UTC string with second precision,
	## flooring any partial second: `2026-10-13T09:30:00Z`.
	##
	## The stored nanoseconds are unchanged, but this string omits them; use
	## [to_nanos_since_epoch] when the full precision must round-trip. There
	## is no corresponding parser here; use a time package for text interchange.
	##
	## Instants before 1970 are formatted too, in the proleptic Gregorian
	## calendar. Years outside 0000 to 9999 use the expanded form with a sign,
	## such as `-0001-12-31T23:59:59Z`.
	to_iso_8601 : Utc -> Str
	to_iso_8601 = |utc| {
		millis = to_millis_since_epoch(utc)
		datetime = InternalDateTime.epoch_millis_to_datetime(millis)

		InternalDateTime.to_iso_8601(datetime)
	}

	## How `Str.inspect` renders an instant: `Utc(2026-10-13T09:30:00Z)`.
	to_inspect : Utc -> Str
	to_inspect = |utc| "Utc(${to_iso_8601(utc)})"

	## Compare two instants for equality (`==` and `!=`).
	is_eq : _

	## Whether the first instant is earlier than the second (`<`).
	is_lt : Utc, Utc -> Bool
	is_lt = |a, b| a.nanos < b.nanos

	## Whether the first instant is no later than the second (`<=`).
	is_lte : Utc, Utc -> Bool
	is_lte = |a, b| a.nanos <= b.nanos

	## Whether the first instant is later than the second (`>`).
	is_gt : Utc, Utc -> Bool
	is_gt = |a, b| a.nanos > b.nanos

	## Whether the first instant is no earlier than the second (`>=`).
	is_gte : Utc, Utc -> Bool
	is_gte = |a, b| a.nanos >= b.nanos

	## Order two instants, earliest first. This is what `List.sort` and
	## `List.sort_by` use.
	order_relative_to : Utc, Utc -> [Before, Same, After]
	order_relative_to = |a, b| a.nanos.order_relative_to(b.nanos)
}

# 2026-10-13T09:30:00Z.
sample : Utc
sample = Utc.from_millis_since_epoch(1_791_883_800_000)

epoch : Utc
epoch = Utc.from_nanos_since_epoch(0)

# Epoch conversions round-trip, on both sides of the epoch.
expect Utc.from_nanos_since_epoch(42).to_nanos_since_epoch() == 42
expect Utc.from_nanos_since_epoch(-42).to_nanos_since_epoch() == -42
expect Utc.from_millis_since_epoch(1_500).to_nanos_since_epoch() == 1_500_000_000
expect Utc.from_millis_since_epoch(-1_500).to_nanos_since_epoch() == -1_500_000_000
expect Utc.from_millis_since_epoch(-1_500).to_millis_since_epoch() == -1_500
expect sample.to_millis_since_epoch() == 1_791_883_800_000

# `to_millis_since_epoch` floors rather than truncating toward zero.
expect Utc.from_nanos_since_epoch(1_999_999).to_millis_since_epoch() == 1
expect Utc.from_nanos_since_epoch(999_999).to_millis_since_epoch() == 0
expect Utc.from_nanos_since_epoch(-1).to_millis_since_epoch() == -1
expect Utc.from_nanos_since_epoch(-1_000_000).to_millis_since_epoch() == -1
expect Utc.from_nanos_since_epoch(-1_000_001).to_millis_since_epoch() == -2

# Results clamp at both ends of the I128 range.
expect Utc.from_millis_since_epoch(I128.highest).to_nanos_since_epoch() == I128.highest
expect Utc.from_millis_since_epoch(I128.lowest).to_nanos_since_epoch() == I128.lowest
expect Utc.from_nanos_since_epoch(I128.lowest).to_millis_since_epoch() == -170_141_183_460_469_231_731_687_303_715_885
expect Utc.from_nanos_since_epoch(I128.highest).to_millis_since_epoch() == 170_141_183_460_469_231_731_687_303_715_884

# `since` is directional and clamps to what a Duration holds.
expect Utc.from_millis_since_epoch(2_500).since(Utc.from_millis_since_epoch(1_000)) == Duration.millis(1_500)
expect sample.since(sample) == Duration.zero
expect Utc.from_millis_since_epoch(1_000).since(Utc.from_millis_since_epoch(2_500)) == Duration.zero
expect Utc.from_nanos_since_epoch(I128.lowest).since(Utc.from_nanos_since_epoch(I128.highest)) == Duration.zero
expect Utc.from_nanos_since_epoch(I128.highest).since(Utc.from_nanos_since_epoch(I128.lowest)) == Duration.nanos(U64.highest)
expect Utc.from_nanos_since_epoch(I128.highest).since(epoch) == Duration.nanos(U64.highest)
expect epoch.since(Utc.from_nanos_since_epoch(I128.lowest)) == Duration.nanos(U64.highest)
expect Utc.from_nanos_since_epoch(18_446_744_073_709_551_615).since(epoch) == Duration.nanos(U64.highest)
expect Utc.from_nanos_since_epoch(18_446_744_073_709_551_614).since(epoch).to_nanos() == 18_446_744_073_709_551_614

# `since` across the epoch.
expect Utc.from_millis_since_epoch(1_000).since(Utc.from_millis_since_epoch(-1_000)) == Duration.seconds(2)
expect Utc.from_millis_since_epoch(-1_000).since(Utc.from_millis_since_epoch(-3_000)) == Duration.seconds(2)
expect Utc.from_millis_since_epoch(-1_000).since(Utc.from_millis_since_epoch(1_000)) == Duration.zero

# A file five minutes and one second old is stale; one modified in the future is not.
expect sample.since(Utc.from_millis_since_epoch(1_791_883_499_000)) > Duration.minutes(5)
expect !(sample.since(Utc.from_millis_since_epoch(1_791_883_801_000)) > Duration.minutes(5))

# `to_iso_8601`, including before 1970.
expect sample.to_iso_8601() == "2026-10-13T09:30:00Z"
expect epoch.to_iso_8601() == "1970-01-01T00:00:00Z"
expect Utc.from_nanos_since_epoch(999_999_999).to_iso_8601() == "1970-01-01T00:00:00Z"
expect Utc.from_nanos_since_epoch(-1).to_iso_8601() == "1969-12-31T23:59:59Z"
expect Utc.from_millis_since_epoch(-86_400_000).to_iso_8601() == "1969-12-31T00:00:00Z"
expect Utc.from_millis_since_epoch(-2_208_988_800_000).to_iso_8601() == "1900-01-01T00:00:00Z"
expect Utc.from_millis_since_epoch(-62_167_219_201_000).to_iso_8601() == "-0001-12-31T23:59:59Z"
expect Utc.from_millis_since_epoch(253_402_300_800_000).to_iso_8601() == "+10000-01-01T00:00:00Z"

# `to_inspect` is what `Str.inspect` shows, alone and inside other values.
expect sample.to_inspect() == "Utc(2026-10-13T09:30:00Z)"
expect Str.inspect(sample) == "Utc(2026-10-13T09:30:00Z)"
expect Str.inspect(Utc.from_nanos_since_epoch(-1)) == "Utc(1969-12-31T23:59:59Z)"

expect {
	err : [Expired(Utc)]
	err = Expired(sample)

	Str.inspect(err) == "Expired(Utc(2026-10-13T09:30:00Z))"
}

expect Str.inspect({ modified: sample }) == "{ modified: Utc(2026-10-13T09:30:00Z) }"

# `==`, `!=` and the ordering operators.
expect Utc.from_millis_since_epoch(1) == Utc.from_nanos_since_epoch(1_000_000)
expect sample != epoch
expect sample.is_eq(sample)
expect epoch < sample
expect !(sample < sample)
expect !(sample < epoch)
expect epoch <= sample
expect sample <= sample
expect !(sample <= epoch)
expect sample > epoch
expect !(sample > sample)
expect !(epoch > sample)
expect sample >= epoch
expect sample >= sample
expect !(epoch >= sample)
expect Utc.from_nanos_since_epoch(-1) < epoch
expect Utc.from_nanos_since_epoch(I128.lowest) < Utc.from_nanos_since_epoch(I128.highest)

# `order_relative_to`, `List.sort` and `List.sort_by`.
expect epoch.order_relative_to(sample) == Before
expect sample.order_relative_to(sample) == Same
expect sample.order_relative_to(epoch) == After

expect {
	before_epoch = Utc.from_millis_since_epoch(-5)
	sorted = List.sort([sample, before_epoch, epoch])

	sorted == [before_epoch, epoch, sample]
}

expect {
	files = [
		{ name: "new", modified: sample },
		{ name: "ancient", modified: Utc.from_millis_since_epoch(-2_208_988_800_000) },
		{ name: "old", modified: epoch },
	]
	names = List.sort_by(files, |file| file.modified).map(|file| file.name)

	names == ["ancient", "old", "new"]
}
