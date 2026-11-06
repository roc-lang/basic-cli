import Host

nanos_per_milli : U64
nanos_per_milli = 1_000_000

nanos_per_second : U64
nanos_per_second = 1_000_000_000

nanos_per_minute : U64
nanos_per_minute = 60_000_000_000

## Render the thousandths of a second as a decimal fraction without trailing
## zeros: `500` is ".5", `50` is ".05", `5` is ".005" and `0` is "".
fraction_str : U64 -> Str
fraction_str = |thousandths|
	if thousandths == 0 {
		""
	} else if thousandths % 100 == 0 {
		".${(thousandths // 100).to_str()}"
	} else if thousandths % 10 == 0 {
		hundredths = thousandths // 10
		if (hundredths < 10) ".0${hundredths.to_str()}" else ".${hundredths.to_str()}"
	} else if thousandths < 10 {
		".00${thousandths.to_str()}"
	} else if thousandths < 100 {
		".0${thousandths.to_str()}"
	} else {
		".${thousandths.to_str()}"
	}

## A non-negative length of time with nanosecond resolution.
##
## Build one from a unit, `Duration.seconds(5)`, and pass it wherever a timeout
## or a wait is expected. Durations support `+`, `-`, `==` and the ordering
## operators, and sort with `List.sort`.
##
## Every result is clamped to what a `Duration` can hold: zero at the low end
## and [U64.highest] nanoseconds (about 584 years) at the high end. Nothing here
## crashes on overflow, so `a - b` is [Duration.zero] when `b` is longer than `a`.
Duration :: { nanos : U64 }.{

	## The empty duration. A timeout of `Duration.zero` expires immediately.
	zero : Duration
	zero = Duration.{ nanos: 0 }

	## A duration of the given number of nanoseconds.
	nanos : U64 -> Duration
	nanos = |count| Duration.{ nanos: count }

	## A duration of the given number of milliseconds, clamped to the longest
	## representable duration.
	millis : U64 -> Duration
	millis = |count| Duration.{ nanos: count.times_saturated(nanos_per_milli) }

	## A duration of the given number of seconds, clamped to the longest
	## representable duration.
	seconds : U64 -> Duration
	seconds = |count| Duration.{ nanos: count.times_saturated(nanos_per_second) }

	## A duration of the given number of minutes, clamped to the longest
	## representable duration.
	minutes : U64 -> Duration
	minutes = |count| Duration.{ nanos: count.times_saturated(nanos_per_minute) }

	## The length of this duration in nanoseconds.
	to_nanos : Duration -> U64
	to_nanos = |duration| duration.nanos

	## The length of this duration in whole milliseconds, truncating any
	## remainder: 1999 microseconds is 1 millisecond.
	to_millis : Duration -> U64
	to_millis = |duration| duration.nanos // nanos_per_milli

	## The length of this duration in whole seconds, truncating any remainder.
	to_seconds : Duration -> U64
	to_seconds = |duration| duration.nanos // nanos_per_second

	## Format this duration for people, in the largest unit that fits:
	## nanoseconds below a millisecond (`"999ns"`), whole milliseconds below a
	## second (`"250ms"`), then seconds with up to three decimals (`"1.5s"`,
	## `"10800s"`). Digits past the unit's precision are truncated, not rounded.
	to_str : Duration -> Str
	to_str = |duration| {
		total = duration.nanos

		if total < nanos_per_milli {
			"${total.to_str()}ns"
		} else if total < nanos_per_second {
			"${(total // nanos_per_milli).to_str()}ms"
		} else {
			whole = total // nanos_per_second
			thousandths = (total % nanos_per_second) // nanos_per_milli

			"${whole.to_str()}${fraction_str(thousandths)}s"
		}
	}

	## How `Str.inspect` renders a duration: `Duration(1.5s)`.
	to_inspect : Duration -> Str
	to_inspect = |duration| "Duration(${to_str(duration)})"

	## Pause the current process for this duration.
	##
	## Use this for a wait that was computed, such as
	## `interval.minus(start.elapsed!()).sleep!()`; `Sleep.millis!(250)` reads
	## better for a literal one. `Duration.zero` returns immediately.
	sleep! : Duration => Try({}, [Interrupted])
	sleep! = |duration| match Host.sleep_nanos!(duration.nanos) {
		Ok({}) => Ok({})
		Err(Interrupted) => Err(Interrupted)
	}

	## Add two durations (`a + b`), clamped to the longest representable duration.
	plus : Duration, Duration -> Duration
	plus = |a, b| Duration.{ nanos: a.nanos.plus_saturated(b.nanos) }

	## Subtract one duration from another (`a - b`), giving [Duration.zero] when
	## `b` is the longer one.
	##
	## This gives several timed operations one budget:
	## `budget - start.elapsed!()` is the time left, and is zero once the budget
	## is spent.
	minus : Duration, Duration -> Duration
	minus = |a, b| Duration.{ nanos: a.nanos.minus_saturated(b.nanos) }

	## Compare two durations for equality (`==` and `!=`).
	is_eq : _

	## Whether the first duration is shorter than the second (`<`).
	is_lt : Duration, Duration -> Bool
	is_lt = |a, b| a.nanos < b.nanos

	## Whether the first duration is no longer than the second (`<=`).
	is_lte : Duration, Duration -> Bool
	is_lte = |a, b| a.nanos <= b.nanos

	## Whether the first duration is longer than the second (`>`).
	is_gt : Duration, Duration -> Bool
	is_gt = |a, b| a.nanos > b.nanos

	## Whether the first duration is at least as long as the second (`>=`).
	is_gte : Duration, Duration -> Bool
	is_gte = |a, b| a.nanos >= b.nanos

	## Order two durations, shortest first. This is what `List.sort` and
	## `List.sort_by` use.
	order_relative_to : Duration, Duration -> [Before, Same, After]
	order_relative_to = |a, b| a.nanos.order_relative_to(b.nanos)
}

