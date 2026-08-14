import Host

## A locale represented as a pragmatically validated BCP 47 language tag.
##
## Locale spelling is preserved for display, while equality and hashing are
## ASCII case-insensitive as required for language tags.
Locale :: { raw : Str }.{

	## A reason a locale string could not be parsed.
	ParseErr : [
		Empty,
		EmptySubtag,
		InvalidCharacter,
		InvalidLanguage,
		MissingExtensionValue,
		SubtagTooLong,
	]

	## Parse a dynamic string as a locale.
	##
	## This catches common language-tag mistakes without consulting the IANA
	## registry or implementing every structural rule in BCP 47.
	parse : Str -> Try(Locale, ParseErr)
	parse = |input|
		match validate(input) {
			Ok({}) => Ok(Locale.{ raw: input })
			Err(err) => Err(err)
		}

	## Parse and validate a quoted locale literal.
	##
	## Roc calls this automatically when a quoted literal is expected to have
	## type Locale.
	from_quote : Str -> Try(Locale, [BadQuotedBytes(Str)])
	from_quote = |input|
		match parse(input) {
			Ok(locale) => Ok(locale)
			Err(err) => Err(BadQuotedBytes(parse_err_to_str(err)))
		}

	## Parse a locale from a string value supplied by a generic encoding.
	parser_for : encoding -> (state -> Try({ value : Locale, rest : state }, err))
		where [
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
			encoding.invalid_value : encoding, state -> err,
		]
	parser_for = |encoding| {
		Encoding : encoding

		|state| {
			parsed = Encoding.parse_str(encoding, state)?

			match parse(parsed.value) {
				Ok(locale) => Ok({ value: locale, rest: parsed.rest })
				Err(_) => Err(Encoding.invalid_value(encoding, state))
			}
		}
	}

	## Encode a locale using its original spelling through a generic encoding.
	encoder_for : encoding -> (Locale, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding

		|locale, state| Encoding.encode_str(to_str(locale), state)
	}

	## Return the locale using its original spelling.
	to_str : Locale -> Str
	to_str = |locale| locale.raw

	## Render a locale for debugging and test failures.
	to_inspect : Locale -> Str
	to_inspect = |locale| "Locale(${Json.to_str(locale.raw)})"

	## Compare locale tags without ASCII case distinctions.
	is_eq : Locale, Locale -> Bool
	is_eq = |left, right| ascii_lower(left.raw) == ascii_lower(right.raw)

	## Hash locale tags without ASCII case distinctions.
	to_hash : Locale, Hasher -> Hasher
	to_hash = |locale, hasher| Str.to_hash(ascii_lower(locale.raw), hasher)

	## Returns the most preferred locale for the system or application.
	##
	## POSIX locale names are normalized by removing encoding and modifier
	## suffixes and replacing underscores with hyphens. The special `C` and
	## `POSIX` locales are not language tags and are ignored.
	##
	## Returns `Err(NotAvailable)` if the locale cannot be determined.
	get! : () => Try(Locale, [NotAvailable, ..])
	get! = || {
		raw = widen_locale_err(Host.locale_get!())?
		Ok(Locale.{ raw })
	}

	## Returns the preferred locales for the system or application.
	##
	## Values are normalized and validated as described by `get!`. Invalid values
	## are omitted, and duplicates are removed case-insensitively while preserving
	## preference order.
	all! : () => List(Locale)
	all! = || Host.locale_all!().map(|raw| Locale.{ raw })
}

validate : Str -> Try({}, Locale.ParseErr)
validate = |input|
	if Str.is_empty(input) {
		Err(Empty)
	} else {
		subtags = Str.split_on(input, "-")

		if List.any(subtags, |subtag| Str.is_empty(subtag)) {
			Err(EmptySubtag)
		} else if List.any(subtags, |subtag| has_invalid_character(subtag)) {
			Err(InvalidCharacter)
		} else if List.any(subtags, |subtag| List.len(Str.to_utf8(subtag)) > 8) {
			Err(SubtagTooLong)
		} else {
			validate_structure(subtags)
		}
	}

validate_structure : List(Str) -> Try({}, Locale.ParseErr)
validate_structure = |subtags|
	match subtags {
		[] => Err(Empty)
		[language, .. as rest] => {
			language_bytes = Str.to_utf8(language)
			language_len = List.len(language_bytes)
			is_special = language_len == 1 and (ascii_byte_eq(language_bytes, 'x') or ascii_byte_eq(language_bytes, 'i'))

			if is_special {
				if List.is_empty(rest) {
					Err(MissingExtensionValue)
				} else if ascii_byte_eq(language_bytes, 'x') {
					Ok({})
				} else {
					validate_extensions(rest)
				}
			} else if language_len < 2 or Bool.not(List.all(language_bytes, is_ascii_alpha)) {
				Err(InvalidLanguage)
			} else {
				validate_extensions(rest)
			}
		}
	}

