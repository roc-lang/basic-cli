import InternalUtf16

## Represent operating-system strings without losing non-Unicode data.
##
## Native Unix bytes and Windows UTF-16 units roundtrip through host effects;
## use [`display`](#display) only when a lossy representation is acceptable.
OsStr := [
	Utf8(Str),
	UnixBytes(List(U8)),
	WindowsU16s(List(U16)),
].{

	## Create an OS string from a dynamic UTF-8 `Str`. String literals can be used
	## directly wherever an `OsStr` is expected. The host lowers UTF-8 text to the
	## active OS representation.
	from_str : Str -> OsStr
	from_str = |str| Utf8(str)

	## Create a UTF-8 OS string from a dynamic `Str`. The same as [from_str],
	## named like the other representation constructors.
	utf8 : Str -> OsStr
	utf8 = from_str

	## Create a Unix OS string from a Roc string by storing its UTF-8 bytes.
	unix : Str -> OsStr
	unix = |str| UnixBytes(Str.to_utf8(str))

	## Create a Unix OS string from raw bytes without validating UTF-8.
	unix_bytes : List(U8) -> OsStr
	unix_bytes = |bytes| UnixBytes(bytes)

	## Create a Windows OS string from a Roc string by storing its UTF-16 code units.
	windows : Str -> OsStr
	windows = |str| from_raw(WindowsU16s(InternalUtf16.from_str(str)))

	## Create a Windows OS string from raw UTF-16 code units.
	windows_u16s : List(U16) -> OsStr
	windows_u16s = |u16s| WindowsU16s(u16s)

	## Build an OS string from a quoted string literal.
	from_quote : Str -> Try(OsStr, [BadQuotedBytes(Str)])
	from_quote = |str| Ok(Utf8(str))

	## Build a UTF-8 OS string from an interpolated string literal.
	from_interpolation : List(Str) -> Try((List(Str) -> OsStr), [InvalidInterpolation(Str)])
	from_interpolation = |segments|
		Str.from_interpolation(segments).map_ok(|assemble| |values| Utf8(assemble(values)))

	## Parse and encode every OS string representation as a lossless tagged value.
	parser_for : _
	encoder_for : _

	## Convert an OS string to a string if its raw representation is valid text.
	to_str_try : OsStr -> Try(Str, [InvalidStr(U64)])
	to_str_try = |os_str|
		match to_raw(os_str) {
			Utf8(str) => Ok(str)
			UnixBytes(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Ok(str)
					Err(BadUtf8({ index, problem: _ })) => Err(InvalidStr(index))
				}
			WindowsU16s(u16s) => InternalUtf16.to_str(u16s)
		}

	## Convert an OS string to the bytes that represent it, for writing to a byte
	## stream such as [Stdout.write_bytes!] or [Stderr.write_bytes!].
	##
	## UTF-8 text and Unix OS strings return their exact bytes, so non-Unicode Unix
	## data is preserved. Windows OS strings are UTF-16 code units rather than bytes,
	## so they are encoded as UTF-8 with unpaired surrogates replaced by U+FFFD;
	## that conversion is lossy and must not be used for roundtripping.
	to_bytes : OsStr -> List(U8)
	to_bytes = |os_str|
		match to_raw(os_str) {
			Utf8(str) => Str.to_utf8(str)
			UnixBytes(bytes) => bytes
			WindowsU16s(u16s) => InternalUtf16.to_utf8_lossy(u16s)
		}

	## Convert an OS string to a best-effort display string, replacing invalid text
	## with U+FFFD. This representation is lossy and must not be used for roundtripping.
	display : OsStr -> Str
	display = |os_str|
		match to_raw(os_str) {
			Utf8(str) => str
			UnixBytes(bytes) => Str.from_utf8_lossy(bytes)
			WindowsU16s(u16s) => Str.from_utf8_lossy(InternalUtf16.to_utf8_lossy(u16s))
		}

	## Customize debug output for `Str.inspect`.
	to_inspect : OsStr -> Str
	to_inspect = |os_str|
		match to_raw(os_str) {
			Utf8(str) => "OsStr.utf8(${Json.to_str(str)})"
			UnixBytes(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => "OsStr.unix(${Json.to_str(str)})"
					Err(_) => "OsStr.unix_bytes(${Str.inspect(bytes)})"
				}
			WindowsU16s(u16s) =>
				match InternalUtf16.to_str(u16s) {
					Ok(str) => "OsStr.windows(${Json.to_str(str)})"
					Err(_) => "OsStr.windows_u16s(${Str.inspect(u16s)})"
				}
		}

	## Compare OS strings by content, whichever representation holds it.
	##
	## A string literal is stored as UTF-8, while the operating system hands
	## back native units, so `args.contains("--verbose")` and
	## `Env.var!("EDITOR")? == "vim"` compare text with native units.
	##
	## - Two values that are valid Unicode are equal when they are the same text,
	##   in any mix of UTF-8, Unix bytes and Windows UTF-16.
	## - Unix bytes that are not valid UTF-8, or UTF-16 with an unpaired
	##   surrogate, equal only the identical units of the same kind, and never a
	##   UTF-8 value.
	##
	## Nothing is normalized: case, Unicode normal forms and path separators
	## all still distinguish two values.
	is_eq : OsStr, OsStr -> Bool
	is_eq = |left, right|
		match (to_raw(left), to_raw(right)) {
			(Utf8(a), Utf8(b)) => a == b
			(UnixBytes(a), UnixBytes(b)) => a == b
			(WindowsU16s(a), WindowsU16s(b)) => a == b
			(Utf8(str), UnixBytes(bytes)) | (UnixBytes(bytes), Utf8(str)) => Str.to_utf8(str) == bytes
			(Utf8(str), WindowsU16s(u16s)) | (WindowsU16s(u16s), Utf8(str)) => InternalUtf16.from_str(str) == u16s
			# Encoding text never produces an unpaired surrogate, so the last case
			# also requires the UTF-16 side to be valid.
			(UnixBytes(bytes), WindowsU16s(u16s)) | (WindowsU16s(u16s), UnixBytes(bytes)) =>
				match Str.from_utf8(bytes) {
					Ok(str) => InternalUtf16.from_str(str) == u16s
					Err(_) => False
				}
		}

	## Hash OS strings consistently with [is_eq]: valid Unicode hashes as its
	## text in every representation, and anything else as its raw units.
	to_hash : OsStr, Hasher -> Hasher
	to_hash = |os_str, hasher|
		match to_raw(os_str) {
			Utf8(str) => Str.to_hash(str, hasher)
			UnixBytes(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Str.to_hash(str, hasher)
					Err(_) => List.to_hash(bytes, hasher)
				}
			WindowsU16s(u16s) =>
				match InternalUtf16.to_str(u16s) {
					Ok(str) => Str.to_hash(str, hasher)
					Err(_) => List.to_hash(u16s, hasher)
				}
		}

	## Expose the host ABI representation.
	to_raw : OsStr -> [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]
	to_raw = |os_str|
		match os_str {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => UnixBytes(bytes)
			WindowsU16s(u16s) => WindowsU16s(u16s)
		}

	## Build an OS string from the host ABI representation.
	from_raw : [Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))] -> OsStr
	from_raw = |raw|
		match raw {
			Utf8(str) => Utf8(str)
			UnixBytes(bytes) => UnixBytes(bytes)
			WindowsU16s(u16s) => WindowsU16s(u16s)
		}

}

