## Represent operating-system strings without losing non-Unicode data.
##
## Native Unix bytes and Windows UTF-16 units roundtrip through host effects;
## use [`display`](#display) only when a lossy representation is acceptable.
OsStr := [
	Utf8(Str),
	UnixBytes(List(U8)),
	WindowsU16s(List(U16)),
].{

	## Create an OS string from UTF-8 text.
	## The host lowers this text to the active OS representation.
	from_str : Str -> OsStr
	from_str = |str| Utf8(str)

	## Create a UTF-8 text OS string.
	utf8 : Str -> OsStr
	utf8 = |str| Utf8(str)

	## Create a Unix OS string from a Roc string by storing its UTF-8 bytes.
	unix : Str -> OsStr
	unix = |str| UnixBytes(Str.to_utf8(str))

	## Create a Unix OS string from raw bytes without validating UTF-8.
	unix_bytes : List(U8) -> OsStr
	unix_bytes = |bytes| UnixBytes(bytes)

	## Create a Windows OS string from a Roc string by storing its UTF-16 code units.
	windows : Str -> OsStr
	windows = |str| from_raw(WindowsU16s(str_to_utf16(str)))

	## Create a Windows OS string from raw UTF-16 code units.
	windows_u16s : List(U16) -> OsStr
	windows_u16s = |u16s| WindowsU16s(u16s)

	## Build an OS string from a quoted string literal.
	from_quote : Str -> Try(OsStr, [BadQuotedBytes(Str)])
	from_quote = |str| Ok(Utf8(str))

	## Build a UTF-8 OS string from an interpolated string literal.
	from_interpolation : Str, Iter((Str, Str)) -> OsStr
	from_interpolation = |first, rest|
		Utf8(rest.fold(first, |acc, (interpolated, segment)| acc.concat(interpolated).concat(segment)))

	## TODO: Restore generic parser_for and encoder_for helpers when the compiler
	## no longer treats auto-derived `_` declarations in platforms as hosted:
	## https://github.com/roc-lang/roc/issues/10162

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
			WindowsU16s(u16s) => utf16_to_str(u16s)
		}

	## Convert an OS string to a best-effort display string, replacing invalid text
	## with U+FFFD. This representation is lossy and must not be used for roundtripping.
	display : OsStr -> Str
	display = |os_str|
		match to_raw(os_str) {
			Utf8(str) => str
			UnixBytes(bytes) => Str.from_utf8_lossy(bytes)
			WindowsU16s(u16s) => Str.from_utf8_lossy(utf16_to_utf8_lossy(u16s))
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
				match utf16_to_str(u16s) {
					Ok(str) => "OsStr.windows(${Json.to_str(str)})"
					Err(_) => "OsStr.windows_u16s(${Str.inspect(u16s)})"
				}
			}

	## Compare OS strings by their exact tagged representation.
	is_eq : OsStr, OsStr -> Bool
	is_eq = |left, right| to_raw(left) == to_raw(right)

	## Hash OS strings consistently with exact tagged equality.
	to_hash : OsStr, Hasher -> Hasher
	to_hash = |os_str, hasher|
		match to_raw(os_str) {
			Utf8(str) => Str.to_hash(str, Hasher.write_u8(hasher, 0))
			UnixBytes(bytes) => List.to_hash(bytes, Hasher.write_u8(hasher, 1))
			WindowsU16s(u16s) => List.to_hash(u16s, Hasher.write_u8(hasher, 2))
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

str_to_utf16 : Str -> List(U16)
str_to_utf16 = |str| utf8_to_utf16(Str.to_utf8(str), [])

utf8_to_utf16 : List(U8), List(U16) -> List(U16)
utf8_to_utf16 = |remaining, out|
	match remaining {
		[] => out
		[byte, .. as rest] if byte < 0x80 =>
			utf8_to_utf16(rest, out.append(U8.to_u16(byte)))
		[byte1, byte2, .. as rest] if byte1 < 0xE0 => {
			top = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte1, 0x1F)), 6)
			bottom = U8.to_u32(U8.bitwise_and(byte2, 0x3F))
			utf8_to_utf16(rest, out.append(U32.to_u16_wrap(U32.bitwise_or(top, bottom))))
		}
		[byte1, byte2, byte3, .. as rest] if byte1 < 0xF0 => {
			top = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte1, 0x0F)), 12)
			middle = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte2, 0x3F)), 6)
			bottom = U8.to_u32(U8.bitwise_and(byte3, 0x3F))
			code_point = U32.bitwise_or(U32.bitwise_or(top, middle), bottom)
			utf8_to_utf16(rest, out.append(U32.to_u16_wrap(code_point)))
		}
		[byte1, byte2, byte3, byte4, .. as rest] => {
			top = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte1, 0x07)), 18)
			middle1 = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte2, 0x3F)), 12)
			middle2 = U32.shl_wrap(U8.to_u32(U8.bitwise_and(byte3, 0x3F)), 6)
			bottom = U8.to_u32(U8.bitwise_and(byte4, 0x3F))
			code_point = U32.bitwise_or(U32.bitwise_or(U32.bitwise_or(top, middle1), middle2), bottom)
			high = U32.to_u16_wrap(0xD800 + U32.shr_wrap(code_point - 0x10000, 10))
			low = U32.to_u16_wrap(0xDC00 + U32.bitwise_and(code_point - 0x10000, 0x3FF))
			utf8_to_utf16(rest, out.append(high).append(low))
		}
		_ => {
			crash "A Str contained invalid UTF-8. This should never happen."
		}
	}

