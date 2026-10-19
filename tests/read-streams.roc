## Print what `Stdin` and `File.Reader` reads return, so that scripts/test.py
## can check the end-of-input and line rules and that streams lose no input.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.File
import pf.OsStr
import pf.Path
import pf.Stdin
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	mode = match args {
		[arg, ..] => OsStr.display(arg)
		[] => ""
	}

	match mode {
		"stdin-lines" => stdin_lines!()
		"stdin-line-calls" => stdin_line_calls!()
		"stdin-chunks" => stdin_chunks!()
		"header-then-read-to-end" => {
			header!()?
			rest = Stdin.read_to_end!()?
			Stdout.line!("rest: ${show(rest)}")
		}
		"header-then-chunks" => {
			header!()?
			var $rest = []
			for! item in Stdin.chunks() {
				$rest = List.concat($rest, item?)
			}
			Stdout.line!("rest: ${show($rest)}")
		}
		"header-then-lines" => {
			header!()?
			stdin_lines!()
		}
		"file" => Env.with_temp_dir!(|directory| file!(Path.join(directory, "lines.txt")))
		_ => Err(UnknownMode(mode))
	}
}

## Render a value on one line, with a carriage return shown as `\r`.
show = |value| Str.inspect(value).replace_each("\r", "\\r")

## Every per-item tag of `Stdin.lines`, then the end of input, twice over.
stdin_lines! : () => Try({}, _)
stdin_lines! = || {
	for! item in Stdin.lines() {
		match item {
			Ok(line) => Stdout.line!("line: ${show(line)}")?
			Err(BadUtf8({ index, .. })) => Stdout.line!("bad utf8 at byte ${index.to_str()}")?
			Err(StdinErr(err)) => {
				return Err(StdinErr(err))
			}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
		}
	}
	Stdout.line!("stream ended")?
	# A finished stream has not used up the right to ask again.
	Stdout.line!("line! after the end: ${show(Stdin.line!())}")?
	Stdout.line!("bytes! after the end: ${show(Stdin.bytes!())}")
}

## Single reads through a function value, which needs the open error union
## that `Stdin.line!` rebuilds from the host's closed one.
stdin_line_calls! : () => Try({}, _)
stdin_line_calls! = || {
	read! = Stdin.line!
	first = read!()?
	Stdout.line!("first: ${show(first)}")?
	Stdout.line!("second: ${show(read!())}")?
	Stdout.line!("third: ${show(read!())}")?
	Stdout.line!("fourth: ${show(read!())}")?
	match read!() {
		Err(EndOfInput) => Stdout.line!("fifth: end of input")
		other => Err(ExpectedEndOfInput(other))
	}
}

stdin_chunks! : () => Try({}, _)
stdin_chunks! = || {
	var $bytes = []
	for! item in Stdin.chunks() {
		chunk = item?
		if chunk.is_empty() or chunk.len() > 65_536 {
			return Err(BadChunkSize(chunk.len()))
		}
		$bytes = List.concat($bytes, chunk)
	}
	Stdout.line!("chunks: ${show($bytes)}")?
	Stdout.line!("bytes! after the end: ${show(Stdin.bytes!())}")
}

## Read header lines up to the first empty one and leave the loop with `break`.
## The caller then reads the body some other way.
header! : () => Try({}, _)
header! = || {
	for! item in Stdin.lines() {
		match item {
			Ok("") => {
				break
			}
			Ok(line) => Stdout.line!("header: ${show(line)}")?
			Err(BadUtf8(problem)) => {
				return Err(BadUtf8(problem))
			}
			Err(StdinErr(err)) => {
				return Err(StdinErr(err))
			}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
		}
	}
	Ok({})
}

file! : Path => Try({}, _)
file! = |path| {
	# "one\r\n", an empty line, an invalid UTF-8 line, "four\r\r\n", then an
	# unterminated "five".
	contents = List.concat("one\r\n\n".to_utf8(), [0xff, 0xfe, '\n']).concat("four\r\r\nfive".to_utf8())
	Path.write_bytes!(path, contents)?
	reader = File.open_reader_with_capacity!(path, 4)?

	for! item in reader.lines() {
		match item {
			Ok(line) => Stdout.line!("line: ${show(line)}")?
			Err(BadUtf8({ index, .. })) => Stdout.line!("bad utf8 at byte ${index.to_str()}")?
			Err(FileErr(err)) => {
				return Err(FileErr(err))
			}
		}
	}
	# Method calls on the reader need the open error union too.
	end = reader.position!()?
	Stdout.line!("stream ended at byte ${end.to_str()} of ${contents.len().to_str()}")?
	Stdout.line!("read_line! at the end: ${show(reader.read_line!())}")?
	Stdout.line!("read_until! at the end: ${show(reader.read_until!('\n'))}")?
	Stdout.line!("read_up_to!(8) at the end: ${show(reader.read_up_to!(8))}")?
	Stdout.line!("read_up_to!(0) at the end: ${show(reader.read_up_to!(0))}")?
	Stdout.line!("read_exactly!(1) at the end: ${show(reader.read_exactly!(1))}")?
	Stdout.line!("read_exactly!(0) at the end: ${show(reader.read_exactly!(0))}")?
	var $chunks = 0.U64
	for! item in reader.chunks() {
		_ = item?
		$chunks = $chunks + 1
	}
	Stdout.line!("chunks at the end: ${$chunks.to_str()}")?

	# The same reads return data again once the file has grown.
	Path.append_bytes!(path, "!\nsix\n".to_utf8())?
	Stdout.line!("after growth: ${show(reader.read_until!('\n'))}")?
	Stdout.line!("after growth: ${show(reader.read_line!())}")?
	Stdout.line!("after growth: ${show(reader.read_line!())}")?

	# A line stream holds no bytes, so it can be left and the reader moved.
	_ = reader.seek!(Start(0))?
	var $taken = 0.U64
	for! item in reader.lines() {
		match item {
			Ok(line) => Stdout.line!("first pass: ${show(line)}")?
			Err(BadUtf8(_)) => {}
			Err(FileErr(err)) => {
				return Err(FileErr(err))
			}
		}
		$taken = $taken + 1
		if $taken == 2 {
			break
		}
	}
	position = reader.position!()?
	Stdout.line!("position after two lines: ${position.to_str()}")?
	raw = reader.read_exactly!(3)?
	Stdout.line!("read_exactly!(3): ${show(raw)}")?
	Stdout.line!("read_until!('\\n'): ${show(reader.read_until!('\n'))}")?
	_ = reader.seek!(Current(-7))?
	lines = reader.lines()
	_ = reader.seek!(End(-4))?
	for! item in lines {
		match item {
			Ok(line) => Stdout.line!("after seek: ${show(line)}")?
			Err(BadUtf8(_)) => {}
			Err(FileErr(err)) => {
				return Err(FileErr(err))
			}
		}
	}

	# Chunks cover the whole file from wherever the cursor is.
	_ = reader.seek!(Start(1))?
	var $total = 0.U64
	for! item in File.open_reader!(path)?.chunks() {
		$total = $total + item?.len()
	}
	var $from_one = 0.U64
	for! item in reader.chunks() {
		$from_one = $from_one + item?.len()
	}
	Stdout.line!("chunk bytes: ${$total.to_str()} from the start, ${$from_one.to_str()} from byte 1")
}
