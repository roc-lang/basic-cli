## Download a file without holding it in memory, and follow a response body
## as it arrives.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
}

import pf.Duration
import pf.File
import pf.Http
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Url
import http.Request

# To run this example, first start the test server in another terminal:
#
#     cd ci/rust_http_server && cargo run --release
#
# then:
#
#     roc build examples/http-download.roc
#     ./examples/http-download
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	destination : Path
	destination = "download.bin"

	download!("http://127.0.0.1:9000/stream/sized", destination) ? |err| DownloadFailed(err)
	size = destination.size_in_bytes!()?
	Stdout.line!("Downloaded ${size.to_str()} bytes to ${destination.display()}.")?

	# The status arrives before the body, so a body nobody wants is never read.
	match download!("http://127.0.0.1:9000/not-found", destination) {
		Err(UnexpectedStatus(status)) => Stdout.line!("The server answered ${status.to_str()}; ${destination.display()} was left alone.")?
		Err(err) => {
			return Err(DownloadFailed(err))
		}
		Ok({}) => {
			return Err(MissingFileWasDownloaded)
		}
	}
	unchanged = destination.size_in_bytes!()?
	Stdout.line!("${destination.display()} still holds ${unchanged.to_str()} bytes.")?

	measure!("http://127.0.0.1:9000/stream/sized")?
	measure!("http://127.0.0.1:9000/stream/chunked")?

	# Cleanup
	destination.delete!()?

	Ok({})
}

## Write a response body to disk a chunk at a time.
##
## The request keeps its default `NoTimeout`, so a large file may take as long
## as it needs; the default idle timeout still stops a download whose server
## has been silent for 30 seconds. A body that fails part-way is
## `SourceErr(HttpErr(_))`, a disk that fails is `FileErr(_)`.
download! : Url, Path => Try({}, _)
download! = |url, destination| {
	request = Request.from_method(GET).with_uri(url.to_str())
	response = Http.send_streaming!(request, {})?
	if response.status() != 200 {
		return Err(UnexpectedStatus(response.status()))
	}
	File.with_writer!(destination, Truncate, {}, |writer| writer.write_stream!(response.chunks()))?

	Ok({})
}

## Handle each chunk as it arrives: here, to count the bytes against the
## length the server announced, if it announced one.
measure! : Url => Try({}, _)
measure! = |url| {
	request = Request.from_method(GET).with_uri(url.to_str())
	response = Http.send_streaming!(request, { idle_timeout: After(Duration.seconds(5)) })?
	var $done = 0
	for! item in response.chunks() {
		bytes = item?
		$done = $done + bytes.len()
	}
	match response.content_length() {
		Known(total) => Stdout.line!("Received ${$done.to_str()} of ${total.to_str()} bytes from ${url.path()}.")
		Unknown => Stdout.line!("Received ${$done.to_str()} bytes of unannounced length from ${url.path()}.")
	}
}
