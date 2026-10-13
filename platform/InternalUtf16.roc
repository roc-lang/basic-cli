## Convert between Roc strings and the UTF-16 code units of Windows OS strings.
## `OsStr` and `Path` share this module; it is not exposed to applications.
InternalUtf16 :: [].{

	## Encode a string as UTF-16 code units.
	from_str : Str -> List(U16)
	from_str = |str| utf8_to_utf16(Str.to_utf8(str), [])

	## Decode UTF-16 code units, reporting the index of the first unpaired surrogate.
	to_str : List(U16) -> Try(Str, [InvalidStr(U64)])
	to_str = |u16s|
		match utf16_to_utf8(u16s, [], 0) {
			Ok(bytes) =>
				match Str.from_utf8(bytes) {
					Ok(str) => Ok(str)
					Err(BadUtf8({ index, problem: _ })) => Err(InvalidStr(index))
				}
			Err(InvalidUtf16(index)) => Err(InvalidStr(index))
		}

	## Encode UTF-16 code units as UTF-8, replacing each unpaired surrogate with U+FFFD.
	to_utf8_lossy : List(U16) -> List(U8)
	to_utf8_lossy = |u16s| utf16_to_utf8_lossy_help(u16s, [])
}

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

## One, two and three byte sequences become one unit; four bytes become a surrogate pair.
expect InternalUtf16.from_str("") == []
expect InternalUtf16.from_str("a") == [0x61]
expect InternalUtf16.from_str("é") == [0xE9]
expect InternalUtf16.from_str("€") == [0x20AC]
expect InternalUtf16.from_str("🐦") == [0xD83D, 0xDC26]
expect InternalUtf16.from_str("a🐦é") == [0x61, 0xD83D, 0xDC26, 0xE9]

## Valid units decode back to the same text.
expect InternalUtf16.to_str([]) == Ok("")
expect InternalUtf16.to_str([0x61, 0xE9, 0x20AC, 0xD83D, 0xDC26]) == Ok("aé€🐦")
expect InternalUtf16.to_str(InternalUtf16.from_str("naïve/日本語/🐦.txt")) == Ok("naïve/日本語/🐦.txt")

## An unpaired surrogate is reported at its unit index.
expect InternalUtf16.to_str([0xD800]) == Err(InvalidStr(0))
expect InternalUtf16.to_str([0x61, 0xDC26]) == Err(InvalidStr(1))
expect InternalUtf16.to_str([0xD83D, 0xDC26, 0xD83D]) == Err(InvalidStr(2))
expect InternalUtf16.to_str([0xDC26, 0xD83D]) == Err(InvalidStr(0))

## The lossy form replaces each unpaired surrogate with U+FFFD.
expect InternalUtf16.to_utf8_lossy([0x61, 0x62]) == [0x61, 0x62]
expect InternalUtf16.to_utf8_lossy([0xD800, 0x61]) == [0xEF, 0xBF, 0xBD, 0x61]
expect InternalUtf16.to_utf8_lossy([0xD83D, 0xDC26]) == [0xF0, 0x9F, 0x90, 0xA6]
