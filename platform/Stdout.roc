import IOErr
import Host

## Write text or raw bytes to the process's standard output stream.
Stdout :: [].{

	## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
	## followed by a newline.
	##
	## > To write to `stdout` without the newline, see [Stdout.write!].
	line! : Str => Try({}, [Interrupted, StdoutErr(IOErr)])
	line! = |message| widen_stdout_err(Host.stdout_line!(message))

	## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
	##
	## Note that many terminals will not actually display strings that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	##
	## > To write to `stdout` with a newline at the end, see [Stdout.line!].
	write! : Str => Try({}, [Interrupted, StdoutErr(IOErr)])
	write! = |message| widen_stdout_err(Host.stdout_write!(message))

	## Write the given bytes to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
	##
	## Note that many terminals will not actually display content that is written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	write_bytes! : List(U8) => Try({}, [Interrupted, StdoutErr(IOErr)])
	write_bytes! = |bytes| widen_stdout_err(Host.stdout_write_bytes!(bytes))
}

## Rebuild the error union so app authors get an open row.
##
## An error row that crosses the host boundary is closed by design, and a
## wrapper that forwards the hosted result keeps that closed row. Every public
## function here rebuilds the union instead, so its error combines with others
## in every call form, including `out! = Stdout.line!` followed by `out!(text)?`.
## `tests/error-rows.roc` covers that form.
widen_stdout_err : Try(v, [Interrupted, StdoutErr(IOErr)]) -> Try(v, [Interrupted, StdoutErr(IOErr)])
widen_stdout_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(Interrupted) => Err(Interrupted)
		Err(StdoutErr(err)) => Err(StdoutErr(err))
	}
