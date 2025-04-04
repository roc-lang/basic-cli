module [
    Url,
    append,
    from_str,
    to_str,
    append_param,
    has_query,
    has_fragment,
    query,
    fragment,
    reserve,
    with_query,
    with_fragment,
    query_params,
    path,
]

## A [Uniform Resource Locator](https://en.wikipedia.org/wiki/URL).
##
## It could be an absolute address, such as `https://roc-lang.org/authors` or
## a relative address, such as `/authors`. You can create one using [Url.from_str].
Url := Str implements [Inspect]

## Reserve the given number of bytes as extra capacity. This can avoid reallocation
## when calling multiple functions that increase the length of the URL.
##
## The following example reserves 50 bytes, then builds the url `https://example.com/stuff?caf%C3%A9=du%20Monde&email=hi%40example.com`;
## ```
## Url.from_str("https://example.com")
## |> Url.reserve(50)
## |> Url.append("stuff")
## |> Url.append_param("café", "du Monde")
## |> Url.append_param("email", "hi@example.com")
## ```
## The [Str.count_utf8_bytes](https://www.roc-lang.org/builtins/Str#count_utf8_bytes) function can be helpful in finding out how many bytes to reserve.
##
## There is no `Url.with_capacity` because it's better to reserve extra capacity
## on a [Str] first, and then pass that string to [Url.from_str]. This function will make use
## of the extra capacity.
reserve : Url, U64 -> Url
reserve = |@Url(str), cap|
    @Url(Str.reserve(str, Num.int_cast(cap)))

## Create a [Url] without validating or [percent-encoding](https://en.wikipedia.org/wiki/Percent-encoding)
## anything.
##
## ```
## Url.from_str("https://example.com#stuff")
## ```
##
## URLs can be absolute, like `https://example.com`, or they can be relative, like `/blah`.
##
## ```
## Url.from_str("/this/is#relative")
## ```
##
## Since nothing is validated, this can return invalid URLs.
##
## ```
## Url.from_str("https://this is not a valid URL, not at all!")
## ```
##
## Naturally, passing invalid URLs to functions that need valid ones will tend to result in errors.
##
from_str : Str -> Url
from_str = |str| @Url(str)

## Return a [Str] representation of this URL.
## ```
## # Gives "https://example.com/two%20words"
## Url.from_str("https://example.com")
## |> Url.append("two words")
## |> Url.to_str
## ```
to_str : Url -> Str
to_str = |@Url(str)| str

## [Percent-encodes](https://en.wikipedia.org/wiki/Percent-encoding) a
## [path component](https://en.wikipedia.org/wiki/Uniform_Resource_Identifier#Syntax)
## and appends to the end of the URL's path.
##
## This will be appended before any queries and fragments. If the given path string begins with `/` and the URL already ends with `/`, one
## will be ignored. This avoids turning a single slash into a double slash. If either the given URL or the given string is empty, no `/` will be added.
##
## ```
## # Gives https://example.com/some%20stuff
## Url.from_str("https://example.com")
## |> Url.append("some stuff")
##
## # Gives https://example.com/stuff?search=blah#fragment
## Url.from_str("https://example.com?search=blah#fragment")
## |> Url.append("stuff")
##
## # Gives https://example.com/things/stuff/more/etc/"
## Url.from_str "https://example.com/things/"
## |> Url.append("/stuff/")
## |> Url.append("/more/etc/")
##
## # Gives https://example.com/things
## Url.from_str("https://example.com/things")
## |> Url.append("")
## ```
append : Url, Str -> Url
append = |@Url(url_str), suffix_unencoded|
    suffix = percent_encode(suffix_unencoded)

    when Str.split_first(url_str, "?") is
        Ok({ before, after }) ->
            bytes =
                Str.count_utf8_bytes(before)
                + 1 # for "/"
                + Str.count_utf8_bytes(suffix)
                + 1 # for "?"
                + Str.count_utf8_bytes(after)

            before
            |> Str.reserve(bytes)
            |> append_help(suffix)
            |> Str.concat("?")
            |> Str.concat(after)
            |> @Url

        Err(NotFound) ->
            # There wasn't a query, but there might still be a fragment
            when Str.split_first(url_str, "#") is
                Ok({ before, after }) ->
                    bytes =
                        Str.count_utf8_bytes(before)
                        + 1 # for "/"
                        + Str.count_utf8_bytes(suffix)
                        + 1 # for "#"
                        + Str.count_utf8_bytes(after)

                    before
                    |> Str.reserve(bytes)
                    |> append_help(suffix)
                    |> Str.concat("#")
                    |> Str.concat(after)
                    |> @Url

                Err(NotFound) ->
                    # No query and no fragment, so just append it
                    @Url(append_help(url_str, suffix))

