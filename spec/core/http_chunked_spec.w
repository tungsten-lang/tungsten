# spec: core interpreter
# HTTP/1.1 chunked transfer coding (RFC 9112 section 7.1) and response
# framing through the shared HTTPReader. Part 1 frames buffered responses and
# runs on both engines. Part 2 serves canned responses from an in-process
# Socket listener on a native thread, so the socket path is exercised without
# network access; it runs in the compiled lane only because the tree-walking
# interpreter has no Socket.

use core/http

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit(1)

-> rejects(name, needle, &)
  message = nil
  begin
    yield
  rescue error
    message = error.to_s
  if message == nil
    << "FAIL " + name + " (nothing raised)"
    exit(1)
  if !message.include?(needle)
    << "FAIL " + name + " (raised: " + message + ")"
    exit(1)
  << "PASS " + name

# ---------------------------------------------------------------------------
# Part 1: buffered responses (both engines)

chunk_a = "0123456789"
chunk_b = "abcdefghijklmnopqrstuvwxyz"
chunk_c = "ABCDEFGHIJKLMNO"
stream = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Test: head\r\n\r\n"
stream += "a\r\n" + chunk_a + "\r\n"
stream += "1A;ext=\"quoted;value\"\r\n" + chunk_b + "\r\n"
stream += "F ; name\r\n" + chunk_c + "\r\n"
stream += "0\r\nX-Checksum: abc123\r\nExpires: later\r\n\r\n"
response = HTTP.parse_response(stream)
check("http.chunked.hex_sizes", response.body == chunk_a + chunk_b + chunk_c)
check("http.chunked.body_size", response.body.size == 51)
check("http.chunked.header", response.header("X-Test") == "head")
check("http.chunked.trailer", response.trailer("X-Checksum") == "abc123")
check("http.chunked.trailers", response.trailers.size == 2 && response.trailers["expires"] == "later")
check("http.chunked.trailer_not_header", response.header("x-checksum") == nil)
check("http.chunked.headers_unchanged", response.headers.size == 2)

crlf_body = "ab\r\nc\r\n"
crlf = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7\r\n" + crlf_body + "\r\n0\r\n\r\n")
check("http.chunked.data_with_crlf", crlf.body == crlf_body)

utf8_body = "héllo wörld"
utf8 = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nd\r\n" + utf8_body + "\r\n0\r\n\r\n")
check("http.chunked.utf8_byte_sizes", utf8.body == utf8_body && utf8.body.size == 13)

split = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" +
  "2\r\n" + utf8_body.slice(0, 2) + "\r\n" +
  "b\r\n" + utf8_body.slice(2, 11) + "\r\n0\r\n\r\n")
check("http.chunked.utf8_split_across_chunks", split.body == utf8_body)

last_ext = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0;done=1\r\n\r\n")
check("http.chunked.last_chunk_extension", last_ext.body == "abc" && last_ext.trailers.size == 0)

zeros = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n003\r\nabc\r\n000\r\n\r\n")
check("http.chunked.leading_zeros", zeros.body == "abc")

check("http.chunked.decode_chunked", HTTP.decode_chunked("2\r\nhi\r\n0\r\n\r\n") == "hi")
check("http.chunked.parse_chunk_size", HTTP.parse_chunk_size("1aF;x=y") == 431)
check("http.chunked.parse_chunk_size_zero", HTTP.parse_chunk_size("0") == 0)