# Constructors and conversions.
expect Duration.zero.to_nanos() == 0
expect Duration.zero == Duration.nanos(0)
expect Duration.nanos(42).to_nanos() == 42
expect Duration.millis(250).to_nanos() == 250_000_000
expect Duration.seconds(3).to_nanos() == 3_000_000_000
expect Duration.minutes(2).to_nanos() == 120_000_000_000
expect Duration.minutes(1) == Duration.seconds(60)
expect Duration.seconds(1) == Duration.millis(1000)
expect Duration.millis(1) == Duration.nanos(1_000_000)

# `to_millis` and `to_seconds` truncate.
expect Duration.nanos(1_999_999).to_millis() == 1
expect Duration.nanos(999_999).to_millis() == 0
expect Duration.millis(1999).to_seconds() == 1
expect Duration.millis(999).to_seconds() == 0
expect Duration.minutes(3).to_seconds() == 180
expect Duration.seconds(3).to_millis() == 3000

# Constructors clamp at the longest representable duration.
expect Duration.millis(U64.highest).to_nanos() == U64.highest
expect Duration.seconds(U64.highest).to_nanos() == U64.highest
expect Duration.minutes(U64.highest).to_nanos() == U64.highest
expect Duration.seconds(18_446_744_074).to_nanos() == U64.highest
expect Duration.seconds(18_446_744_073).to_nanos() == 18_446_744_073_000_000_000
expect Duration.nanos(U64.highest).to_nanos() == U64.highest

# `+` and `plus`, clamping at the top.
expect Duration.seconds(1) + Duration.millis(500) == Duration.millis(1500)
expect Duration.seconds(1).plus(Duration.millis(500)) == Duration.millis(1500)
expect Duration.zero + Duration.zero == Duration.zero
expect Duration.nanos(U64.highest) + Duration.nanos(1) == Duration.nanos(U64.highest)
expect Duration.nanos(U64.highest).plus(Duration.nanos(U64.highest)).to_nanos() == U64.highest

# `-` and `minus`, clamping at zero.
expect Duration.seconds(2) - Duration.millis(500) == Duration.millis(1500)
expect Duration.seconds(2).minus(Duration.millis(500)) == Duration.millis(1500)
expect Duration.seconds(1) - Duration.seconds(1) == Duration.zero
expect Duration.seconds(1) - Duration.seconds(2) == Duration.zero
expect Duration.millis(1).minus(Duration.minutes(1)) == Duration.zero
expect Duration.zero - Duration.nanos(U64.highest) == Duration.zero
expect Duration.zero.minus(Duration.nanos(1)).to_nanos() == 0

