## Read native command-line arguments without losing non-Unicode data.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Stderr

main! : List(OsStr) => Try({}, _)
main! = |args| {
	# Skip first arg (executable path), get the remaining args
	match args.drop_first(1) {
		[first_arg, ..] => {

			Stdout.line!("received argument: ${OsStr.display(first_arg)}")?

			match OsStr.to_raw(first_arg) {
				Utf8(str) => {
					Stdout.line!("UTF-8 argument text: ${Str.inspect(str)}")?
					round_tripped_arg = OsStr.from_raw(Utf8(str))
					Stdout.line!("back to OsStr: ${Str.inspect(round_tripped_arg)}")?
				}
				UnixBytes(bytes) => {
					Stdout.line!("Unix argument, bytes: ${Str.inspect(bytes)}")?
					round_tripped_arg = OsStr.from_raw(UnixBytes(bytes))
					Stdout.line!("back to OsStr: ${Str.inspect(round_tripped_arg)}")?
				}
				WindowsU16s(u16s) => {
					Stdout.line!("Windows argument, UTF-16 code units: ${Str.inspect(u16s)}")?
					round_tripped_arg = OsStr.from_raw(WindowsU16s(u16s))
					Stdout.line!("back to OsStr: ${Str.inspect(round_tripped_arg)}")?
				}
			}

			# Arguments are not guaranteed to be valid UTF-8. `Stderr.write_bytes!`
			# takes bytes, and `OsStr.to_bytes` provides them without the U+FFFD
			# replacements that `OsStr.display` would introduce.
			match OsStr.to_str_try(first_arg) {
				Ok(text) => {
					Stdout.line!("argument 1 is valid UTF-8: ${text}")?
				}
				Err(InvalidStr(index)) => {
					Stderr.write!("Invalid UTF-8 at byte ${U64.to_str(index)} in argument 1: \"")?
					Stderr.write_bytes!(OsStr.to_bytes(first_arg))?
					Stderr.line!("\"")?
				}
			}

			Ok({})
		}
		[] => Err(MissingArgument)
	}
}
