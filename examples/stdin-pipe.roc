## Number each line of piped text, reading one line at a time.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.Stderr
import pf.Stdin
import pf.Stdout

# Reading piped text from stdin, for example: `cat LICENSE | roc ./examples/stdin-pipe.roc`

main! : List(OsStr) => Try({}, _)
main! = |_| {
	# The stream ends when the input does. The last line need not end in a
	# newline, so `echo -n "hey"` is one line too.
	var $number = 0.U64
	for! item in Stdin.lines() {
		$number = $number + 1
		match item {
			Ok(line) => Stdout.line!("${$number.to_str()}: ${line}")?
			# Only this line is affected; the stream carries on with the next.
			Err(BadUtf8({ index, .. })) => Stderr.line!("${$number.to_str()}: invalid UTF-8 at byte ${index.to_str()}")?
			# Reading failed, and this is the stream's last item.
			Err(Interrupted) => {
				return Err(Interrupted)
			}
			Err(StdinErr(err)) => {
				return Err(StdinErr(err))
			}
		}
	}

	Stdout.line!("Read ${$number.to_str()} line(s)")
}