utf16_to_str : List(U16) -> Try(Str, [InvalidStr(U64)])
utf16_to_str = |u16s|
	match utf16_to_utf8(u16s, [], 0) {
		Ok(bytes) =>
			match Str.from_utf8(bytes) {
				Ok(str) => Ok(str)
				Err(BadUtf8({ index, problem: _ })) => Err(InvalidStr(index))
			}
		Err(InvalidUtf16(index)) => Err(InvalidStr(index))
	}

utf16_to_utf8 : List(U16), List(U8), U64 -> Try(List(U8), [InvalidUtf16(U64)])
utf16_to_utf8 = |remaining, out, index|
	match remaining {
		[] => Ok(out)
		[high, low, .. as rest] if is_high_surrogate(high) and is_low_surrogate(low) => {
			high_bits = U32.shl_wrap(U16.to_u32(high) - 0xD800, 10)
			low_bits = U16.to_u32(low) - 0xDC00
			code_point = 0x10000 + high_bits + low_bits
			utf16_to_utf8(rest, append_code_point_utf8(out, code_point), index + 2)
		}
		[unit, ..] if is_surrogate(unit) => Err(InvalidUtf16(index))
		[unit, .. as rest] =>
			utf16_to_utf8(rest, append_code_point_utf8(out, U16.to_u32(unit)), index + 1)
		}

utf16_to_utf8_lossy : List(U16) -> List(U8)
utf16_to_utf8_lossy = |u16s| utf16_to_utf8_lossy_help(u16s, [])

utf16_to_utf8_lossy_help : List(U16), List(U8) -> List(U8)
utf16_to_utf8_lossy_help = |remaining, out|
	match remaining {
		[] => out
		[high, low, .. as rest] if is_high_surrogate(high) and is_low_surrogate(low) => {
			high_bits = U32.shl_wrap(U16.to_u32(high) - 0xD800, 10)
			low_bits = U16.to_u32(low) - 0xDC00
			code_point = 0x10000 + high_bits + low_bits
			utf16_to_utf8_lossy_help(rest, append_code_point_utf8(out, code_point))
		}
		[unit, .. as rest] if is_surrogate(unit) =>
			utf16_to_utf8_lossy_help(rest, append_code_point_utf8(out, 0xFFFD))
		[unit, .. as rest] =>
			utf16_to_utf8_lossy_help(rest, append_code_point_utf8(out, U16.to_u32(unit)))
		}

append_code_point_utf8 : List(U8), U32 -> List(U8)
append_code_point_utf8 = |out, code_point|
	if code_point < 0x80 {
		out.append(U32.to_u8_wrap(code_point))
	} else if code_point < 0x800 {
		out.append(U32.to_u8_wrap(0xC0 + U32.shr_wrap(code_point, 6)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(code_point, 0x3F)))
	} else if code_point < 0x10000 {
		out.append(U32.to_u8_wrap(0xE0 + U32.shr_wrap(code_point, 12)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(U32.shr_wrap(code_point, 6), 0x3F)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(code_point, 0x3F)))
	} else {
		out.append(U32.to_u8_wrap(0xF0 + U32.shr_wrap(code_point, 18)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(U32.shr_wrap(code_point, 12), 0x3F)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(U32.shr_wrap(code_point, 6), 0x3F)))
			.append(U32.to_u8_wrap(0x80 + U32.bitwise_and(code_point, 0x3F)))
	}

is_high_surrogate : U16 -> Bool
is_high_surrogate = |unit| unit >= 0xD800 and unit <= 0xDBFF

is_low_surrogate : U16 -> Bool
is_low_surrogate = |unit| unit >= 0xDC00 and unit <= 0xDFFF

is_surrogate : U16 -> Bool
is_surrogate = |unit| unit >= 0xD800 and unit <= 0xDFFF

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
	value == OsStr.utf8("config.toml")
}

## Equality and hashing preserve representation identity.
expect OsStr.utf8("abc") != OsStr.unix("abc")
expect Dict.single(OsStr.unix_bytes([97, 255]), "found").get(OsStr.unix_bytes([97, 255])) == Ok("found")
