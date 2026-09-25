## TODO(https://github.com/roc-lang/roc/issues/11691): requires Stream.custom.
## Check lazy pulls, terminal errors, shared cursors, and stream-owned handles.
app [main!] { pf: platform "../../platform/main.roc" }

import pf.Env
import pf.File
import pf.OsStr
import pf.Path
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| Env.with_temp_dir!(
	|workspace| {
		path = Path.join(workspace, "chunks.dat")
		Path.write_bytes!(path, [0, 255, 128, 10, 1, 2, 3, 4])?
		check_chunks!(path)?
		for early in [Bool.False, Bool.True] {
			match read_one!(path, early) {
				Ok(_) => {}
				Err(ExpectedEarlyReturn) => {}
				Err(err) => return Err(err)
			}
		}
		# This continuation must not keep the file handle alive.
		terminal = error_tail!(path)?
		Path.delete!(path)?
		match Stream.next!(terminal) {
			Done => {}
			_ => return Err(ExpectedTerminalError)
		}
		Path.write_bytes!(path, [])?
		check_empty!(path)?
		Path.delete!(path)?
		Stdout.line!("Binary chunk streams and resource cleanup passed")
	},
)

check_chunks! = |path| {
	reader = File.open_reader_with_capacity!(path, 2)?
	match reader.chunks(0) {
		Err(InvalidChunkSize) => {}
		Ok(_) => return Err(ExpectedInvalidChunkSize)
	}
	stream = reader.chunks(2)?
	expect Stream.size_hint(stream) == Unknown
	before = reader.position!()?
	expect before == 0
	# An alias can move the cursor between construction and consumption.
	_ = reader.seek!(Start(1))?
	first = pull!(stream)?
	expect first.bytes == [255, 128]
	after = reader.position!()?
	expect after == 3
	# Later pulls consult the same cursor and do not invalidate retained chunks.
	_ = reader.seek!(End(-2))?
	last = pull!(first.rest)?
	expect last.bytes == [3, 4]
	match Stream.next!(last.rest) {
		Done => {}
		_ => return Err(ExpectedEOF)
	}
	_ = reader.seek!(Start(0))?
	# A fresh stream can read again after EOF and a seek.
	all = Stream.collect!(reader.chunks(3)?)
	var $contents = []
	for result in all {
		bytes = result?
		expect !bytes.is_empty()
		expect bytes.len() <= 3
		$contents = List.concat($contents, bytes)
	}
	expect $contents == [0, 255, 128, 10, 1, 2, 3, 4]
	expect first.bytes == [255, 128]
	_ = reader.seek!(Start(0))?
	lengths = Stream.collect!(Stream.map(reader.chunks(3)?, |item| item.map_ok(|bytes| bytes.len())))
	var $total = 0.U64
	for length in lengths {
		$total = $total + length?
	}
	expect $total == 8
	Ok({})
}

pull! = |stream|
	match Stream.next!(stream) {
		One({ item, rest }) => Ok({ bytes: item?, rest })
		_ => Err(ExpectedChunk)
	}

read_one! = |path, early| {
	# The stream owns the reader after the helper that opened it has returned.
	stream = open_chunks!(path, 2)?
	first = pull!(stream)?
	expect first.bytes == [0, 255]
	if early {
		return Err(ExpectedEarlyReturn)
	}
	Ok({})
}

error_tail! = |path| {
	stream = open_chunks!(path, U64.highest)?
	match Stream.next!(stream) {
		One({ item: Err(FileErr(OutOfMemory)), rest }) => Ok(rest)
		_ => Err(ExpectedReadError)
	}
}

open_chunks! = |path, max_bytes| {
	reader = File.open_reader!(path)?
	reader.chunks(max_bytes)
}

check_empty! = |path| {
	reader = File.open_reader!(path)?
	stream = reader.chunks(8)?
	match Stream.next!(stream) {
		Done => Ok({})
		_ => Err(ExpectedEOF)
	}
}
