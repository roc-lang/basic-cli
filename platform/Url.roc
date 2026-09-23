## A validated HTTP or HTTPS URL implemented entirely in Roc.
##
## This is deliberately stricter than a browser parser. Hosts must be ASCII
## DNS names, dotted-decimal IPv4 addresses, or bracketed IPv6 addresses made
## from hexadecimal groups with optional :: elision. IPv4-in-IPv6 and Unicode
## domain names are intentionally unsupported.
Url :: {
	scheme : [Http, Https],
	host : Str,
	port : [None, Some(U16)],
	path : Str,
	query : [None, Some(Str)],
	fragment : [None, Some(Str)],
}.{

	## A reason a URL or relative reference could not be parsed.
	##
	## This error set describes this module's strict HTTP/HTTPS subset. Inputs
	## that browsers might repair, such as missing authority slashes or
	## backslashes, are rejected instead.
	ParseErr : [
		CredentialsNotAllowed,
		EmptyHost,
		InternationalHostUnsupported,
		InvalidCharacter(U8),
		InvalidHost(Str),
		InvalidIpv4(Str),
		InvalidIpv6(Str),
		InvalidPercentEncoding(U64),
		InvalidPort(Str),
		MissingAuthority,
		MissingScheme,
		PortOutOfRange(U64),
		UnsupportedScheme(Str),
	]

	## Parse a dynamic string as an absolute HTTP or HTTPS URL.
	##
	## The input must contain an explicit scheme and authority. Its host is
	## lowercased, default ports are removed, dot path segments are normalized,
	## and non-ASCII path, query, and fragment bytes are percent-encoded.
	parse : Str -> Try(Url, ParseErr)
	parse = |input| parse_absolute(input)

	## Convert a quoted literal to a URL using the same validation as parse.
	##
	## Roc calls this automatically when a quoted literal is expected to have
	## type Url. A rejected literal reports a descriptive BadQuotedBytes error.
	from_quote : Str -> Try(Url, [BadQuotedBytes(Str)])
	from_quote = |input|
		match parse_absolute(input) {
			Ok(url) => Ok(url)
			Err(err) => Err(BadQuotedBytes(parse_err_to_str(err)))
		}

	## Parse a URL from a string value supplied by a generic encoding.
	parser_for : encoding -> (state -> Try({ value : Url, rest : state }, err))
		where [
			encoding.parse_str : encoding, state -> Try({ value : Str, rest : state }, err),
			encoding.invalid_value : encoding, state -> err,
		]
	parser_for = |encoding| {
		Encoding : encoding

		|state| {
			parsed = Encoding.parse_str(encoding, state)?

			match parse(parsed.value) {
				Ok(url) => Ok({ value: url, rest: parsed.rest })
				Err(_) => Err(Encoding.invalid_value(encoding, state))
			}
		}
	}

	## Encode a URL as its canonical string through a generic encoding.
	encoder_for : encoding -> (Url, state -> Try(state, err))
		where [
			encoding.encode_str : Str, state -> Try(state, err),
		]
	encoder_for = |_encoding| {
		Encoding : encoding

		|url, state| Encoding.encode_str(to_str(url), state)
	}

	## Serialize the URL in a stable normalized ASCII form.
	##
	## Scheme and DNS host names are lowercase, default ports are omitted,
	## paths are absolute, and IPv6 addresses use eight unpadded groups.
	to_str : Url -> Str
	to_str = |url| serialize(url, True)

	## Render a URL for debugging and test failures.
	to_inspect : Url -> Str
	to_inspect = |url| "Url(${Json.to_str(to_str(url))})"

	## Compare URLs by their canonical serialized representation.
	is_eq : Url, Url -> Bool
	is_eq = |left, right| Str.is_eq(to_str(left), to_str(right))

	## Hash URLs consistently with canonical equality.
	to_hash : Url, Hasher -> Hasher
	to_hash = |url, hasher| Str.to_hash(to_str(url), hasher)

	## Return Http or Https.
	scheme : Url -> [Http, Https]
	scheme = |url| url.scheme

	## Return the canonical host.
	##
	## IPv6 brackets are omitted; to_str includes them where required.
	host : Url -> Str
	host = |url|
		if starts_with(url.host, "[") {
			trim_brackets(url.host)
		} else {
			url.host
		}

	## Return an explicit non-default port.
	##
	## Ports 80 for HTTP and 443 for HTTPS are canonicalized to None.
	port : Url -> [None, Some(U16)]
	port = |url| url.port

	## Return the absolute percent-encoded path, always beginning with slash.
	path : Url -> Str
	path = |url| url.path

	## Return the percent-encoded query without its leading question mark.
	##
	## None and Some("") distinguish no query from a present empty query.
	query : Url -> [None, Some(Str)]
	query = |url| url.query

	## Return the percent-encoded fragment without its leading hash.
	##
	## None and Some("") distinguish no fragment from a present empty fragment.
	fragment : Url -> [None, Some(Str)]
	fragment = |url| url.fragment

	## Return this URL without its fragment. HTTP never transmits fragments.
	without_fragment : Url -> Url
	without_fragment = |url|
		Url.{
			scheme: url.scheme,
			host: url.host,
			port: url.port,
			path: url.path,
			query: url.query,
			fragment: None,
		}

	## Resolve a strict relative reference or absolute web URL against this URL.
	##
	## Root-relative, path-relative, query-only, and fragment-only references
	## are supported. Scheme-relative references are rejected.
	resolve : Url, Str -> Try(Url, ParseErr)
	resolve = |base, reference| resolve_reference(base, reference)

	## Append unencoded path segments.
	##
	## Each list item is one segment, so slash characters inside an item are
	## percent-encoded rather than treated as separators.
	append_path_segments : Url, List(Str) -> Url
	append_path_segments = |url, segments| {
		suffix = Str.join_with(segments.map(percent_encode), "/")
		next_path = 
			if Str.is_empty(suffix) {
				url.path
			} else if url.path == "/" {
				Str.concat("/", suffix)
			} else if ends_with(url.path, "/") {
				Str.concat(url.path, suffix)
			} else {
				Str.concat(Str.concat(url.path, "/"), suffix)
			}
		Url.{
			scheme: url.scheme,
			host: url.host,
			port: url.port,
			path: normalize_path(next_path),
			query: url.query,
			fragment: url.fragment,
		}
	}

	## Append one application/x-www-form-urlencoded query pair.
	##
	## Existing parameters, ordering, duplicate names, and the fragment are
	## preserved.
	append_query_param : Url, Str, Str -> Url
	append_query_param = |url, key, value| {
		pair = Str.concat(Str.concat(form_encode(key), "="), form_encode(value))
		next_query = 
			match url.query {
				None => pair
				Some("") => pair
				Some(existing) => Str.concat(Str.concat(existing, "&"), pair)
			}
		Url.{
			scheme: url.scheme,
			host: url.host,
			port: url.port,
			path: url.path,
			query: Some(next_query),
			fragment: url.fragment,
		}
	}

	## Decode the query into ordered name/value pairs.
	##
	## Plus signs decode as spaces, percent escapes decode as UTF-8 bytes,
	## parameters without equals receive an empty value, and duplicates remain.
	query_pairs : Url -> List((Str, Str))
	query_pairs = |url|
		match url.query {
			None => []
			Some("") => []
			Some(query_str) =>
				Str.split_on(query_str, "&").map(
					|pair|
						match split_first(pair, "=") {
							Found({ before, after }) => (form_decode(before), form_decode(after))
							NotFound => (form_decode(pair), "")
						},
				)
			}

	## Replace or remove the query.
	##
	## Some("") produces a present empty query. The supplied query may contain
	## Unicode but must otherwise already obey URL query syntax.
	with_query : Url, [None, Some(Str)] -> Try(Url, ParseErr)
	with_query = |url, option| {
		next_query_option = 
			match option {
				None => Ok(None)
				Some(raw) =>
					match validate_component(raw, Query) {
						Ok(value) => Ok(Some(value))
						Err(err) => Err(err)
					}
				}?
		Ok(
			Url.{
				scheme: url.scheme,
				host: url.host,
				port: url.port,
				path: url.path,
				query: next_query_option,
				fragment: url.fragment,
			},
		)
	}

	## Replace or remove the fragment.
	##
	## Some("") produces a present empty fragment. Unicode is percent-encoded.
	with_fragment : Url, [None, Some(Str)] -> Try(Url, ParseErr)
	with_fragment = |url, option| {
		next_fragment_option = 
			match option {
				None => Ok(None)
				Some(raw) =>
					match validate_component(raw, Fragment) {
						Ok(value) => Ok(Some(value))
						Err(err) => Err(err)
					}
				}?
		Ok(
			Url.{
				scheme: url.scheme,
				host: url.host,
				port: url.port,
				path: url.path,
				query: url.query,
				fragment: next_fragment_option,
			},
		)
	}
}

