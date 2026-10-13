import IOErr
import Host

## Read lines, chunks, or all remaining bytes from standard input.
##
## Every read ends the same way: once all input has been returned, the next
## read is `Err(EndOfInput)`. An empty `Ok` is real data, such as an empty line.
## All reads share one buffer, so they can be mixed freely: reading a few lines
## and then calling [read_to_end!] loses nothing.
Stdin :: [].{

	## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
	##
	## A line ends at `\n`. The terminator is not returned, and one `\r` before
	## it is removed. Input that ends without a `\n` still yields its last
	## line; after that the result is `Err(EndOfInput)`. An empty line is
	## `Ok("")`.
	##
	## A line that is not valid UTF-8 is consumed and reported as `BadUtf8`;
	## the next call reads the line after it.
	##
	## > This function will block the program from continuing until `stdin` receives a newline character
	## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
	## program having gotten stuck. It's often helpful to print a prompt first, so
	## the user knows it's necessary to enter something before the program will continue.
	line! : () => Try(Str, [EndOfInput, BadUtf8({ problem : Str.Utf8Problem, index : U64 }), StdinErr(IOErr)])
	line! = ||
		match Host.stdin_line!() {
			Ok(bytes) => Str.from_utf8(bytes)
			Err(EndOfInput) => Err(EndOfInput)
			Err(StdinErr(err)) => Err(StdinErr(err))
		}

	## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
	##
	## Returns at least one byte and no more than 16,384, or `Err(EndOfInput)`
	## once the input has ended. Use [chunks] to process all of the input a
	## piece at a time, or [read_to_end!] to collect it.
	##
	## > This is typically used in combination with [Tty.enable_raw_mode!],
	## which disables default terminal behaviour and allows reading input
	## without buffering until Enter key is pressed.
	bytes! : () => Try(List(U8), [EndOfInput, StdinErr(IOErr)])
	bytes! = || widen_stdin_end_err(Host.stdin_bytes!())

	## Read all bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin))
	## until [EOF](https://en.wikipedia.org/wiki/End-of-file) in this source.
	read_to_end! : () => Try(List(U8), [StdinErr(IOErr)])
	read_to_end! = || widen_stdin_err(Host.stdin_read_to_end!())

	## Lazily read standard input a line at a time, as [line!] does.
	##
	## Building the stream reads nothing. The stream ends at the end of input.
	## A `BadUtf8` item concerns one line, and the stream continues with the
	## next. A `StdinErr` item is the last one.
	##
	## Each item is one read and the stream holds no input of its own, so
	## leaving the loop early loses nothing: whatever reads next, including a
	## second `Stdin.lines()`, starts at the line after the last one yielded.
	##
	## ```roc
	## for! item in Stdin.lines() {
	##     match item {
	##         Ok(line) => Stdout.line!(line)?
	##         Err(BadUtf8(_)) => {}
	##         Err(StdinErr(err)) => { return Err(StdinErr(err)) }
	##     }
	## }
	## ```
	lines : () -> Stream(Try(Str, [BadUtf8({ problem : Str.Utf8Problem, index : U64 }), StdinErr(IOErr)]))
	lines = ||
		Stream.custom(
			Reading,
			Unknown,
			|state|
				match state {
					Finished => Err(NoMore)
					Reading =>
						match line!() {
							Ok(text) => Ok((Ok(text), Reading))
							Err(EndOfInput) => Err(NoMore)
							Err(BadUtf8(problem)) => Ok((Err(BadUtf8(problem)), Reading))
							Err(StdinErr(err)) => Ok((Err(StdinErr(err)), Finished))
						}
				},
		)

	## Lazily read standard input as non-empty chunks of bytes, as [bytes!]
	## does. Chunk boundaries do not correspond to lines or text encoding
	## boundaries.
	##
	## Building the stream reads nothing. The stream ends at the end of input,
	## and a `StdinErr` item is the last one. Each item is one read and the
	## stream holds no input of its own, so it can follow [line!] or [lines]
	## without losing a byte.
	##
	## ```roc
	## for! item in Stdin.chunks() {
	##     Stdout.write_bytes!(item?)?
	## }
	## ```
	chunks : () -> Stream(Try(List(U8), [StdinErr(IOErr)]))
	chunks = ||
		Stream.custom(
			Reading,
			Unknown,
			|state|
				match state {
					Finished => Err(NoMore)
					Reading =>
						match bytes!() {
							Ok(chunk) => Ok((Ok(chunk), Reading))
							Err(EndOfInput) => Err(NoMore)
							Err(StdinErr(err)) => Ok((Err(StdinErr(err)), Finished))
						}
				},
		)
}

## A tag union that crosses the host boundary is closed by design, so each
## public function rebuilds the error it forwards. That gives callers an open
## union, which `?` can combine with other error types however the function is
## called: directly, as a method, or through a function value.
widen_stdin_end_err : Try(v, [EndOfInput, StdinErr(IOErr)]) -> Try(v, [EndOfInput, StdinErr(IOErr)])
widen_stdin_end_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(EndOfInput) => Err(EndOfInput)
		Err(StdinErr(err)) => Err(StdinErr(err))
	}

widen_stdin_err : Try(v, [StdinErr(IOErr)]) -> Try(v, [StdinErr(IOErr)])
widen_stdin_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(StdinErr(err)) => Err(StdinErr(err))
	}

# Building a stream is pure: it reads nothing and its length is not known.
expect Stream.size_hint(Stdin.lines()) == Unknown
expect Stream.size_hint(Stdin.chunks()) == Unknown
