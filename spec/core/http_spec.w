use core/http

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit(1)

-> rejects(name, &)
  raised = false
  begin
    yield
  rescue error
    raised = true
  check(name, raised)

plain = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: one\r\nx-test: two\r\n\r\nhello")
check("http.status", plain.status == 200)
check("http.reason", plain.reason == "OK")
check("http.version", plain.version == "HTTP/1.1")
check("http.body", plain.body == "hello")
check("http.header.case", plain.header("X-TEST") == "one, two")
check("http.success", plain.success? && plain.ok? && !plain.redirect?)

chunked = HTTP.parse_response(
  "HTTP/1.1 201 Created\r\nTransfer-Encoding: chunked\r\n\r\n" +
  "4;name=value\r\nWiki\r\n5\r\npedia\r\n0\r\nChecksum: yes\r\n\r\n")
check("http.chunked.status", chunked.status == 201)
check("http.chunked.body", chunked.body == "Wikipedia")

binary = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" +
  "3\r\na\0b\r\n0\r\n\r\n")
check("http.chunked.binary_size", binary.body.size == 3)
check("http.chunked.binary_nul", binary.body.slice(1, 1) == "\0")

head = HTTP.parse_response(
  "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n", "HEAD")
check("http.head.no_body", head.body == "")

url = URL.parse("http://example.com:8080/a?q=1")
request = HTTP.build_request_head("get", url, {
  "Accept": "text/plain",
  "Host": "wrong.example",
  "Connection": "keep-alive",
  "Content-Length": "999"
}, "hi")
check("http.request.line", request.starts_with?("GET /a?q=1 HTTP/1.1\r\n"))
check("http.request.host", request.include?("Host: example.com:8080\r\n"))
check("http.request.header", request.include?("Accept: text/plain\r\n"))
check("http.request.length", request.include?("Content-Length: 2\r\n"))
check("http.request.close", request.include?("Connection: close\r\n\r\n"))
check("http.request.no_override", !request.include?("wrong.example") && !request.include?("999"))

redirect = HTTP.parse_response("HTTP/1.0 302 Found\r\nLocation: /next\r\n\r\n")
check("http.redirect", redirect.redirect? && !redirect.success?)

early_hints = HTTP.parse_response(
  "HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload\r\n\r\n" +
  "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
check("http.informational.final_status", early_hints.status == 200)
check("http.informational.final_body", early_hints.body == "ok")

rejects("http.reject.https") ->
  HTTP.get("https://example.com/")
rejects("http.reject.header_newline") ->
  HTTP.build_request_head("GET", url, {"Bad": "one\r\ntwo"})
rejects("http.reject.header_nul") ->
  HTTP.build_request_head("GET", url, {"Bad": "one\0two"})
rejects("http.reject.header_name") ->
  HTTP.build_request_head("GET", url, {"Bad Name": "value"})
rejects("http.reject.transfer_encoding") ->
  HTTP.build_request_head("GET", url, {"Transfer-Encoding": "chunked"})
rejects("http.reject.short_body") ->
  HTTP.parse_response("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhey")
rejects("http.reject.long_body") ->
  HTTP.parse_response("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nhello")
rejects("http.reject.ambiguous_framing") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n")
rejects("http.reject.bad_chunk") ->
  HTTP.parse_response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nxyz\r\n")
rejects("http.reject.upgrade") ->
  HTTP.parse_response("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n")

<< "http_spec: all checks passed"