# Absolute URL and authority parsing.

parse_absolute : Str -> Try(Url, Url.ParseErr)
parse_absolute = |input| {
	scheme_parts = 
		match split_first(input, "://") {
			Found(parts) => Ok(parts)
			NotFound =>
				if Str.contains(input, ":") {
					Err(MissingAuthority)
				} else {
					Err(MissingScheme)
				}
			}?
	scheme = 
		match ascii_lower(scheme_parts.before) {
			"http" => Ok(Http)
			"https" => Ok(Https)
			other => Err(UnsupportedScheme(other))
		}?
	{ authority, suffix } = split_authority(scheme_parts.after)
	if Str.is_empty(authority) {
		Err(EmptyHost)
	} else if Str.contains(authority, "@") {
		Err(CredentialsNotAllowed)
	} else {
		parsed_authority = parse_authority(authority, scheme)?
		components = parse_suffix(suffix)?
		Ok(
			Url.{
				scheme,
				host: parsed_authority.host,
				port: parsed_authority.port,
				path: normalize_path(components.path),
				query: components.query,
				fragment: components.fragment,
			},
		)
	}
}

parse_authority : Str, [Http, Https] -> Try({ host : Str, port : [None, Some(U16)] }, Url.ParseErr)
parse_authority = |authority, scheme| {
	if starts_with(authority, "[") {
		match split_first(authority, "]") {
			NotFound => Err(InvalidIpv6(authority))
			Found({ before, after }) => {
				raw_ipv6 = drop_prefix(before, "[")
				host = validate_ipv6(raw_ipv6)?
				port = 
					if Str.is_empty(after) {
						Ok(None)
					} else if starts_with(after, ":") {
						parse_port(drop_prefix(after, ":"), scheme)
					} else {
						Err(InvalidIpv6(authority))
					}
				Ok({ host: Str.concat(Str.concat("[", host), "]"), port: port? })
			}
		}
	} else {
		{ raw_host, raw_port } = 
			match split_last(authority, ":") {
				Found({ before, after }) => { raw_host: before, raw_port: Some(after) }
				NotFound => { raw_host: authority, raw_port: None }
			}
		host = validate_host(raw_host)?
		port = 
			match raw_port {
				None => Ok(None)
				Some(raw) => parse_port(raw, scheme)
			}
		Ok({ host, port: port? })
	}
}

