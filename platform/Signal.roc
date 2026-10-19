import Host
import IOErr
import System

## Cooperatively handle requests to stop the process.
##
## Register before acquiring resources that need application cleanup. A caught
## event makes blocking effects return `Interrupted`; acknowledge it with
## [poll!] before running application cleanup. Catching does not clean up
## remote resources automatically.
Signal :: [].{
	Kind : [Interrupt, Terminate]
	Request : [Interrupt, Terminate(System.Unix)]

	## Add events to those caught for the lifetime of this process.
	## `Interrupt` catches Ctrl-C. `Terminate(unix)` catches Unix SIGTERM,
	## including systemd's default stop request. Duplicate registrations and an
	## empty list do nothing. Repeated events coalesce and never force exit.
	catch! : List(Request) => Try({}, [SignalErr(IOErr)])
	catch! = |requests|
		match Host.signal_catch!(requests) {
			Ok({}) => Ok({})
			Err(SignalErr(err)) => Err(SignalErr(err))
		}

	## Acknowledge pending events, returning each kind at most once, in
	## Interrupt/Terminate order. An interrupted effect does not acknowledge
	## events itself. Native forced termination cannot be caught.
	poll! : () => List(Kind)
	poll! = || Host.signal_poll!()
}