## Inspection identifies the representation and preserves invalid raw units.
expect Str.inspect(OsStr.utf8("a\nb")) == "OsStr.utf8(\"a\\nb\")"
expect Str.inspect(OsStr.unix("abc")) == "OsStr.unix(\"abc\")"
expect Str.inspect(OsStr.unix_bytes([97, 255, 98])) == "OsStr.unix_bytes([97, 255, 98])"
expect Str.inspect(OsStr.windows("abc")) == "OsStr.windows(\"abc\")"
expect Str.inspect(OsStr.windows_u16s([0xD800, 97])) == "OsStr.windows_u16s([55296, 97])"

## Interpolation creates a UTF-8 representation.
expect {
	name = "config"
	value : OsStr
	value = "${name}.toml"
	OsStr.to_raw(value) == Utf8("config.toml")
}

## Equality follows the content, not the representation that holds it.
expect OsStr.utf8("abc") == OsStr.unix("abc")
expect OsStr.unix("abc") == OsStr.utf8("abc")
expect OsStr.utf8("abc") == OsStr.windows("abc")
expect OsStr.windows("abc") == OsStr.utf8("abc")
expect OsStr.unix("abc") == OsStr.windows("abc")
expect OsStr.windows("abc") == OsStr.unix("abc")

## The same representation still compares its units.
expect OsStr.utf8("abc") == OsStr.utf8("abc")
expect OsStr.unix("abc") == OsStr.unix_bytes([97, 98, 99])
expect OsStr.windows("abc") == OsStr.windows_u16s([97, 98, 99])
expect OsStr.utf8("abc") != OsStr.utf8("abd")
expect OsStr.unix("abc") != OsStr.unix("abd")
expect OsStr.windows("abc") != OsStr.windows("abd")