validate_host : Str -> Try(Str, Url.ParseErr)
validate_host = |raw_host| {
	if Str.is_empty(raw_host) {
		Err(EmptyHost)
	} else if List.any(Str.to_utf8(raw_host), |byte| byte > 127) {
		Err(InternationalHostUnsupported)
	} else if List.all(Str.to_utf8(raw_host), |byte| is_digit(byte) or byte == 46) {
		validate_ipv4(raw_host)
	} else {
		validate_dns_name(raw_host)
	}
}

validate_dns_name : Str -> Try(Str, [InvalidHost(Str)])
validate_dns_name = |raw_host| {
	host = ascii_lower(raw_host)
	labels = Str.split_on(host, ".")
	valid = 
		List.len(Str.to_utf8(host)) <= 253 and
			List.all(
				labels,
				|label| {
					bytes = Str.to_utf8(label)
					len = List.len(bytes)
					len > 0 and len <= 63 and
						is_alphanumeric(first_or_zero(bytes)) and
							is_alphanumeric(last_or_zero(bytes)) and
								List.all(bytes, |byte| is_alphanumeric(byte) or byte == 45)
				},
			)
	if valid {
		Ok(host)
	} else {
		Err(InvalidHost(raw_host))
	}
}

validate_ipv4 : Str -> Try(Str, [InvalidIpv4(Str)])
validate_ipv4 = |raw_host| {
	parts = Str.split_on(raw_host, ".")
	if List.len(parts) != 4 {
		Err(InvalidIpv4(raw_host))
	} else {
		match parse_ipv4_parts(parts, []) {
			Err(_) => Err(InvalidIpv4(raw_host))
			Ok(values) => Ok(Str.join_with(values.map(U64.to_str), "."))
		}
	}
}

parse_ipv4_parts : List(Str), List(U64) -> Try(List(U64), [BadIpv4Part])
parse_ipv4_parts = |parts, out|
	match parts {
		[] => Ok(out)
		[first, .. as rest] =>
			match parse_decimal(first) {
				Ok(value) =>
					if value <= 255 {
						parse_ipv4_parts(rest, out.append(value))
					} else {
						Err(BadIpv4Part)
					}
				Err(_) => Err(BadIpv4Part)
			}
		}

parse_port : Str, [Http, Https] -> Try([None, Some(U16)], [InvalidPort(Str), PortOutOfRange(U64)])
parse_port = |raw, scheme|
	match parse_decimal(raw) {
		Err(_) => Err(InvalidPort(raw))
		Ok(value) =>
			if value > 65535 {
				Err(PortOutOfRange(value))
			} else {
				port = U64.to_u16_wrap(value)
				is_default = 
					match scheme {
						Http => port == 80
						Https => port == 443
					}
				Ok(
					if is_default {
						None
					} else {
						Some(port)
					},
				)
			}
		}

parse_decimal : Str -> Try(U64, [NotDecimal])
parse_decimal = |raw| {
	bytes = Str.to_utf8(raw)
	if List.is_empty(bytes) or Bool.not(List.all(bytes, is_digit)) {
		Err(NotDecimal)
	} else {
		Ok(List.fold(bytes, 0, |acc, byte| acc * 10 + U8.to_u64(byte - 48)))
	}
}

# IPv6 parsing.
#
# Addresses are validated as eight hexadecimal groups, with at most one ::
# elision. IPv4-in-IPv6 syntax is outside this module's deliberately small
# subset. Serialization expands elided groups and removes leading zeroes.
validate_ipv6 : Str -> Try(Str, [InvalidIpv6(Str)])
validate_ipv6 = |raw| {
	pieces = Str.split_on(raw, "::")
	if List.len(pieces) > 2 {
		Err(InvalidIpv6(raw))
	} else if List.len(pieces) == 1 {
		groups = parse_ipv6_side(raw)?
		if List.len(groups) == 8 {
			Ok(serialize_ipv6(groups))
		} else {
			Err(InvalidIpv6(raw))
		}
	} else {
		left = parse_ipv6_side(get_or_empty(pieces, 0))?
		right = parse_ipv6_side(get_or_empty(pieces, 1))?
		count = List.len(left) + List.len(right)
		if count >= 8 {
			Err(InvalidIpv6(raw))
		} else {
			groups = List.concat(List.concat(left, List.repeat(0, 8 - count)), right)
			Ok(serialize_ipv6(groups))
		}
	}
}

parse_ipv6_side : Str -> Try(List(U16), [InvalidIpv6(Str)])
parse_ipv6_side = |raw|
	if Str.is_empty(raw) {
		Ok([])
	} else {
		parse_hex_groups(Str.split_on(raw, ":"), [])
	}

parse_hex_groups : List(Str), List(U16) -> Try(List(U16), [InvalidIpv6(Str)])
parse_hex_groups = |parts, out|
	match parts {
		[] => Ok(out)
		[first, .. as rest] => {
			bytes = Str.to_utf8(first)
			if List.is_empty(bytes) or List.len(bytes) > 4 or Bool.not(List.all(bytes, is_hex)) {
				Err(InvalidIpv6(first))
			} else {
				value = List.fold(bytes, 0, |acc, byte| acc * 16 + U8.to_u16(hex_value(byte)))
				parse_hex_groups(rest, out.append(value))
			}
		}
	}