## Internal helper
append_help : Str, Str -> Str
append_help = |prefix, suffix|
    if Str.ends_with(prefix, "/") then
        if Str.starts_with(suffix, "/") then
            # Avoid a double-slash by appending only the part of the suffix after the "/"
            when Str.split_first(suffix, "/") is
                Ok({ after }) ->
                    # TODO `expect before == ""`
                    Str.concat(prefix, after)

                Err(NotFound) ->
                    # This should never happen, because we already verified
                    # that the suffix starts_with "/"
                    # TODO `expect Bool.false` here with a comment
                    Str.concat(prefix, suffix)
        else
            # prefix ends with "/" but suffix doesn't start with one, so just append.
            Str.concat(prefix, suffix)
    else if Str.starts_with(suffix, "/") then
        # Suffix starts with "/" but prefix doesn't end with one, so just append them.
        Str.concat(prefix, suffix)
    else if Str.is_empty(prefix) then
        # Prefix is empty; return suffix.
        suffix
    else if Str.is_empty(suffix) then
        # Suffix is empty; return prefix.
        prefix
    else
        # Neither is empty, but neither has a "/", so add one in between.
        prefix
        |> Str.concat("/")
        |> Str.concat(suffix)

## Internal helper. This is intentionally unexposed so that you don't accidentally
## double-encode things. If you really want to percent-encode an arbitrary string,
## you can always do:
##
## ```
## Url.from_str("")
## |> Url.append(my_str_to_encode)
## |> Url.to_str
## ```
##
## > It is recommended to encode spaces as `%20`, the HTML 2.0 specification
## suggests that these can be encoded as `+`, however this is not always safe to
## use. See [this stackoverflow discussion](https://stackoverflow.com/questions/2678551/when-should-space-be-encoded-to-plus-or-20/47188851#47188851)
## for a detailed explanation.
percent_encode : Str -> Str
percent_encode = |input|
    # Optimistically assume we won't need any percent encoding, and can have
    # the same capacity as the input string. If we're wrong, it will get doubled.
    initial_output = List.with_capacity((Str.count_utf8_bytes(input) |> Num.int_cast))

    answer =
        List.walk(
            Str.to_utf8(input),
            initial_output,
            |output, byte|
                # Spec for percent-encoding: https://www.ietf.org/rfc/rfc3986.txt
                if
                    (byte >= 97 and byte <= 122) # lowercase ASCII
                    or (byte >= 65 and byte <= 90) # uppercase ASCII
                    or (byte >= 48 and byte <= 57) # digit
                then
                    # This is the most common case: an unreserved character,
                    # which needs no encoding in a path
                    List.append(output, byte)
                else
                    when byte is
                        46 # '.'
                        | 95 # '_'
                        | 126 # '~'
                        | 150 -> # '-'
                            # These special characters can all be unescaped in paths
                            List.append(output, byte)

                        _ ->
                            # This needs encoding in a path
                            suffix =
                                Str.to_utf8(percent_encoded)
                                |> List.sublist({ len: 3, start: 3 * Num.int_cast(byte) })

                            List.concat(output, suffix),
        )

    Str.from_utf8(answer)
    |> Result.with_default("") # This should never fail

## Adds a [Str] query parameter to the end of the [Url].
##
## The key and value both get [percent-encoded](https://en.wikipedia.org/wiki/Percent-encoding).
##
## ```
## # Gives https://example.com?email=someone%40example.com
## Url.from_str("https://example.com")
## |> Url.append_param("email", "someone@example.com")
## ```
##
## This can be called multiple times on the same URL.
##
## ```
## # Gives https://example.com?caf%C3%A9=du%20Monde&email=hi%40example.com
## Url.from_str("https://example.com")
## |> Url.append_param("café", "du Monde")
## |> Url.append_param("email", "hi@example.com")
## ```
##
append_param : Url, Str, Str -> Url
append_param = |@Url(url_str), key, value|
    { without_fragment, after_query } =
        when Str.split_last(url_str, "#") is
            Ok({ before, after }) ->
                # The fragment is almost certainly going to be a small string,
                # so this interpolation should happen on the stack.
                { without_fragment: before, after_query: "#${after}" }

            Err(NotFound) ->
                { without_fragment: url_str, after_query: "" }

    encoded_key = percent_encode(key)
    encoded_value = percent_encode(value)

    bytes =
        Str.count_utf8_bytes(without_fragment)
        + 1 # for "?" or "&"
        + Str.count_utf8_bytes(encoded_key)
        + 1 # for "="
        + Str.count_utf8_bytes(encoded_value)
        + Str.count_utf8_bytes(after_query)

    without_fragment
    |> Str.reserve(bytes)
    |> Str.concat((if has_query(@Url(without_fragment)) then "&" else "?"))
    |> Str.concat(encoded_key)
    |> Str.concat("=")
    |> Str.concat(encoded_value)
    |> Str.concat(after_query)
    |> @Url