validate_extensions : List(Str) -> Try({}, Locale.ParseErr)
validate_extensions = |subtags|
	match subtags {
		[] => Ok({})
		[subtag, .. as rest] => {
			bytes = Str.to_utf8(subtag)

			if List.len(bytes) == 1 {
				if List.is_empty(rest) {
					Err(MissingExtensionValue)
				} else if ascii_byte_eq(bytes, 'x') {
					Ok({})
				} else {
					validate_extensions(rest)
				}
			} else {
				validate_extensions(rest)
			}
		}
	}

has_invalid_character : Str -> Bool
has_invalid_character = |subtag| Bool.not(List.all(Str.to_utf8(subtag), is_ascii_alphanumeric))

is_ascii_alpha : U8 -> Bool
is_ascii_alpha = |byte| (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

is_ascii_digit : U8 -> Bool
is_ascii_digit = |byte| byte >= 48 and byte <= 57

is_ascii_alphanumeric : U8 -> Bool
is_ascii_alphanumeric = |byte| is_ascii_alpha(byte) or is_ascii_digit(byte)

ascii_byte_eq : List(U8), U8 -> Bool
ascii_byte_eq = |bytes, expected|
	match bytes {
		[byte] => byte == expected or byte == expected - 32
		_ => False
	}

ascii_lower : Str -> Str
ascii_lower = |input|
	Str.from_utf8_lossy(
		Str.to_utf8(input).map(
			|byte|
				if byte >= 65 and byte <= 90 {
					byte + 32
				} else {
					byte
				},
		),
	)

parse_err_to_str : Locale.ParseErr -> Str
parse_err_to_str = |err|
	match err {
		Empty => "Locale must not be empty"
		EmptySubtag => "Locale subtags must not be empty"
		InvalidCharacter => "Locale must contain only ASCII letters, digits, and hyphens"
		InvalidLanguage => "Locale must start with a 2-8 letter language subtag"
		MissingExtensionValue => "Locale extension or private-use marker must be followed by a subtag"
		SubtagTooLong => "Locale subtags must be at most 8 characters"
	}

widen_locale_err : Try(a, [NotAvailable]) -> Try(a, [NotAvailable, ..])
widen_locale_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(NotAvailable) => Err(NotAvailable)
	}

expect
	match Locale.parse("en-US") {
		Ok(locale) => Locale.to_str(locale) == "en-US"
		Err(_) => False
	}

expect
	match Locale.parse("zh-Hant-TW") {
		Ok(locale) => Locale.to_str(locale) == "zh-Hant-TW"
		Err(_) => False
	}

expect Locale.parse("de-CH-1901").is_ok()

expect Locale.parse("en-u-ca-gregory").is_ok()

expect Locale.parse("x-private").is_ok()

expect Locale.parse("x-a").is_ok()

expect Locale.parse("en-x-a").is_ok()

expect Locale.parse("i-default").is_ok()

expect Locale.parse("") == Err(Empty)

expect Locale.parse("en--US") == Err(EmptySubtag)

expect Locale.parse("-en") == Err(EmptySubtag)

expect Locale.parse("en-") == Err(EmptySubtag)

expect Locale.parse("en_US") == Err(InvalidCharacter)

expect Locale.parse("en-café") == Err(InvalidCharacter)

expect Locale.parse("1n-US") == Err(InvalidLanguage)

expect Locale.parse("a-DE") == Err(InvalidLanguage)

expect Locale.parse("en-toolongtag") == Err(SubtagTooLong)

expect Locale.parse("en-u") == Err(MissingExtensionValue)

expect {
	locale : Locale
	locale = "en-US"
	Locale.to_str(locale) == "en-US"
}

expect
	match (Locale.parse("en-US"), Locale.parse("EN-us")) {
		(Ok(left), Ok(right)) => left == right and Locale.to_str(right) == "EN-us"
		_ => False
	}

expect
	match (Locale.parse("en-US"), Locale.parse("fr-FR")) {
		(Ok(left), Ok(right)) => left != right
		_ => False
	}

expect
	match (Locale.parse("en-US"), Locale.parse("EN-us")) {
		(Ok(stored), Ok(lookup)) => Dict.single(stored, "found").get(lookup) == Ok("found")
		_ => False
	}

expect
	match Locale.from_quote("en_US") {
		Err(BadQuotedBytes(message)) => Str.contains(message, "ASCII letters, digits, and hyphens")
		Ok(_) => False
	}

## Inspection preserves spelling and identifies the nominal type.
expect
	match Locale.parse("EN-us") {
		Ok(locale) => Str.inspect(locale) == "Locale(\"EN-us\")"
		Err(_) => False
	}

## Generic encoders preserve the locale's original spelling.
expect {
	locale : Locale
	locale = "en-US"
	Json.to_str(locale) == "\"en-US\""
}

## Generic parsers validate encoded locale strings.
expect {
	decoded : Try(Locale, [InvalidJson(Str)])
	decoded = Json.parse("\"zh-Hant-TW\"")

	match decoded {
		Ok(locale) => Locale.to_str(locale) == "zh-Hant-TW"
		Err(_) => False
	}
}

expect {
	decoded : Try(Locale, [InvalidJson(Str)])
	decoded = Json.parse("\"en_US\"")
	decoded == Err(Json.invalid_json)
}