serialize_ipv6 : List(U16) -> Str
serialize_ipv6 = |groups| Str.join_with(groups.map(u16_to_hex), ":")

u16_to_hex : U16 -> Str
u16_to_hex = |value|
	if value == 0 {
		"0"
	} else {
		u16_to_hex_help(value, [])
	}

u16_to_hex_help : U16, List(U8) -> Str
u16_to_hex_help = |value, digits| {
	next_digits = [lower_hex_digit_byte(U16.to_u8_wrap(value % 16))].concat(digits)
	next = value // 16
	if next == 0 {
		Str.from_utf8_lossy(next_digits)
	} else {
		u16_to_hex_help(next, next_digits)
	}
}

parse_suffix : Str -> Try({ fragment : [None, Some(Str)], path : Str, query : [None, Some(Str)] }, Url.ParseErr)
parse_suffix = |suffix| {
	{ before_fragment, fragment } = 
		match split_first(suffix, "#") {
			Found({ before, after }) => { before_fragment: before, fragment: Some(after) }
			NotFound => { before_fragment: suffix, fragment: None }
		}
	{ raw_path, query } = 
		match split_first(before_fragment, "?") {
			Found({ before, after }) => { raw_path: before, query: Some(after) }
			NotFound => { raw_path: before_fragment, query: None }
		}
	path_input = if Str.is_empty(raw_path) {
		"/"
	} else {
		raw_path
	}
	if Bool.not(starts_with(path_input, "/")) {
		Err(InvalidCharacter(first_or_zero(Str.to_utf8(path_input))))
	} else {
		path = validate_component(path_input, Path)?
		encoded_query = validate_optional(query, Query)?
		encoded_fragment = validate_optional(fragment, Fragment)?
		Ok({ path, query: encoded_query, fragment: encoded_fragment })
	}
}

validate_optional : [None, Some(Str)], [Fragment, Path, Query] -> Try([None, Some(Str)], Url.ParseErr)
validate_optional = |option, kind|
	match option {
		None => Ok(None)
		Some(raw) =>
			match validate_component(raw, kind) {
				Ok(value) => Ok(Some(value))
				Err(err) => Err(err)
			}
		}

validate_component : Str, [Fragment, Path, Query] -> Try(Str, Url.ParseErr)
validate_component = |raw, kind|
	match validate_component_help(Str.to_utf8(raw), kind, 0, []) {
		Ok(bytes) => Ok(Str.from_utf8_lossy(bytes))
		Err(err) => Err(err)
	}

validate_component_help : List(U8), [Fragment, Path, Query], U64, List(U8) -> Try(List(U8), Url.ParseErr)
validate_component_help = |bytes, kind, index, out| {
	if index >= List.len(bytes) {
		Ok(out)
	} else {
		byte = get_or_zero(bytes, index)
		if byte == 37 {
			if index + 2 >= List.len(bytes) or Bool.not(is_hex(get_or_zero(bytes, index + 1))) or Bool.not(is_hex(get_or_zero(bytes, index + 2))) {
				Err(InvalidPercentEncoding(index))
			} else {
				next = out.append(37)
					.append(ascii_upper_hex(get_or_zero(bytes, index + 1)))
					.append(ascii_upper_hex(get_or_zero(bytes, index + 2)))
				validate_component_help(bytes, kind, index + 3, next)
			}
		} else if byte > 127 {
			validate_component_help(bytes, kind, index + 1, append_percent_byte(out, byte))
		} else if is_forbidden(byte, kind) {
			Err(InvalidCharacter(byte))
		} else {
			validate_component_help(bytes, kind, index + 1, out.append(byte))
		}
	}
}

is_forbidden : U8, [Fragment, Path, Query] -> Bool
is_forbidden = |byte, kind| {
	common = byte <= 32 or byte == 127 or byte == 34 or byte == 60 or byte == 62 or byte == 92
	if common {
		True
	} else {
		match kind {
			Path => byte == 35 or byte == 63
			Query => byte == 35
			Fragment => False
		}
	}
}

# Relative-reference resolution and path normalization.

resolve_reference : Url, Str -> Try(Url, Url.ParseErr)
resolve_reference = |base, reference| {
	lower = ascii_lower(reference)
	if starts_with(lower, "http://") or starts_with(lower, "https://") {
		parse_absolute(reference)
	} else if Str.contains(reference, "://") or starts_with(reference, "//") {
		Err(MissingScheme)
	} else {
		relative = parse_relative(reference)?
		next_path = 
			if Str.is_empty(relative.path) {
				base.path
			} else if starts_with(relative.path, "/") {
				normalize_path(relative.path)
			} else {
				normalize_path(Str.concat(path_directory(base.path), relative.path))
			}
		next_query = 
			match relative.query {
				Some(value) => Some(value)
				None => if Str.is_empty(relative.path) {
					base.query
				} else {
					None
				}
			}
		Ok(
			Url.{
				scheme: base.scheme,
				host: base.host,
				port: base.port,
				path: next_path,
				query: next_query,
				fragment: relative.fragment,
			},
		)
	}
}