## Different text is unequal in every pairing, including a prefix.
expect OsStr.utf8("abc") != OsStr.unix("abd")
expect OsStr.utf8("abc") != OsStr.windows("abd")
expect OsStr.unix("abc") != OsStr.windows("abd")
expect OsStr.utf8("abc") != OsStr.unix("ab")
expect OsStr.windows("ab") != OsStr.utf8("abc")
expect OsStr.unix("ab") != OsStr.windows("abc")
expect OsStr.utf8("") == OsStr.unix_bytes([])
expect OsStr.utf8("") == OsStr.windows_u16s([])
expect OsStr.unix_bytes([]) == OsStr.windows_u16s([])

## A literal equals the native value the operating system returns for that text.
expect {
	literal : OsStr
	literal = "--verbose"
	literal == OsStr.unix("--verbose") and literal == OsStr.windows("--verbose")
}

## Text outside ASCII compares by code point: two, three and four byte UTF-8
## sequences against one UTF-16 unit or a surrogate pair.
expect OsStr.utf8("é€") == OsStr.unix_bytes([0xC3, 0xA9, 0xE2, 0x82, 0xAC])
expect OsStr.utf8("é€") == OsStr.windows_u16s([0xE9, 0x20AC])
expect OsStr.unix_bytes([0xC3, 0xA9, 0xE2, 0x82, 0xAC]) == OsStr.windows_u16s([0xE9, 0x20AC])
expect OsStr.utf8("🐦") == OsStr.unix_bytes([0xF0, 0x9F, 0x90, 0xA6])
expect OsStr.utf8("🐦") == OsStr.windows_u16s([0xD83D, 0xDC26])
expect OsStr.unix_bytes([0xF0, 0x9F, 0x90, 0xA6]) == OsStr.windows_u16s([0xD83D, 0xDC26])
expect OsStr.windows_u16s([0xD83D, 0xDC26]) == OsStr.unix_bytes([0xF0, 0x9F, 0x90, 0xA6])
expect OsStr.utf8("🐦") != OsStr.windows_u16s([0xD83D, 0xDC27])

## Invalid UTF-8 equals only the identical bytes. It is not the text `display`
## shows for it, and not UTF-16 units with the same numbers.
expect OsStr.unix_bytes([97, 255]) == OsStr.unix_bytes([97, 255])
expect OsStr.unix_bytes([97, 255]) != OsStr.unix_bytes([97, 254])
expect OsStr.unix_bytes([97, 255]) != OsStr.utf8(OsStr.display(OsStr.unix_bytes([97, 255])))
expect OsStr.utf8("a") != OsStr.unix_bytes([97, 255])
expect OsStr.unix_bytes([97, 255]) != OsStr.windows_u16s([97, 255])
expect OsStr.windows_u16s([97, 255]) != OsStr.unix_bytes([97, 255])

