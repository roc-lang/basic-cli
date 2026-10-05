## Build a validated search URL while encoding path and query components.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout
import pf.Url

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	base : Url.Url
	base = "https://api.example.com"
	search = base.append_path_segments(["v1", "search"])
	with_query = search.append_query_param("q", "roc lang")
	with_page = with_query.append_query_param("page", "1")
	url = with_page.with_fragment(Some("results")) ? |err| UrlBuildFailed(err)

	expect url.path() == "/v1/search"
	expect url.query() == Some("q=roc+lang&page=1")
	expect url.query_pairs() == [("q", "roc lang"), ("page", "1")]

	Stdout.line!("Request URL: ${url.to_str()}")?
	Stdout.line!("Debug URL: ${Str.inspect(url)}")?
	Stdout.line!("JSON URL: ${Json.to_str(url)}")?
	Ok({})
}
