import IOErr
import Host

## Provides functionality to change the behaviour of the terminal.
## This is useful for running an app like vim or a game in the terminal.
##
## The platform remembers whether it switched the terminal into raw mode, and
## restores the terminal when the app finishes: when `main!` returns `Ok` or
## `Err`, when the app exits with a specific exit code, and when it stops on a
## `crash`. The terminal is always put back into the mode it was in when
## [Tty.enable_raw_mode!] was called.
##
## While raw mode is enabled, the platform also restores the terminal when the
## process is asked to terminate from the outside:
## - On Unix, by `SIGHUP`, `SIGINT`, `SIGQUIT`, or `SIGTERM`. The process still
##   terminates from that signal. A signal that was already being ignored when
##   raw mode was enabled stays ignored.
## - On Windows, by Ctrl+C, Ctrl+Break, or the console window closing.
##
## The platform cannot restore the terminal when the process is stopped without
## being given the chance to run any code. This includes `SIGKILL` and `SIGSTOP`
## on Unix, and `TerminateProcess` (for example "End task") on Windows. If that
## happens, run `reset` or `stty sane` to recover the terminal.
##
## Note that pressing Ctrl+C does not interrupt the app while raw mode is
## enabled; the key press is delivered to the app as input.
Tty :: [].{

	## Enable terminal [raw mode](https://en.wikipedia.org/wiki/Terminal_mode) to disable some default terminal behaviour.
	##
	## This leads to the following changes:
	## - Input will not be echoed to the terminal screen.
	## - Input will be sent straight to the program instead of being buffered (= collected) until the Enter key is pressed.
	## - Special keys like Backspace and CTRL+C will not be processed by the terminal driver but will be passed to the program.
	##
	## Calling this when raw mode is already enabled does nothing and returns `Ok`.
	## Calls are not counted, so a single [Tty.disable_raw_mode!] undoes any number
	## of calls to this function.
	##
	## Returns a `TtyErr` when the process has no terminal to configure (for
	## example when it runs detached from a terminal), or when the operating
	## system rejects the change. The terminal mode is left untouched in that case.
	enable_raw_mode! : () => Try({}, [TtyErr(IOErr)])
	enable_raw_mode! = ||
		Host.tty_enable_raw_mode!()
			.map_err(|err| TtyErr(err))

	## Revert the terminal to the mode it was in before [Tty.enable_raw_mode!] was called.
	##
	## Calling this when raw mode is not enabled does nothing and returns `Ok`;
	## the platform only ever reverts a mode that it enabled itself.
	##
	## Returns a `TtyErr` when the operating system rejects the change. Raw mode
	## is still considered enabled in that case, so this can be called again and
	## the platform will retry when the app finishes.
	disable_raw_mode! : () => Try({}, [TtyErr(IOErr)])
	disable_raw_mode! = ||
		Host.tty_disable_raw_mode!()
			.map_err(|err| TtyErr(err))
}