## An unpaired surrogate equals only the identical units. It is not the text
## `display` shows for it, and not the bytes a lenient encoder would write.
expect OsStr.windows_u16s([0xD800, 97]) == OsStr.windows_u16s([0xD800, 97])
expect OsStr.windows_u16s([0xD800, 97]) != OsStr.windows_u16s([0xD801, 97])
expect OsStr.windows_u16s([0xD800, 97]) != OsStr.utf8(OsStr.display(OsStr.windows_u16s([0xD800, 97])))
expect OsStr.utf8("a") != OsStr.windows_u16s([0xD800, 97])
expect OsStr.windows_u16s([0xD800, 97]) != OsStr.unix_bytes([0xEF, 0xBF, 0xBD, 97])
expect OsStr.windows_u16s([0xD800, 97]) != OsStr.unix_bytes([0xED, 0xA0, 0x80, 97])
expect OsStr.unix_bytes([0xED, 0xA0, 0x80, 97]) != OsStr.windows_u16s([0xD800, 97])

## Invalid values of different kinds are never equal.
expect OsStr.unix_bytes([255]) != OsStr.windows_u16s([0xD800])
expect OsStr.windows_u16s([0xDC00]) != OsStr.unix_bytes([0xDC])

## Nothing is normalized: case, Unicode normal forms and separators differ.
expect OsStr.utf8("Abc") != OsStr.unix("abc")
expect OsStr.utf8("é") != OsStr.unix("e\u(0301)")
expect OsStr.utf8("a/b") != OsStr.windows("a\\b")
expect OsStr.utf8("./a") != OsStr.unix("a")
expect OsStr.utf8("a/") != OsStr.unix("a")

## Equality is transitive across all three representations, and unequal
## values stay unequal through a third.
expect {
	text = OsStr.utf8("naïve 🐦")
	bytes = OsStr.unix("naïve 🐦")
	units = OsStr.windows("naïve 🐦")
	text == bytes and bytes == units and text == units and units == text and units == bytes and bytes == text
}

expect {
	bytes = OsStr.unix_bytes([97, 255])
	units = OsStr.windows_u16s([97, 255])
	text = OsStr.utf8("aÿ")
	# The units are valid text; the bytes are not, so they equal neither.
	units == text and bytes != units and bytes != text
}

## Inspection still shows the representation of values that are equal.
expect OsStr.utf8("abc") == OsStr.unix("abc") and Str.inspect(OsStr.utf8("abc")) != Str.inspect(OsStr.unix("abc"))
expect Str.inspect(OsStr.windows("abc")) == "OsStr.windows(\"abc\")"

## Hashing agrees with equality, so `Dict`, `Set` and `List.contains` find a
## value through any representation.
expect Dict.single(OsStr.unix("HOME"), "found").get(OsStr.utf8("HOME")) == Ok("found")
expect Dict.single(OsStr.windows("HOME"), "found").get(OsStr.utf8("HOME")) == Ok("found")
expect Dict.single(OsStr.utf8("HOME"), "found").get(OsStr.unix("HOME")) == Ok("found")
expect Dict.single(OsStr.utf8("HOME"), "found").get(OsStr.windows("HOME")) == Ok("found")
expect Dict.single(OsStr.unix("HOME"), "found").get(OsStr.windows("HOME")) == Ok("found")
expect Dict.single(OsStr.windows("HOME"), "found").get(OsStr.unix("HOME")) == Ok("found")
expect Dict.single(OsStr.windows("🐦"), "found").get(OsStr.unix_bytes([0xF0, 0x9F, 0x90, 0xA6])) == Ok("found")
expect Dict.single(OsStr.unix("HOME"), "found").get(OsStr.utf8("home")) == Err(KeyNotFound)

