import IOErr
import Host

## Write text or raw bytes to the process's standard error stream.
Stderr :: [].{

	## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
	## followed by a newline.
	##
	## > To write to `stderr` without the newline, see [Stderr.write!].
	line! : Str => Try({}, [Interrupted, StderrErr(IOErr)])
	line! = |message| widen_stderr_err(Host.stderr_line!(message))

	## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
	##
	## Most terminals will not actually display strings that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	##
	## > To write to `stderr` with a newline at the end, see [Stderr.line!].
	write! : Str => Try({}, [Interrupted, StderrErr(IOErr)])
	write! = |message| widen_stderr_err(Host.stderr_write!(message))

	## Write the given bytes to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
	##
	## Most terminals will not actually display content that are written to them until they receive a newline,
	## so this may appear to do nothing until you write a newline!
	write_bytes! : List(U8) => Try({}, [Interrupted, StderrErr(IOErr)])
	write_bytes! = |bytes| widen_stderr_err(Host.stderr_write_bytes!(bytes))
}

## Rebuild the error union so app authors get an open row.
##
## An error row that crosses the host boundary is closed by design, and a
## wrapper that forwards the hosted result keeps that closed row. Every public
## function here rebuilds the union instead, so its error combines with others
## in every call form, including `err! = Stderr.line!` followed by `err!(text)?`.
## `tests/error-rows.roc` covers that form.
widen_stderr_err : Try(v, [Interrupted, StderrErr(IOErr)]) -> Try(v, [Interrupted, StderrErr(IOErr)])
widen_stderr_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(Interrupted) => Err(Interrupted)
		Err(StderrErr(err)) => Err(StderrErr(err))
	}
