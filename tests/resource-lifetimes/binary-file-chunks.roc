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
		for early in [False, True] {
			match read_one!(path, early) {
				Ok(_) => {}
				Err(ExpectedEarlyReturn) => {}
				Err(err) => return Err(err)
			}
		}
		# This continuation must not keep the handle alive. Reading a directory
		# fails, which makes the error item that ends the stream.
		tail = error_tail!(workspace)
		Path.delete!(path)?
		match tail {
			Ok(terminal) =>
				match Stream.next!(terminal) {
					Done => {}
					_ => return Err(ExpectedTerminalError)
				}
			# Windows refuses to open a directory, so there is no stream to end.
			Err(PathErr(IsADirectory, _)) => {}
			Err(err) => return Err(err)
		}
		Path.write_bytes!(path, [])?
		check_empty!(path)?
		Path.delete!(path)?
		Stdout.line!("Binary chunk streams and resource cleanup passed")
	},
)

check_chunks! = |path| {
	reader = File.open_reader_with_capacity!(path, 2)?
	stream = reader.chunks()
	expect Stream.size_hint(stream) == Unknown
	before = reader.position!()?
	expect before == 0
	# An alias can move the cursor between construction and consumption.
	_ = reader.seek!(Start(1))?
	first = pull!(stream)?
	expect first.bytes == [255, 128, 10, 1, 2, 3, 4]
	after = reader.position!()?
	expect after == 8
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
	all = Stream.collect!(reader.chunks())
	var $contents = []
	for result in all {
		bytes = result?
		expect !bytes.is_empty()
		expect bytes.len() <= 65_536
		$contents = List.concat($contents, bytes)
	}
	expect $contents == [0, 255, 128, 10, 1, 2, 3, 4]
	expect first.bytes == [255, 128, 10, 1, 2, 3, 4]
	_ = reader.seek!(Start(0))?
	lengths = Stream.collect!(Stream.map(reader.chunks(), |item| item.map_ok(|bytes| bytes.len())))
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
	stream = open_chunks!(path)?
	first = pull!(stream)?
	expect first.bytes == [0, 255, 128, 10, 1, 2, 3, 4]
	if early {
		return Err(ExpectedEarlyReturn)
	}
	Ok({})
}

error_tail! = |path| {
	stream = open_chunks!(path)?
	match Stream.next!(stream) {
		One({ item: Err(FileErr(_)), rest }) => Ok(rest)
		_ => Err(ExpectedReadError)
	}
}

open_chunks! = |path| {
	reader = File.open_reader!(path)?
	Ok(reader.chunks())
}

check_empty! = |path| {
	reader = File.open_reader!(path)?
	stream = reader.chunks()
	match Stream.next!(stream) {
		Done => Ok({})
		_ => Err(ExpectedEOF)
	}
}