parse_relative : Str -> Try({ fragment : [None, Some(Str)], path : Str, query : [None, Some(Str)] }, Url.ParseErr)
parse_relative = |reference| {
	{ before_fragment, fragment } = 
		match split_first(reference, "#") {
			Found({ before, after }) => { before_fragment: before, fragment: Some(after) }
			NotFound => { before_fragment: reference, fragment: None }
		}
	{ raw_path, query } = 
		match split_first(before_fragment, "?") {
			Found({ before, after }) => { raw_path: before, query: Some(after) }
			NotFound => { raw_path: before_fragment, query: None }
		}
	path = validate_component(raw_path, Path)?
	encoded_query = validate_optional(query, Query)?
	encoded_fragment = validate_optional(fragment, Fragment)?
	Ok({ path, query: encoded_query, fragment: encoded_fragment })
}

normalize_path : Str -> Str
normalize_path = |path_str| {
	rooted = if starts_with(path_str, "/") {
		path_str
	} else {
		Str.concat("/", path_str)
	}
	trailing = ends_with(rooted, "/") or ends_with(rooted, "/.") or ends_with(rooted, "/..")
	normalized = normalize_segments(Str.split_on(rooted, "/"), [])
	joined = Str.concat("/", Str.join_with(normalized, "/"))
	if trailing and joined != "/" {
		Str.concat(joined, "/")
	} else {
		joined
	}
}

normalize_segments : List(Str), List(Str) -> List(Str)
normalize_segments = |segments, out|
	match segments {
		[] => out
		["", .. as rest] => normalize_segments(rest, out)
		[".", .. as rest] => normalize_segments(rest, out)
		["..", .. as rest] => normalize_segments(rest, List.drop_last(out, 1))
		[first, .. as rest] => normalize_segments(rest, out.append(first))
	}

path_directory : Str -> Str
path_directory = |path_str| {
	parts = Str.split_on(path_str, "/")
	if List.len(parts) <= 2 {
		"/"
	} else {
		Str.concat(Str.join_with(List.drop_last(parts, 1), "/"), "/")
	}
}

serialize : Url, Bool -> Str
serialize = |url, include_fragment| {
	scheme_str = 
		match url.scheme {
			Http => "http"
			Https => "https"
		}
	port_str = 
		match url.port {
			None => ""
			Some(value) => Str.concat(":", U16.to_str(value))
		}
	query_str = 
		match url.query {
			None => ""
			Some(value) => Str.concat("?", value)
		}
	fragment_str = 
		if include_fragment {
			match url.fragment {
				None => ""
				Some(value) => Str.concat("#", value)
			}
		} else {
			""
		}
	Str.concat(
		Str.concat(
			Str.concat(
				Str.concat(
					Str.concat(Str.concat(scheme_str, "://"), url.host),
					port_str,
				),
				url.path,
			),
			query_str,
		),
		fragment_str,
	)
}

# Percent encoding and application/x-www-form-urlencoded query handling.

percent_encode : Str -> Str
percent_encode = |input|
	Str.from_utf8_lossy(
		List.fold(
			Str.to_utf8(input),
			[],
			|out, byte|
				if is_unreserved(byte) {
					out.append(byte)
				} else {
					append_percent_byte(out, byte)
				},
		),
	)

form_encode : Str -> Str
form_encode = |input|
	Str.from_utf8_lossy(
		List.fold(
			Str.to_utf8(input),
			[],
			|out, byte|
				if byte == 32 {
					out.append(43)
				} else if is_form_unescaped(byte) {
					out.append(byte)
				} else {
					append_percent_byte(out, byte)
				},
		),
	)

form_decode : Str -> Str
form_decode = |input| Str.from_utf8_lossy(form_decode_help(Str.to_utf8(input), 0, []))

form_decode_help : List(U8), U64, List(U8) -> List(U8)
form_decode_help = |bytes, index, out| {
	if index >= List.len(bytes) {
		out
	} else {
		byte = get_or_zero(bytes, index)
		if byte == 43 {
			form_decode_help(bytes, index + 1, out.append(32))
		} else if byte == 37 and index + 2 < List.len(bytes) and is_hex(get_or_zero(bytes, index + 1)) and is_hex(get_or_zero(bytes, index + 2)) {
			decoded = hex_value(get_or_zero(bytes, index + 1)) * 16 + hex_value(get_or_zero(bytes, index + 2))
			form_decode_help(bytes, index + 3, out.append(decoded))
		} else {
			form_decode_help(bytes, index + 1, out.append(byte))
		}
	}
}

# Small string and byte helpers. Keeping these local avoids depending on host
# code or exposing parser implementation details through the public API.

split_authority : Str -> { authority : Str, suffix : Str }
split_authority = |after_scheme| {
	bytes = Str.to_utf8(after_scheme)
	index = first_delimiter(bytes, 0)
	authority = Str.from_utf8_lossy(List.sublist(bytes, { start: 0, len: index }))
	suffix = Str.from_utf8_lossy(List.sublist(bytes, { start: index, len: List.len(bytes) - index }))
	{ authority, suffix }
}

first_delimiter : List(U8), U64 -> U64
first_delimiter = |bytes, index| {
	if index >= List.len(bytes) {
		index
	} else {
		byte = get_or_zero(bytes, index)
		if byte == 47 or byte == 63 or byte == 35 {
			index
		} else {
			first_delimiter(bytes, index + 1)
		}
	}
}