expect {
	literal : OsStr
	literal = "HOME"
	Dict.from_list([(OsStr.unix("PATH"), 1), (OsStr.unix("HOME"), 2)]).get(literal) == Ok(2)
}

expect [OsStr.unix("--quiet"), OsStr.unix("--verbose")].contains("--verbose")
expect [OsStr.windows("--quiet"), OsStr.windows("--verbose")].contains("--verbose")
expect Bool.not([OsStr.unix("--quiet")].contains("--verbose"))

## Values equal across representations collapse to one `Set` or `Dict` key.
expect Set.from_list([OsStr.utf8("abc"), OsStr.unix("abc"), OsStr.windows("abc")]).len() == 1
expect Set.from_list([OsStr.utf8("abc"), OsStr.unix("abc"), OsStr.windows("abd")]).len() == 2
expect Set.from_list([OsStr.unix("abc")]).contains(OsStr.windows("abc"))
expect Dict.from_list([(OsStr.utf8("k"), 1), (OsStr.unix("k"), 2), (OsStr.windows("k"), 3)]).len() == 1

## Invalid native units are still usable keys, and stay apart from text and
## from each other.
expect Dict.single(OsStr.unix_bytes([97, 255]), "found").get(OsStr.unix_bytes([97, 255])) == Ok("found")
expect Dict.single(OsStr.windows_u16s([0xD800, 97]), "found").get(OsStr.windows_u16s([0xD800, 97])) == Ok("found")
expect Dict.single(OsStr.unix_bytes([97, 255]), "found").get(OsStr.windows_u16s([97, 255])) == Err(KeyNotFound)
expect Dict.single(OsStr.windows_u16s([0xD800, 97]), "found").get(OsStr.utf8(OsStr.display(OsStr.windows_u16s([0xD800, 97])))) == Err(KeyNotFound)
expect Set.from_list([OsStr.unix_bytes([97, 255]), OsStr.windows_u16s([97, 255]), OsStr.utf8("aÿ")]).len() == 2

## `to_bytes` keeps raw Unix bytes and encodes other representations as UTF-8.
expect OsStr.to_bytes(OsStr.utf8("abc")) == [97, 98, 99]
expect OsStr.to_bytes(OsStr.unix("abc")) == [97, 98, 99]
expect OsStr.to_bytes(OsStr.unix_bytes([97, 255, 98])) == [97, 255, 98]
expect OsStr.to_bytes(OsStr.windows("abc")) == [97, 98, 99]
expect OsStr.to_bytes(OsStr.windows_u16s([0xD800, 97])) == [0xEF, 0xBF, 0xBD, 97]

## Generic codecs roundtrip non-text representations without loss.
expect {
	original = OsStr.windows_u16s([0xD800, 97])
	decoded : Try(OsStr, _)
	decoded = Json.parse(Json.to_str(original))
	decoded == Ok(original)
}

expect {
	original = OsStr.unix_bytes([97, 255])
	decoded : Try(OsStr, _)
	decoded = Json.parse(Json.to_str(original))
	decoded == Ok(original)
}

## Constructors and raw conversion keep the representation they name.
expect OsStr.to_raw(OsStr.from_str("abc")) == Utf8("abc")
expect OsStr.to_raw(OsStr.utf8("abc")) == Utf8("abc")
expect OsStr.to_raw(OsStr.unix("abc")) == UnixBytes([97, 98, 99])
expect OsStr.to_raw(OsStr.windows("abc")) == WindowsU16s([97, 98, 99])
expect OsStr.to_raw(OsStr.from_raw(UnixBytes([97, 255]))) == UnixBytes([97, 255])
expect OsStr.to_raw(OsStr.from_raw(WindowsU16s([0xD800, 97]))) == WindowsU16s([0xD800, 97])
