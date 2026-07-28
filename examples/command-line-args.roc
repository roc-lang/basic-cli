## Read native command-line arguments without losing non-Unicode data.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0/4rAQg8kUYZ3Vksr4qMQHpaFYNiHSn9GgS7gVxghd1XYV.tar.zst" }

import pf.OsStr
import pf.Stdout

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

			Ok({})
		}
		[] => Err(MissingArgument)
	}
}
