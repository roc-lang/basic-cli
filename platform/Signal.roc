import Host
import IOErr
import System

## Cooperatively handle signals delivered to the process.
##
## Register before acquiring resources that need application cleanup. A caught
## event makes blocking effects return `Interrupted`; acknowledge it with
## [poll!] before retrying an effect or running application cleanup. Catching
## does not clean up remote resources automatically.
##
## If `Interrupted` reaches `main!`, the platform restores terminal raw mode
## and exits with 128 plus the native signal number on Unix, or 130 on Windows.
## When several events are pending, Terminate takes precedence, followed by
## Interrupt, User1, User2, WindowResize.
Signal :: [].{
	Kind : [Interrupt, Terminate, User1, User2, WindowResize]
	Request : [Interrupt, Terminate(System.Unix), User1(System.Unix), User2(System.Unix), WindowResize(System.Unix)]

	## Add events to those caught for the lifetime of this process.
	## `Interrupt` catches Ctrl-C. `Terminate(unix)` catches Unix SIGTERM,
	## including systemd's default stop request. `User1(unix)` and `User2(unix)`
	## catch SIGUSR1 and SIGUSR2. `WindowResize(unix)` catches SIGWINCH.
	## Duplicate registrations and an empty list do nothing. Repeated events
	## coalesce and never force exit.
	catch! : List(Request) => Try({}, [SignalErr(IOErr)])
	catch! = |requests|
		match Host.signal_catch!(requests) {
			Ok({}) => Ok({})
			Err(SignalErr(err)) => Err(SignalErr(err))
		}

	## Acknowledge pending events, returning each kind at most once, in
	## the order Interrupt, Terminate, User1, User2, WindowResize. An interrupted
	## effect does not acknowledge events itself. Native forced termination
	## cannot be caught.
	poll! : () => List(Kind)
	poll! = || Host.signal_poll!()
}