## Replaces the URL's [query](https://en.wikipedia.org/wiki/URL#Syntax)—the part
## after the `?`, if it has one, but before any `#` it might have.
##
## Passing `""` removes the `?` (if there was one).
##
## ```
## # Gives https://example.com?newQuery=thisRightHere#stuff
## Url.from_str("https://example.com?key1=val1&key2=val2#stuff")
## |> Url.with_query("newQuery=thisRightHere")
##
## # Gives https://example.com#stuff
## Url.from_str("https://example.com?key1=val1&key2=val2#stuff")
## |> Url.with_query("")
## ```
with_query : Url, Str -> Url
with_query = |@Url(url_str), query_str|
    { without_fragment, after_query } =
        when Str.split_last(url_str, "#") is
            Ok({ before, after }) ->
                # The fragment is almost certainly going to be a small string,
                # so this interpolation should happen on the stack.
                { without_fragment: before, after_query: "#${after}" }

            Err(NotFound) ->
                { without_fragment: url_str, after_query: "" }

    before_query =
        when Str.split_last(without_fragment, "?") is
            Ok({ before }) -> before
            Err(NotFound) -> without_fragment

    if Str.is_empty(query_str) then
        @Url(Str.concat(before_query, after_query))
    else
        bytes =
            Str.count_utf8_bytes(before_query)
            + 1 # for "?"
            + Str.count_utf8_bytes(query_str)
            + Str.count_utf8_bytes(after_query)

        before_query
        |> Str.reserve(bytes)
        |> Str.concat("?")
        |> Str.concat(query_str)
        |> Str.concat(after_query)
        |> @Url

## Returns the URL's [query](https://en.wikipedia.org/wiki/URL#Syntax)—the part after
## the `?`, if it has one, but before any `#` it might have.
##
## Returns `""` if the URL has no query.
##
## ```
## # Gives "key1=val1&key2=val2&key3=val3"
## Url.from_str("https://example.com?key1=val1&key2=val2&key3=val3#stuff")
## |> Url.query
##
## # Gives ""
## Url.from_str("https://example.com#stuff")
## |> Url.query
## ```
##
query : Url -> Str
query = |@Url(url_str)|
    without_fragment =
        when Str.split_last(url_str, "#") is
            Ok({ before }) -> before
            Err(NotFound) -> url_str

    when Str.split_last(without_fragment, "?") is
        Ok({ after }) -> after
        Err(NotFound) -> ""

## Returns [Bool.true] if the URL has a `?` in it.
##
## ```
## # Gives Bool.true
## Url.from_str("https://example.com?key=value#stuff")
## |> Url.has_query
##
## # Gives Bool.false
## Url.from_str("https://example.com#stuff")
## |> Url.has_query
## ```
##
has_query : Url -> Bool
has_query = |@Url(url_str)|
    Str.contains(url_str, "?")

## Returns the URL's [fragment](https://en.wikipedia.org/wiki/URL#Syntax)—the part after
## the `#`, if it has one.
##
## Returns `""` if the URL has no fragment.
##
## ```
## # Gives "stuff"
## Url.from_str("https://example.com#stuff")
## |> Url.fragment
##
## # Gives ""
## Url.from_str("https://example.com")
## |> Url.fragment
## ```
##
fragment : Url -> Str
fragment = |@Url(url_str)|
    when Str.split_last(url_str, "#") is
        Ok({ after }) -> after
        Err(NotFound) -> ""

