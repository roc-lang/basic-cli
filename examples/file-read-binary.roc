## Count binary file bytes in bounded chunks after inspecting its header.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.File
import pf.OsStr
import pf.Path
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	path = match args {
		[first, ..] => Path.from_os_str(first)
		[] => return Err(MissingPathArgument)
	}
	reader = File.open_reader!(path)?
	# Preview at most 16 bytes; a short file is valid and an empty one has no header.
	header = match reader.read_up_to!(16) {
		Ok(bytes) => bytes
		Err(EndOfInput) => []
		Err(FileErr(err)) => return Err(FileErr(err))
	}
	Stdout.line!("Header bytes: ${Str.inspect(header)}")?
	_ = reader.seek!(Start(0))?
	var $total = 0.U64
	for! item in reader.chunks() {
		bytes = item?
		$total = $total + bytes.len()
	}
	Stdout.line!("Read ${$total.to_str()} bytes")
}
