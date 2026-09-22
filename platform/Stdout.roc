import IOErr exposing [IOErr]
import Host

## Write text or raw bytes to the process's standard output stream.
Stdout :: [].{

	## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
	## followed by a newline.
	##
	## > To write to `stdout` without the newline, see [Stdout.write!].
	line! : Str => Try({}, [StdoutErr(IOErr)])
	line! = |message| widen_stdout_err(Host.stdout_line!(message))

	## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
	##
	## Note that many terminals will not actually display strings that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	##
	## > To write to `stdout` with a newline at the end, see [Stdout.line!].
	write! : Str => Try({}, [StdoutErr(IOErr)])
	write! = |message| widen_stdout_err(Host.stdout_write!(message))

	## Write the given bytes to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
	##
	## Note that many terminals will not actually display content that is written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr)])
	write_bytes! = |bytes| widen_stdout_err(Host.stdout_write_bytes!(bytes))
}

## Rebuild the error union so it is open at call sites.
## Passing a hosted function's result straight through leaves the union closed,
## which stops `?` from combining it with other error types.
widen_stdout_err : Try(v, [StdoutErr(IOErr)]) -> Try(v, [StdoutErr(IOErr)])
widen_stdout_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(StdoutErr(err)) => Err(StdoutErr(err))
	}
