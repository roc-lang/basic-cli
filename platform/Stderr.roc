import IOErr exposing [IOErr]
import Host

## Write text or raw bytes to the process's standard error stream.
Stderr :: [].{

	## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
	## followed by a newline.
	##
	## > To write to `stderr` without the newline, see [Stderr.write!].
	line! : Str => Try({}, [StderrErr(IOErr)])
	line! = |message| widen_stderr_err(Host.stderr_line!(message))

	## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
	##
	## Most terminals will not actually display strings that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	##
	## > To write to `stderr` with a newline at the end, see [Stderr.line!].
	write! : Str => Try({}, [StderrErr(IOErr)])
	write! = |message| widen_stderr_err(Host.stderr_write!(message))

	## Write the given bytes to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
	##
	## Most terminals will not actually display content that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	write_bytes! : List(U8) => Try({}, [StderrErr(IOErr)])
	write_bytes! = |bytes| widen_stderr_err(Host.stderr_write_bytes!(bytes))
}

## Rebuild the error union so it is open at call sites.
## Passing a hosted function's result straight through leaves the union closed,
## which stops `?` from combining it with other error types.
widen_stderr_err : Try(v, [StderrErr(IOErr)]) -> Try(v, [StderrErr(IOErr)])
widen_stderr_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(StderrErr(err)) => Err(StderrErr(err))
	}