# A spent budget leaves nothing, rather than a negative or a crash.
expect {
	budget = Duration.seconds(5)
	elapsed = Duration.seconds(7)
	remaining = budget - elapsed

	remaining == Duration.zero and (budget - Duration.seconds(2)) == Duration.seconds(3)
}

# `==` and `!=`.
expect Duration.millis(1500) == Duration.nanos(1_500_000_000)
expect Duration.millis(1500) != Duration.millis(1501)
expect Duration.seconds(1).is_eq(Duration.millis(1000))
expect !(Duration.seconds(1) != Duration.seconds(1))

# Ordering operators.
expect Duration.millis(999) < Duration.seconds(1)
expect !(Duration.seconds(1) < Duration.seconds(1))
expect !(Duration.seconds(2) < Duration.seconds(1))
expect Duration.millis(999) <= Duration.seconds(1)
expect Duration.seconds(1) <= Duration.seconds(1)
expect !(Duration.seconds(2) <= Duration.seconds(1))
expect Duration.minutes(1) > Duration.seconds(59)
expect !(Duration.seconds(1) > Duration.seconds(1))
expect !(Duration.seconds(1) > Duration.seconds(2))
expect Duration.minutes(1) >= Duration.seconds(59)
expect Duration.minutes(1) >= Duration.seconds(60)
expect !(Duration.seconds(1) >= Duration.seconds(2))
expect Duration.zero < Duration.nanos(1)
expect Duration.nanos(U64.highest) > Duration.minutes(1)

# `order_relative_to`, `List.sort` and `List.sort_by`.
expect Duration.seconds(1).order_relative_to(Duration.seconds(2)) == Before
expect Duration.seconds(2).order_relative_to(Duration.seconds(2)) == Same
expect Duration.seconds(3).order_relative_to(Duration.seconds(2)) == After

expect {
	sorted = List.sort([Duration.seconds(2), Duration.millis(5), Duration.minutes(1), Duration.zero])

	sorted == [Duration.zero, Duration.millis(5), Duration.seconds(2), Duration.minutes(1)]
}

expect {
	jobs = [
		{ name: "slow", took: Duration.seconds(9) },
		{ name: "fast", took: Duration.millis(3) },
		{ name: "medium", took: Duration.millis(700) },
	]
	names = List.sort_by(jobs, |job| job.took).map(|job| job.name)

	names == ["fast", "medium", "slow"]
}

# `to_str`: nanoseconds below a millisecond.
expect Duration.zero.to_str() == "0ns"
expect Duration.nanos(1).to_str() == "1ns"
expect Duration.nanos(999).to_str() == "999ns"
expect Duration.nanos(999_999).to_str() == "999999ns"

# `to_str`: whole milliseconds below a second.
expect Duration.millis(1).to_str() == "1ms"
expect Duration.millis(250).to_str() == "250ms"
expect Duration.nanos(1_999_999).to_str() == "1ms"
expect Duration.nanos(999_999_999).to_str() == "999ms"

# `to_str`: seconds with up to three decimals, truncated.
expect Duration.seconds(1).to_str() == "1s"
expect Duration.millis(1500).to_str() == "1.5s"
expect Duration.millis(1050).to_str() == "1.05s"
expect Duration.millis(1005).to_str() == "1.005s"
expect Duration.millis(1250).to_str() == "1.25s"
expect Duration.millis(1234).to_str() == "1.234s"
expect Duration.millis(1010).to_str() == "1.01s"
expect Duration.millis(2100).to_str() == "2.1s"
expect Duration.nanos(1_234_999_999).to_str() == "1.234s"
expect Duration.nanos(1_000_999_999).to_str() == "1s"
expect Duration.minutes(180).to_str() == "10800s"
expect Duration.minutes(1).to_str() == "60s"
expect Duration.nanos(U64.highest).to_str() == "18446744073.709s"

# `to_inspect` is what `Str.inspect` shows, alone and inside other values.
expect Duration.millis(1500).to_inspect() == "Duration(1.5s)"
expect Str.inspect(Duration.millis(1500)) == "Duration(1.5s)"
expect Str.inspect(Duration.zero) == "Duration(0ns)"

expect {
	err : [TooSlow(Duration)]
	err = TooSlow(Duration.millis(1500))

	Str.inspect(err) == "TooSlow(Duration(1.5s))"
}

expect Str.inspect({ timeout: Duration.millis(250) }) == "{ timeout: Duration(250ms) }"