parse_err_to_str : Url.ParseErr -> Str
parse_err_to_str = |err|
	match err {
		CredentialsNotAllowed => "URL credentials are not supported"
		EmptyHost => "URL host is empty"
		InternationalHostUnsupported => "URL host must be ASCII; use its Punycode form"
		InvalidCharacter(byte) => Str.concat("URL contains invalid byte ", U8.to_str(byte))
		InvalidHost(host) => Str.concat("Invalid URL host: ", host)
		InvalidIpv4(host) => Str.concat("Invalid IPv4 address: ", host)
		InvalidIpv6(host) => Str.concat("Invalid IPv6 address: ", host)
		InvalidPercentEncoding(index) => Str.concat("Invalid percent escape at byte ", U64.to_str(index))
		InvalidPort(port) => Str.concat("Invalid URL port: ", port)
		MissingAuthority => "URL must contain :// after its scheme"
		MissingScheme => "URL must start with http:// or https://"
		PortOutOfRange(port) => Str.concat("URL port is out of range: ", U64.to_str(port))
		UnsupportedScheme(scheme) => Str.concat("Unsupported URL scheme: ", scheme)
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

ascii_upper_hex : U8 -> U8
ascii_upper_hex = |byte|
	if byte >= 97 and byte <= 102 {
		byte - 32
	} else {
		byte
	}

is_unreserved : U8 -> Bool
is_unreserved = |byte| is_alphanumeric(byte) or byte == 45 or byte == 46 or byte == 95 or byte == 126

is_form_unescaped : U8 -> Bool
is_form_unescaped = |byte| is_alphanumeric(byte) or byte == 42 or byte == 45 or byte == 46 or byte == 95

is_alphanumeric : U8 -> Bool
is_alphanumeric = |byte| is_digit(byte) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

is_digit : U8 -> Bool
is_digit = |byte| byte >= 48 and byte <= 57

is_hex : U8 -> Bool
is_hex = |byte| is_digit(byte) or (byte >= 65 and byte <= 70) or (byte >= 97 and byte <= 102)

hex_value : U8 -> U8
hex_value = |byte|
	if byte <= 57 {
		byte - 48
	} else if byte <= 70 {
		byte - 55
	} else {
		byte - 87
	}

append_percent_byte : List(U8), U8 -> List(U8)
append_percent_byte = |out, byte|
	out.append(37).append(hex_digit_byte(byte // 16)).append(hex_digit_byte(byte % 16))

hex_digit_byte : U8 -> U8
hex_digit_byte = |value|
	if value < 10 {
		value + 48
	} else {
		value + 55
	}

lower_hex_digit_byte : U8 -> U8
lower_hex_digit_byte = |value|
	if value < 10 {
		value + 48
	} else {
		value + 87
	}

get_or_zero : List(U8), U64 -> U8
get_or_zero = |list, index|
	match list.get(index) {
		Ok(value) => value
		Err(_) => 0
	}

get_or_empty : List(Str), U64 -> Str
get_or_empty = |list, index|
	match list.get(index) {
		Ok(value) => value
		Err(_) => ""
	}

first_or_zero : List(U8) -> U8
first_or_zero = |list| get_or_zero(list, 0)

last_or_zero : List(U8) -> U8
last_or_zero = |list|
	if List.is_empty(list) {
		0
	} else {
		get_or_zero(list, List.len(list) - 1)
	}

trim_brackets : Str -> Str
trim_brackets = |str| {
	bytes = Str.to_utf8(str)
	if List.len(bytes) < 2 {
		""
	} else {
		Str.from_utf8_lossy(List.sublist(bytes, { start: 1, len: List.len(bytes) - 2 }))
	}
}

starts_with : Str, Str -> Bool
starts_with = |str, prefix|
	if Str.is_empty(prefix) {
		True
	} else {
		match split_first(str, prefix) {
			Found({ before, after: _ }) => Str.is_empty(before)
			NotFound => False
		}
	}

ends_with : Str, Str -> Bool
ends_with = |str, suffix| {
	if Str.is_empty(suffix) {
		True
	} else {
		parts = Str.split_on(str, suffix)
		match parts.get(List.len(parts) - 1) {
			Ok(last) => Str.is_empty(last)
			Err(_) => False
		}
	}
}

drop_prefix : Str, Str -> Str
drop_prefix = |str, prefix| {
	parts = Str.split_on(str, prefix)
	Str.join_with(List.drop_first(parts, 1), prefix)
}

split_first : Str, Str -> [Found({ after : Str, before : Str }), NotFound]
split_first = |str, separator| {
	parts = Str.split_on(str, separator)
	if List.len(parts) > 1 {
		match parts.get(0) {
			Ok(before) => Found({ before, after: Str.join_with(List.drop_first(parts, 1), separator) })
			Err(_) => NotFound
		}
	} else {
		NotFound
	}
}

split_last : Str, Str -> [Found({ after : Str, before : Str }), NotFound]
split_last = |str, separator| {
	parts = Str.split_on(str, separator)
	if List.len(parts) > 1 {
		match parts.get(List.len(parts) - 1) {
			Ok(after) => Found({ before: Str.join_with(List.drop_last(parts, 1), separator), after })
			Err(_) => NotFound
		}
	} else {
		NotFound
	}
}

# The parsing cases below are a curated strict HTTP/HTTPS subset informed by
# web-platform-tests/url/resources/urltestdata.json at WPT commit
# dc97e7bed3096ac9e0e591ab5fa22e7fb8844ead (BSD-3-Clause).

expect
	match Url.parse("HTTP://Example.COM:80/a/../b") {
		Ok(url) => Url.to_str(url) == "http://example.com/b"
		Err(_) => False
	}

expect
	match Url.parse("https://example.com:443") {
		Ok(url) => Url.scheme(url) == Https and Url.host(url) == "example.com" and Url.port(url) == None and Url.path(url) == "/"
		Err(_) => False
	}

expect
	match Url.parse("https://127.000.000.001:8443/") {
		Ok(url) => Url.to_str(url) == "https://127.0.0.1:8443/"
		Err(_) => False
	}

expect
	match Url.parse("http://[::1]:8080/") {
		Ok(url) => Url.host(url) == "0:0:0:0:0:0:0:1" and Url.to_str(url) == "http://[0:0:0:0:0:0:0:1]:8080/"
		Err(_) => False
	}

expect
	match Url.parse("https://example.com/café?q=naïve#résumé") {
		Ok(url) => Url.to_str(url) == "https://example.com/caf%C3%A9?q=na%C3%AFve#r%C3%A9sum%C3%A9"
		Err(_) => False
	}

expect
	match Url.parse("https://example.com/%7euser") {
		Ok(url) => Url.to_str(url) == "https://example.com/%7Euser"
		Err(_) => False
	}

expect Url.parse("example.com") == Err(MissingScheme)

expect Url.parse("mailto:user@example.com") == Err(MissingAuthority)

expect Url.parse("ftp://example.com") == Err(UnsupportedScheme("ftp"))

expect Url.parse("https://user:secret@example.com") == Err(CredentialsNotAllowed)

expect Url.parse("https://münich.example") == Err(InternationalHostUnsupported)

expect Url.parse("https://") == Err(EmptyHost)

expect Url.parse("https://-example.com") == Err(InvalidHost("-example.com"))

expect Url.parse("https://example..com") == Err(InvalidHost("example..com"))

expect Url.parse("https://127.0.0.256") == Err(InvalidIpv4("127.0.0.256"))

expect Url.parse("https://127.0.0") == Err(InvalidIpv4("127.0.0"))

expect
	match Url.parse("https://[:::1]") {
		Err(InvalidIpv6(_)) => True
		_ => False
	}

expect Url.parse("https://example.com:wat") == Err(InvalidPort("wat"))

expect Url.parse("https://example.com:70000") == Err(PortOutOfRange(70000))

expect Url.parse("https://example.com/%zz") == Err(InvalidPercentEncoding(1))

expect Url.parse("https://example.com/a b") == Err(InvalidCharacter(32))

expect Url.parse("https://example.com/a\\b") == Err(InvalidCharacter(92))

expect
	match Url.parse("https://example.com/?#") {
		Ok(url) => Url.query(url) == Some("") and Url.fragment(url) == Some("")
		Err(_) => False
	}

expect
	match Url.parse("https://example.com/") {
		Err(_) => False
		Ok(url) => {
			with_path = Url.append_path_segments(url, ["a/b", "café"])
			with_first = Url.append_query_param(with_path, "tag", "one")
			built = Url.append_query_param(with_first, "tag", "two words")
			Url.to_str(built) == "https://example.com/a%2Fb/caf%C3%A9?tag=one&tag=two+words" and
				Url.query_pairs(built) == [("tag", "one"), ("tag", "two words")]
		}
	}

expect
	match Url.parse("https://example.com/a/b?old=1#old") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "../c?new=2#fresh") {
				Ok(resolved) => Url.to_str(resolved) == "https://example.com/c?new=2#fresh"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a/b?old=1#old") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "?new=2") {
				Ok(resolved) => Url.to_str(resolved) == "https://example.com/a/b?new=2"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a/b?old=1") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "#fresh") {
				Ok(resolved) => Url.to_str(resolved) == "https://example.com/a/b?old=1#fresh"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a/b") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "/root/./x/../y") {
				Ok(resolved) => Url.to_str(resolved) == "https://example.com/root/y"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a?x=1#frag") {
		Err(_) => False
		Ok(url) => Url.to_str(Url.without_fragment(url)) == "https://example.com/a?x=1"
	}

expect
	match Url.from_quote("https://example.com") {
		Ok(url) => Url.to_str(url) == "https://example.com/"
		Err(_) => False
	}

expect
	match Url.parse("http://localhost:0/a/./b/../../c/") {
		Ok(url) => Url.port(url) == Some(0) and Url.to_str(url) == "http://localhost:0/c/"
		Err(_) => False
	}

expect
	match Url.parse("https://example.com:65535") {
		Ok(url) => Url.port(url) == Some(65535) and Url.to_str(url) == "https://example.com:65535/"
		Err(_) => False
	}

expect Url.parse("https://example.com:") == Err(InvalidPort(""))

expect Url.parse("https://example.com:65536") == Err(PortOutOfRange(65536))

expect Url.parse("https://example_com") == Err(InvalidHost("example_com"))

expect Url.parse("https://example.com.") == Err(InvalidHost("example.com."))

expect
	match Url.parse("http://[2001:0DB8:0000:0000:0000:ff00:0042:8329]/") {
		Ok(url) => Url.host(url) == "2001:db8:0:0:0:ff00:42:8329" and Url.to_str(url) == "http://[2001:db8:0:0:0:ff00:42:8329]/"
		Err(_) => False
	}

expect
	match Url.parse("http://[::]/") {
		Ok(url) => Url.host(url) == "0:0:0:0:0:0:0:0"
		Err(_) => False
	}

expect
	match Url.parse("http://[1:2:3:4:5:6:7]/") {
		Err(InvalidIpv6(_)) => True
		_ => False
	}

expect
	match Url.parse("http://[1:2:3:4:5:6:7:8:9]/") {
		Err(InvalidIpv6(_)) => True
		_ => False
	}

expect
	match Url.parse("http://[::ffff:192.0.2.1]/") {
		Err(InvalidIpv6(_)) => True
		_ => False
	}

expect
	match Url.parse("https://example.com/a/%2f/%aa") {
		Ok(url) => Url.path(url) == "/a/%2F/%AA"
		Err(_) => False
	}

expect Url.parse("https://example.com/%") == Err(InvalidPercentEncoding(1))

expect Url.parse("https://example.com/%0") == Err(InvalidPercentEncoding(1))

expect Url.parse("https://example.com/<unsafe>") == Err(InvalidCharacter(60))

expect
	match Url.parse("https://example.com/path?reserved=%23%26/?#fragment/?") {
		Ok(url) =>
			Url.path(url) == "/path" and
				Url.query(url) == Some("reserved=%23%26/?") and
					Url.fragment(url) == Some("fragment/?")
		Err(_) => False
	}

expect
	match Url.parse("https://example.com/?name=Roc+Lang&letter=%C3%A9&flag&name=again") {
		Ok(url) => Url.query_pairs(url) == [("name", "Roc Lang"), ("letter", "é"), ("flag", ""), ("name", "again")]
		Err(_) => False
	}

expect
	match Url.parse("https://example.com/?") {
		Ok(url) => Url.query_pairs(url) == []
		Err(_) => False
	}

expect
	match Url.parse("https://example.com/base?old=1#frag") {
		Err(_) => False
		Ok(url) => {
			appended = Url.append_path_segments(url, ["space here", "?and#"])
			Url.to_str(appended) == "https://example.com/base/space%20here/%3Fand%23?old=1#frag"
		}
	}

expect
	match Url.parse("https://example.com/base") {
		Err(_) => False
		Ok(url) => Url.append_path_segments(url, []) == url
	}

expect
	match Url.parse("https://example.com/path?old=1#frag") {
		Err(_) => False
		Ok(url) =>
			match Url.with_query(url, None) {
				Ok(changed) => Url.to_str(changed) == "https://example.com/path#frag"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/path") {
		Err(_) => False
		Ok(url) =>
			match Url.with_query(url, Some("term=café&empty=")) {
				Ok(changed) => Url.to_str(changed) == "https://example.com/path?term=caf%C3%A9&empty="
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/path") {
		Err(_) => False
		Ok(url) => Url.with_query(url, Some("bad#query")) == Err(InvalidCharacter(35))
	}

expect
	match Url.parse("https://example.com/path#old") {
		Err(_) => False
		Ok(url) =>
			match Url.with_fragment(url, None) {
				Ok(changed) => Url.to_str(changed) == "https://example.com/path"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/path") {
		Err(_) => False
		Ok(url) =>
			match Url.with_fragment(url, Some("résumé/?")) {
				Ok(changed) => Url.to_str(changed) == "https://example.com/path#r%C3%A9sum%C3%A9/?"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/path") {
		Err(_) => False
		Ok(url) => Url.with_fragment(url, Some("bad\\fragment")) == Err(InvalidCharacter(92))
	}

expect
	match Url.parse("https://example.com/a/b?old=1#old") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "") {
				Ok(resolved) => Url.to_str(resolved) == "https://example.com/a/b?old=1"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a/b") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "../../../root") {
				Ok(resolved) => Url.to_str(resolved) == "https://example.com/root"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a/b") {
		Err(_) => False
		Ok(base) =>
			match Url.resolve(base, "HTTP://Other.EXAMPLE:80/x") {
				Ok(resolved) => Url.to_str(resolved) == "http://other.example/x"
				Err(_) => False
			}
		}

expect
	match Url.parse("https://example.com/a/b") {
		Err(_) => False
		Ok(base) => Url.resolve(base, "//other.example/x") == Err(MissingScheme)
	}

expect
	match Url.parse("https://example.com/a/b") {
		Err(_) => False
		Ok(base) => Url.resolve(base, "ftp://other.example/x") == Err(MissingScheme)
	}

expect
	match Url.from_quote("not a url") {
		Err(BadQuotedBytes(message)) => Str.contains(message, "http:// or https://")
		Ok(_) => False
	}

## Inspection uses the canonical URL and identifies the nominal type.
expect
	match Url.parse("HTTPS://EXAMPLE.COM:443/a") {
		Ok(url) => Str.inspect(url) == "Url(\"https://example.com/a\")"
		Err(_) => False
	}

## Canonically equivalent URLs compare and hash identically.
expect
	match (Url.parse("HTTPS://EXAMPLE.COM:443/a"), Url.parse("https://example.com/a")) {
		(Ok(stored), Ok(lookup)) => stored == lookup and Dict.single(stored, "found").get(lookup) == Ok("found")
		_ => False
	}

## Generic encoders represent URLs as canonical strings.
expect {
	url : Url
	url = "https://example.com/a?q=roc"
	Json.to_str(url) == "\"https://example.com/a?q=roc\""
}

## Generic parsers validate and canonicalize encoded URL strings.
expect {
	decoded : Try(Url, [InvalidJson(Str)])
	decoded = Json.parse("\"HTTPS://EXAMPLE.COM:443/a\"")

	match decoded {
		Ok(url) => Url.to_str(url) == "https://example.com/a"
		Err(_) => False
	}
}

expect {
	decoded : Try(Url, [InvalidJson(Str)])
	decoded = Json.parse("\"not a url\"")
	decoded == Err(Json.invalid_json)
}
