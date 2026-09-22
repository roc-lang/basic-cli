import IOErr exposing [IOErr]
import Host

## Read lines, chunks, or all remaining bytes from standard input.
Stdin :: [].{

	## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
	##
	## > This task will block the program from continuing until `stdin` receives a newline character
	## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
	## program having gotten stuck. It's often helpful to print a prompt first, so
	## the user knows it's necessary to enter something before the program will continue.
	line! : () => Try(Str, [EndOfFile, StdinErr(IOErr)])
	line! = || widen_stdin_eof_err(Host.stdin_line!())

	## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
	## This function can read no more than 16,384 bytes at a time. Use [read_to_end!] if you need more.
	##
	## > This is typically used in combination with [Tty.enable_raw_mode!],
	## which disables default terminal behaviour and allows reading input
	## without buffering until Enter key is pressed.
	bytes! : () => Try(List(U8), [EndOfFile, StdinErr(IOErr)])
	bytes! = || widen_stdin_eof_err(Host.stdin_bytes!())

	## Read all bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin))
	## until [EOF](https://en.wikipedia.org/wiki/End-of-file) in this source.
	read_to_end! : () => Try(List(U8), [StdinErr(IOErr)])
	read_to_end! = || widen_stdin_err(Host.stdin_read_to_end!())
}

## Rebuild the error union so it is open at call sites.
## Passing a hosted function's result straight through leaves the union closed,
## which stops `?` from combining it with other error types.
widen_stdin_eof_err : Try(v, [EndOfFile, StdinErr(IOErr)]) -> Try(v, [EndOfFile, StdinErr(IOErr)])
widen_stdin_eof_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(EndOfFile) => Err(EndOfFile)
		Err(StdinErr(err)) => Err(StdinErr(err))
	}

widen_stdin_err : Try(v, [StdinErr(IOErr)]) -> Try(v, [StdinErr(IOErr)])
widen_stdin_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(StdinErr(err)) => Err(StdinErr(err))
	}