interim = HTTP.parse_response(
  "HTTP/1.1 100 Continue\r\n\r\n" +
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nok\r\n0\r\n\r\n")
check("http.chunked.after_interim", interim.status == 200 && interim.body == "ok")

folded = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nX-Fold: one\r\n two\r\n\tthree\r\n\r\nok")
check("http.obs_fold", folded.header("x-fold") == "one two three")

head = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n", "HEAD")
check("http.head.chunked_no_body", head.body == "")
not_modified = HTTP.parse_response(
  "HTTP/1.1 304 Not Modified\r\nContent-Length: 10\r\n\r\n")
check("http.304.no_body", not_modified.body == "" && not_modified.status == 304)
no_content = HTTP.parse_response(
  "HTTP/1.1 204 No Content\r\nTransfer-Encoding: chunked\r\n\r\n")
check("http.204.no_body", no_content.body == "")
zero_length = HTTP.parse_response("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
check("http.content_length.zero", zero_length.body == "")
to_eof = HTTP.parse_response("HTTP/1.0 200 OK\r\nConnection: close\r\n\r\nall of it")
check("http.read_to_eof", to_eof.body == "all of it")

rejects("http.reject.chunked_http10", "HTTP/1.0") ->
  HTTP.parse_response(
    "HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
rejects("http.reject.chunk_size_width", "chunk size too large") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1000000000000000\r\n")
rejects("http.reject.chunk_size_invalid", "invalid chunk size") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3g\r\nabc\r\n0\r\n\r\n")
rejects("http.reject.chunk_size_empty", "invalid chunk size") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n;ext\r\n0\r\n\r\n")
rejects("http.reject.chunk_terminator", "malformed chunk terminator") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabcd\r\n0\r\n\r\n")
rejects("http.reject.chunk_data_short", "incomplete chunk data") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nab")
rejects("http.reject.trailers_missing_end", "incomplete chunk trailers") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n")
rejects("http.reject.trailer_name", "invalid chunk trailer name") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nBad Name: x\r\n\r\n")
rejects("http.reject.bytes_after_last_chunk", "bytes after") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\nxx")
rejects("http.reject.transfer_encoding_gzip", "unsupported response Transfer-Encoding") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n")
rejects("http.reject.fold_before_field", "malformed response header") ->
  HTTP.parse_response("HTTP/1.1 200 OK\r\n folded\r\nContent-Length: 0\r\n\r\n")

# The bound applies to announced sizes before any download: a chunk size or
# Content-Length that cannot fit the remaining budget is refused up front.
oversize_chunk = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFF\r\n"
rejects("http.bound.chunk_size_refused", "max_response_bytes") ->
  HTTP.read_response(HTTPReader.new(nil, oversize_chunk, 4096, nil), "GET")
rejects("http.bound.chunk_size_unbounded_incomplete", "incomplete chunk data") ->
  HTTP.read_response(HTTPReader.new(nil, oversize_chunk, nil, nil), "GET")
rejects("http.bound.buffered_input", "max_response_bytes") ->
  HTTPReader.new(nil, oversize_chunk, 10, nil)
oversize_length = "HTTP/1.1 200 OK\r\nContent-Length: 99999999999999999999\r\n\r\n"
rejects("http.bound.content_length_refused", "max_response_bytes") ->
  HTTP.read_response(HTTPReader.new(nil, oversize_length, 4096, nil), "GET")
rejects("http.bound.content_length_unbounded_incomplete", "incomplete response body") ->
  HTTP.parse_response(oversize_length)

# ---------------------------------------------------------------------------
# Part 2: canned responses served over a loopback Socket (compiled lane)

if env("TUNGSTEN_INTERPRETED_SPEC") == "1"
  << "SKIP http.chunked.socket (the interpreter has no Socket)"
  << "http_chunked_spec: all checks passed"
  exit(0)

port = 39476
listener = Socket.listen("127.0.0.1", port)
if listener == nil
  << "SKIP http.chunked.socket (Socket.listen unavailable on this engine)"
  << "http_chunked_spec: all checks passed"
  exit(0)

url = "http://127.0.0.1:[port]/chunked"

# Accept one connection, read the request head, write each piece, then close
# — after `release` delivers when given, which keeps the connection open so a
# client that waits for EOF instead of trusting the framing would stall.
-> serve_once(listener, pieces, release)
  seen = Channel.new(1)
  thread = Thread.new ->
    connection = listener.accept
    request = ""
    loop
      chunk = connection.read(4096)
      break if chunk == nil
      request += chunk
      break if request.index("\r\n\r\n") != nil
    seen.send(request)
    pieces.each -> (piece)
      connection.write(piece)
    if release != nil
      release.receive
    connection.close
  [thread, seen]

-> finish(server, release)
  if release != nil
    release.send(true)
  server[0].join
  server[1].receive

# Several chunks, an extension, a trailer, pieces split mid-token and mid-CRLF.
server = serve_once(listener, [
  "HTTP/1.1 200 OK\r\nTransfer-Enc",
  "oding: chunked\r\nX-Loop: yes\r\n\r\na\r\n01234",
  "56789\r\n1A;ext=1\r\n" + chunk_b + "\r",
  "\n0\r\nX-Checksum: 9\r\n\r\n"
], nil)
response = HTTP.get(url, {}, 5000)
request = finish(server, nil)
check("http.socket.chunked.body", response.body == chunk_a + chunk_b)
check("http.socket.chunked.header", response.header("x-loop") == "yes")
check("http.socket.chunked.trailer", response.trailer("x-checksum") == "9")
check("http.socket.chunked.connection_close", request.include?("Connection: close\r\n"))

# A complete chunked message returns as soon as its framing ends, even when
# the server keeps the connection open.
release = Channel.new(1)
server = serve_once(listener, [
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
], release)
started = clock_ms()
response = HTTP.get(url, {}, 5000)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.chunked.no_eof_wait", response.body == "hello" && elapsed < 2500)

# An announced chunk larger than the bound is refused before it is downloaded:
# the server never sends the data, so waiting for it would hit the timeout.
release = Channel.new(1)
server = serve_once(listener, [
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFF\r\n"
], release)
started = clock_ms()
rejects("http.socket.bound.chunk_size", "max_response_bytes") ->
  HTTP.request("GET", url, {}, nil, 3000, 1024)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.bound.chunk_size_prompt", elapsed < 1500)

# Many small chunks whose total crosses the bound are rejected mid-stream.
piece = "12c\r\n" + ("x" * 300) + "\r\n"
server = serve_once(listener, [
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n",
  piece, piece, piece, piece, piece, "0\r\n\r\n"
], nil)
rejects("http.socket.bound.cumulative", "max_response_bytes") ->
  HTTP.request("GET", url, {}, nil, 3000, 1000)
finish(server, nil)

# The same bound accepts a stream that fits it.
server = serve_once(listener, [
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n", piece, piece, "0\r\n\r\n"
], nil)
response = HTTP.request("GET", url, {}, nil, 3000, 1000)
finish(server, nil)
check("http.socket.bound.fits", response.body.size == 600)

# Content-Length beyond the bound is refused up front, without downloading.
release = Channel.new(1)
server = serve_once(listener, ["HTTP/1.1 200 OK\r\nContent-Length: 5000\r\n\r\nabc"], release)
started = clock_ms()
rejects("http.socket.bound.content_length", "max_response_bytes") ->
  HTTP.request("GET", url, {}, nil, 3000, 1024)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.bound.content_length_prompt", elapsed < 1500)

# A Content-Length body completes without waiting for EOF.
release = Channel.new(1)
server = serve_once(listener, ["HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npo", "ng"], release)
started = clock_ms()
response = HTTP.get(url, {}, 5000)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.content_length.no_eof_wait", response.body == "pong" && elapsed < 2500)

# Neither Content-Length nor chunked: the body runs to EOF (HTTP/1.0 style).
server = serve_once(listener, [
  "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nstream", "ed body"
], nil)
response = HTTP.get(url, {}, 5000)
finish(server, nil)
check("http.socket.read_to_eof", response.body == "streamed body")
server = serve_once(listener, ["HTTP/1.0 200 OK\r\n\r\nold"], nil)
response = HTTP.get(url, {}, 5000)
finish(server, nil)
check("http.socket.http10_to_eof", response.version == "HTTP/1.0" && response.body == "old")

# HEAD, 204, and 304 have no body: they return without reading past the head.
release = Channel.new(1)
server = serve_once(listener, ["HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n"], release)
started = clock_ms()
response = HTTP.head(url, {}, 5000)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.head", response.body == "" && response.header("content-length") == "1000" && elapsed < 2500)
release = Channel.new(1)
server = serve_once(listener, ["HTTP/1.1 304 Not Modified\r\nTransfer-Encoding: chunked\r\n\r\n"], release)
started = clock_ms()
response = HTTP.get(url, {}, 5000)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.304", response.status == 304 && response.body == "" && elapsed < 2500)
release = Channel.new(1)
server = serve_once(listener, ["HTTP/1.1 204 No Content\r\n\r\n"], release)
response = HTTP.get(url, {}, 5000)
finish(server, release)
check("http.socket.204", response.status == 204 && response.body == "")

# A stalled server trips the read deadline, reported as a timeout.
release = Channel.new(1)
server = serve_once(listener, ["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel"], release)
started = clock_ms()
rejects("http.socket.timeout", "timed out") ->
  HTTP.get(url, {}, 300)
elapsed = clock_ms() - started
finish(server, release)
check("http.socket.timeout_elapsed", elapsed >= 250 && elapsed < 3000)

# A server that closes mid-chunk is an incomplete message, not a timeout.
server = serve_once(listener, ["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel"], nil)
rejects("http.socket.truncated", "incomplete chunk data") ->
  HTTP.get(url, {}, 5000)
finish(server, nil)

listener.close
<< "http_chunked_spec: all checks passed"
