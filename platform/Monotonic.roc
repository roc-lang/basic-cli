import Duration
import Host

## A reading of a clock that only moves forward and is unaffected by wall-clock
## changes, for measuring elapsed time.
##
## A reading has no meaning on its own: it counts from an unspecified,
## process-local origin, so there is no integer in or out. Only the difference
## between two readings is useful, as a [Duration]. Readings must not be
## persisted or compared across runs; use [Utc] for a point in calendar time.
##
## ```roc
## start = Monotonic.now!()
## work!()?
## Stdout.line!("Completed in ${start.elapsed!().to_str()}")?
## ```
Monotonic :: { nanos : U64 }.{

	## Read the monotonic clock.
	now! : () => Monotonic
	now! = || Monotonic.{ nanos: Host.monotonic_now!() }

	## The time from an earlier reading to this one: `later.since(earlier)`.
	##
	## Gives [Duration.zero] when `earlier` is in fact the later reading.
	since : Monotonic, Monotonic -> Duration
	since = |later, earlier| Duration.nanos(later.nanos.minus_saturated(earlier.nanos))

	## The time since this reading was taken: `Monotonic.now!().since(start)`.
	##
	## A deadline loop is `start.elapsed!() < Duration.seconds(10)`.
	elapsed! : Monotonic => Duration
	elapsed! = |start| since(now!(), start)
}

expect Monotonic.{ nanos: 1_500_000_000 }.since(Monotonic.{ nanos: 0 }) == Duration.millis(1500)
expect Monotonic.{ nanos: 7 }.since(Monotonic.{ nanos: 7 }) == Duration.zero
expect Monotonic.{ nanos: U64.highest }.since(Monotonic.{ nanos: 0 }) == Duration.nanos(U64.highest)

# The arguments are directional: an earlier reading is not "since" a later one.
expect Monotonic.{ nanos: 5 }.since(Monotonic.{ nanos: 9 }) == Duration.zero
expect Monotonic.{ nanos: 0 }.since(Monotonic.{ nanos: U64.highest }) == Duration.zero