## Replaces the URL's [fragment](https://en.wikipedia.org/wiki/URL#Syntax).
##
## If the URL didn't have a fragment, adds one. Passing `""` removes the fragment.
##
## ```
## # Gives https://example.com#things
## Url.from_str("https://example.com#stuff")
## |> Url.with_fragment("things")
##
## # Gives https://example.com#things
## Url.from_str("https://example.com")
## |> Url.with_fragment("things")
##
## # Gives https://example.com
## Url.from_str("https://example.com#stuff")
## |> Url.with_fragment ""
## ```
##
with_fragment : Url, Str -> Url
with_fragment = |@Url(url_str), fragment_str|
    when Str.split_last(url_str, "#") is
        Ok({ before }) ->
            if Str.is_empty(fragment_str) then
                # If the given fragment is empty, remove the URL's fragment
                @Url(before)
            else
                # Replace the URL's old fragment with this one, discarding `after`
                @Url("${before}#${fragment_str}")

        Err(NotFound) ->
            if Str.is_empty(fragment_str) then
                # If the given fragment is empty, leave the URL as having no fragment
                @Url(url_str)
            else
                # The URL didn't have a fragment, so give it this one
                @Url("${url_str}#${fragment_str}")

## Returns [Bool.true] if the URL has a `#` in it.
##
## ```
## # Gives Bool.true
## Url.from_str("https://example.com?key=value#stuff")
## |> Url.has_fragment
##
## # Gives Bool.false
## Url.from_str("https://example.com?key=value")
## |> Url.has_fragment
## ```
##
has_fragment : Url -> Bool
has_fragment = |@Url(url_str)|
    Str.contains(url_str, "#")

# Adapted from the percent-encoding crate, © The rust-url developers, Apache2-licensed
#
# https://github.com/servo/rust-url/blob/e12d76a61add5bc09980599c738099feaacd1d0d/percent_encoding/src/lib.rs#L183
percent_encoded : Str
percent_encoded = "%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F%20%21%22%23%24%25%26%27%28%29%2A%2B%2C%2D%2E%2F%30%31%32%33%34%35%36%37%38%39%3A%3B%3C%3D%3E%3F%40%41%42%43%44%45%46%47%48%49%4A%4B%4C%4D%4E%4F%50%51%52%53%54%55%56%57%58%59%5A%5B%5C%5D%5E%5F%60%61%62%63%64%65%66%67%68%69%6A%6B%6C%6D%6E%6F%70%71%72%73%74%75%76%77%78%79%7A%7B%7C%7D%7E%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FF"

query_params : Url -> Dict Str Str
query_params = |url|
    query(url)
    |> Str.split_on("&")
    |> List.walk(
        Dict.empty({}),
        |dict, pair|
            when Str.split_first(pair, "=") is
                Ok({ before, after }) -> Dict.insert(dict, before, after)
                Err(NotFound) -> Dict.insert(dict, pair, ""),
    )

## Returns the URL's [path](https://en.wikipedia.org/wiki/URL#Syntax)—the part after
## the scheme and authority (e.g. `https://`) but before any `?` or `#` it might have.
##
## Returns `""` if the URL has no path.
##
## ```
## # Gives "example.com/"
## Url.from_str("https://example.com/?key1=val1&key2=val2&key3=val3#stuff")
## |> Url.path
## ```
##
## ```
## # Gives "/foo/"
## Url.from_str("/foo/?key1=val1&key2=val2&key3=val3#stuff")
## |> Url.path
## ```
path : Url -> Str
path = |@Url(url_str)|
    without_authority =
        if Str.starts_with(url_str, "/") then
            url_str
        else
            when Str.split_first(url_str, ":") is
                Ok({ after }) ->
                    when Str.split_first(after, "//") is
                        # Only drop the `//` if it's right after the `://` like in `https://`
                        # (so, `before` is empty) - otherwise, the `//` is part of the path!
                        Ok({ before, after: after_slashes }) if Str.is_empty(before) -> after_slashes
                        _ -> after

                # There's no `//` and also no `:` so this must be a path-only URL, e.g. "/foo?bar=baz#blah"
                Err(NotFound) -> url_str

    # Drop the query and/or fragment
    when Str.split_last(without_authority, "?") is
        Ok({ before }) -> before
        Err(NotFound) ->
            when Str.split_last(without_authority, "#") is
                Ok({ before }) -> before
                Err(NotFound) -> without_authority

# `Url.path` supports non-encoded URIs in query parameters (https://datatracker.ietf.org/doc/html/rfc3986#section-3.4)
expect
    input = Url.from_str("https://example.com/foo/bar?key1=https://www.baz.com/some-path#stuff")
    expected = "example.com/foo/bar"
    path(input) == expected

# `Url.path` supports non-encoded URIs in query parameters (https://datatracker.ietf.org/doc/html/rfc3986#section-3.4)
expect
    input = Url.from_str("/foo/bar?key1=https://www.baz.com/some-path#stuff")
    output = Url.path(input)
    expected = "/foo/bar"
    output == expected
