## Exercise binary reads, buffered seeks, aliases, and cleanup on read failure.
app [main!] { pf: platform "../../platform/main.roc" }

import pf.Env
import pf.File
import pf.OsStr
import pf.Path
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| Env.with_temp_dir!(
	|workspace| {
		path = Path.join(workspace, "binary.dat")
		Path.write_bytes!(path, [97, 10, 0, 255, 128, 120, 121, 122])?
		check_reader!(path)?
		match fail_early!(path) {
			Err(FileUnexpectedEOF) => {}
			Err(err) => return Err(err)
			Ok(_) => return Err(ExpectedTruncation)
		}
		Path.delete!(path)?
		Path.write_bytes!(path, [])?
		check_empty!(path)?
		Path.delete!(path)?
		Stdout.line!("Binary reads, seeks, and resource cleanup passed")
	},
)

check_reader! = |path| {
	reader = File.open_reader_with_capacity!(path, 4)?
	alias = reader
	line = reader.read_line!()?
	expect line == [97, 10]
	var $position = alias.position!()?
	expect $position == 2
	retained = alias.read_up_to!(2)?
	expect retained == [0, 255]
	$position = reader.seek!(Current(-1))?
	expect $position == 3
	var $bytes = alias.read_exactly!(3)?
	expect $bytes == [255, 128, 120]
	$position = reader.position!()?
	expect $position == 6
	$position = reader.seek!(End(-2))?
	expect $position == 6
	$bytes = reader.read_exactly!(2)?
	expect $bytes == [121, 122]
	$bytes = reader.read_up_to!(1)?
	expect $bytes == []
	$position = reader.seek!(Start(0))?
	expect $position == 0
	$bytes = reader.read_exactly!(2)?
	expect $bytes == [97, 10]
	$bytes = reader.read_up_to!(0)?
	expect $bytes == []
	$bytes = reader.read_exactly!(0)?
	expect $bytes == []
	$position = reader.position!()?
	expect $position == 2
	match reader.read_exactly!(U64.highest) {
		Err(FileErr(OutOfMemory)) => {}
		Err(err) => return Err(err)
		Ok(_) => return Err(ExpectedAllocationFailure)
	}
	match reader.read_up_to!(U64.highest) {
		Err(FileErr(OutOfMemory)) => {}
		Err(err) => return Err(err)
		Ok(_) => return Err(ExpectedAllocationFailure)
	}
	$position = alias.position!()?
	expect $position == 2
	$position = reader.seek!(Start(100))?
	expect $position == 100
	$bytes = alias.read_up_to!(1)?
	expect $bytes == []
	match reader.seek!(End(-100)) {
		Err(FileErr(_)) => {}
		Ok(_) => return Err(ExpectedInvalidSeek)
	}
	$position = reader.seek!(Start(0))?
	expect $position == 0
	expect retained == [0, 255]
	Ok({})
}

fail_early! = |path| {
	reader = File.open_reader!(path)?
	_ = reader.read_exactly!(9)?
	Ok({})
}

check_empty! = |path| {
	reader = File.open_reader!(path)?
	bytes = reader.read_up_to!(16)?
	expect bytes == []
	match reader.read_exactly!(1) {
		Err(FileUnexpectedEOF) => Ok({})
		Err(err) => Err(err)
		Ok(_) => Err(ExpectedTruncation)
	}
}
