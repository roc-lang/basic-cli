import Host

## Measure elapsed time using a clock that is unaffected by wall-clock changes.
## Values are nanoseconds since an unspecified, process-local origin. They are
## suitable for subtraction and must not be persisted or compared across runs.
Monotonic :: [].{

	## Read the process-local monotonic clock in nanoseconds.
	now! : () => U64
	now! = || Host.monotonic_now!()
}
