# Hammer spec — self-contained assertions over the pure library functions
# in lib/core.w (URL parsing + HTTP response framing).
#
# COMPILED ONLY. The interpreter cannot exercise these functions: the
# framing helpers call ccall_nobox("w_string_byte_ptr", ...) (unsupported
# under the interpreter), and the interpreter does not resolve unqualified
# static self-calls (url_host -> url_without_scheme). So build and run:
#
#   bin/tungsten -o /tmp/hammer_spec bits/tungsten-hammer/spec/hammer_spec.w
#   /tmp/hammer_spec
#
# The CLI entry point (lib/hammer.w) is deliberately NOT loaded here — only
# lib/core.w, proving the library split leaves the pure logic side-effect free.

use hammer/core

+ Check
  ro :passed
  ro :failed

  -> new
    @passed = 0
    @failed = 0

  # Compare with == first, then via to_s (compiled Array == is identity-based).
  -> eq(label, actual, expected)
    same = actual == expected
    if !same
      same = actual.to_s() == expected.to_s()
    if same
      @passed = @passed + 1
    else
      @failed = @failed + 1
      << "FAIL: " + label
      << "  expected: " + show(expected)
      << "  actual:   " + show(actual)

  -> show(v)
    s = v.to_s()
    if s == nil
      return "(unprintable)"
    s

  -> done
    << @passed.to_s() + " passed, " + @failed.to_s() + " failed"
    if @failed > 0
      exit 1
    << "OK"

t = Check.new

# ---- url_without_scheme ----
t.eq("strips http:// scheme", Hammer.url_without_scheme("http://example.com/x"), "example.com/x")
t.eq("strips https:// scheme", Hammer.url_without_scheme("https://example.com/x"), "example.com/x")
t.eq("leaves scheme-less URL untouched", Hammer.url_without_scheme("example.com/x"), "example.com/x")

# ---- url_host ----
t.eq("host drops port and path", Hammer.url_host("http://a.com:8080/p"), "a.com")
t.eq("host without port", Hammer.url_host("http://a.com/p"), "a.com")
t.eq("host with no path", Hammer.url_host("http://a.com"), "a.com")
t.eq("host from https URL", Hammer.url_host("https://sub.a.com:443/q"), "sub.a.com")

# ---- url_port ----
t.eq("default http port is 80", Hammer.url_port("http://a.com/p"), 80)
t.eq("default https port is 443", Hammer.url_port("https://a.com/p"), 443)
t.eq("explicit http port", Hammer.url_port("http://a.com:9000/p"), 9000)
t.eq("explicit https port overrides default", Hammer.url_port("https://a.com:8443/p"), 8443)
t.eq("explicit port with no path", Hammer.url_port("http://a.com:1234"), 1234)

# ---- url_path ----
t.eq("missing path defaults to /", Hammer.url_path("http://a.com"), "/")
t.eq("explicit multi-segment path", Hammer.url_path("http://a.com/foo/bar"), "/foo/bar")
t.eq("path with port present", Hammer.url_path("http://a.com:81/q"), "/q")
t.eq("root slash path", Hammer.url_path("http://a.com/"), "/")

# ---- request_batch ----
batch1 = Hammer.request_batch("h.com", "/p", 1)
t.eq("request line present", batch1.index("GET /p HTTP/1.1") == 0, true)
t.eq("host header present", batch1.index("Host: h.com") != nil, true)
t.eq("keep-alive present", batch1.index("Connection: keep-alive") != nil, true)
t.eq("single request size", batch1.size, 56)
batch2 = Hammer.request_batch("h.com", "/p", 2)
t.eq("pipeline 2 doubles the batch", batch2.size, 112)

# ---- content_length ----
t.eq("content-length parsed", Hammer.content_length("HTTP/1.1 200 OK\r\nContent-Length: 42\r\n\r\n", 100), 42)
t.eq("lowercase content-length parsed", Hammer.content_length("HTTP/1.1 200 OK\r\ncontent-length: 7\r\n\r\n", 100), 7)
t.eq("absent content-length is 0", Hammer.content_length("HTTP/1.1 200 OK\r\n\r\n", 100), 0)
t.eq("content-length beyond header_end ignored", Hammer.content_length("HTTP/1.1 200 OK\r\nContent-Length: 42\r\n\r\n", 5), 0)

# ---- response_length / response_length_at_raw ----
resp = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"
t.eq("framed response length includes body", Hammer.response_length(resp), 43)
t.eq("response length equals byte size for a complete response", Hammer.response_length(resp), resp.size)

noclen = "HTTP/1.1 204 No Content\r\n\r\n"
t.eq("bodyless response length is header + CRLFCRLF", Hammer.response_length(noclen), 27)
t.eq("bodyless response length equals its size", Hammer.response_length(noclen), noclen.size)

# Incomplete response (header present, body truncated) returns 0 — the caller
# must read more before a full response is framed.
truncated = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhel"
t.eq("truncated body is not yet framed", Hammer.response_length(truncated), 0)

# Too-short buffer (< 15 bytes) can't hold a status line — returns 0.
t.eq("too-short buffer is not framed", Hammer.response_length("HTTP/1.1"), 0)

t.done
