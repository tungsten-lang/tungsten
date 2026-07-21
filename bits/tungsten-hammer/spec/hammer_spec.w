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

# ---- IPv6 bracketed hosts (RFC 3986 §3.2.2) ----
# Brackets are escaped in the source URLs so the lexer does not treat them as
# string interpolation; the parsed host is the bare address, no brackets.
t.eq("IPv6 host strips brackets", Hammer.url_host("http://\[::1\]:8080/p"), "::1")
t.eq("IPv6 explicit port after bracket", Hammer.url_port("http://\[::1\]:8080/p"), 8080)
t.eq("IPv6 host without port", Hammer.url_host("http://\[2001:db8::1\]/p"), "2001:db8::1")
t.eq("IPv6 default port when absent", Hammer.url_port("http://\[2001:db8::1\]/p"), 80)
t.eq("IPv6 https default port", Hammer.url_port("https://\[::1\]/p"), 443)
t.eq("IPv6 host with no path", Hammer.url_host("http://\[::1\]:8080"), "::1")
t.eq("IPv6 path is unaffected by the address", Hammer.url_path("http://\[::1\]:8080/foo"), "/foo")

# ---- userinfo (user[:pass]@) is stripped from the authority ----
t.eq("userinfo stripped from host", Hammer.url_host("http://user:pass@h.com/p"), "h.com")
t.eq("userinfo does not shadow the port", Hammer.url_port("http://user:pass@h.com:9000/p"), 9000)
t.eq("user-only userinfo stripped", Hammer.url_host("http://user@h.com/p"), "h.com")
t.eq("userinfo path is unaffected", Hammer.url_path("http://user:pass@h.com/deep/path"), "/deep/path")

# ---- userinfo + IPv6 combined ----
t.eq("userinfo before IPv6 host", Hammer.url_host("http://user:pass@\[::1\]:8080/p"), "::1")
t.eq("userinfo before IPv6 port", Hammer.url_port("http://user:pass@\[::1\]:8080/p"), 8080)

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

# ---- chunked transfer-encoding framing (RFC 7230 §4.1) ----
# A chunked body has no Content-Length; the frame runs from the status line
# through the terminating zero-length chunk and its blank line.
chunked1 = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
t.eq("chunked response frames to its full byte size", Hammer.response_length(chunked1), chunked1.size)
t.eq("chunked response length is header + chunk framing", Hammer.response_length(chunked1), 62)

# The header name and the "chunked" token are matched case-insensitively.
chunked_ci = "HTTP/1.1 200 OK\r\ntransfer-encoding: Chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
t.eq("chunked detection is case-insensitive", Hammer.response_length(chunked_ci), 62)

# A hex chunk size larger than one digit ('b' == 11) frames the 11-byte body.
chunked_hex = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nb\r\nhello world\r\n0\r\n\r\n"
t.eq("chunked hex size frames the full body", Hammer.response_length(chunked_hex), chunked_hex.size)

# Multiple data chunks are summed through the terminator.
chunked_two = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nfoo\r\n3\r\nbar\r\n0\r\n\r\n"
t.eq("multiple chunks are summed", Hammer.response_length(chunked_two), chunked_two.size)

# Chunk extensions (";foo=bar" on the size line) are skipped.
chunked_ext = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;foo=bar\r\nhello\r\n0\r\n\r\n"
t.eq("chunk extensions are skipped", Hammer.response_length(chunked_ext), chunked_ext.size)

# A trailer header after the last chunk is consumed up to the blank line.
chunked_trailer = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\nX-Sum: abc\r\n\r\n"
t.eq("chunked trailers are consumed", Hammer.response_length(chunked_trailer), chunked_trailer.size)

# An incomplete chunked body is not framed yet (caller must read more).
chunked_partial = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel"
t.eq("chunked body truncated mid-chunk is not framed", Hammer.response_length(chunked_partial), 0)
chunked_noterm = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n"
t.eq("chunked body missing terminator is not framed", Hammer.response_length(chunked_noterm), 0)

# On a keep-alive connection, framing must stop exactly at the terminator so
# the next pipelined response is not swallowed.
chunked_pipelined = chunked1 + "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
t.eq("chunked framing stops at the terminator, not buffer end", Hammer.response_length(chunked_pipelined), 62)
t.eq("chunked frame is shorter than the pipelined buffer", Hammer.response_length(chunked_pipelined) < chunked_pipelined.size, true)

# ---- latency statistics (nearest-rank percentiles + summary) ----
# All percentile/min/max inputs are ascending-sorted. Values below are hand
# checked against the NIST nearest-rank definition: rank = ceil(p*N/100),
# taking the 1-based sample at that rank.

# Ten evenly-spaced samples (N=10): p*N/100 is a whole number, so the rank is
# exactly p/10 and the value is that multiple of 10.
deca = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
t.eq("p50 of 10 samples", Hammer.percentile(deca, 50), 50)     # ceil(500/100)=5 -> deca[4]
t.eq("p90 of 10 samples", Hammer.percentile(deca, 90), 90)     # ceil(900/100)=9 -> deca[8]
t.eq("p99 of 10 samples", Hammer.percentile(deca, 99), 100)    # ceil(990/100)=10 -> deca[9]
t.eq("p25 of 10 samples", Hammer.percentile(deca, 25), 30)     # ceil(250/100)=3 -> deca[2]
t.eq("p75 of 10 samples", Hammer.percentile(deca, 75), 80)     # ceil(750/100)=8 -> deca[7]
t.eq("p0 clamps to the minimum", Hammer.percentile(deca, 0), 10)
t.eq("p100 clamps to the maximum", Hammer.percentile(deca, 100), 100)
t.eq("p above 100 clamps to the maximum", Hammer.percentile(deca, 150), 100)
t.eq("negative percentile clamps to the minimum", Hammer.percentile(deca, -5), 10)
t.eq("min of sorted samples", Hammer.stat_min(deca), 10)
t.eq("max of sorted samples", Hammer.stat_max(deca), 100)
t.eq("sum of samples", Hammer.stat_sum(deca), 550)
t.eq("mean of samples", Hammer.stat_mean(deca), 55)

# Seven samples (N=7): ceil rounds the fractional ranks up. p50 -> rank 4 = 35
# (the true median of an odd count), p90/p99 both -> rank 7 = 65.
hepta = [5, 15, 25, 35, 45, 55, 65]
t.eq("p50 of 7 samples is the median", Hammer.percentile(hepta, 50), 35)  # ceil(350/100)=4
t.eq("p90 of 7 samples rounds up", Hammer.percentile(hepta, 90), 65)      # ceil(630/100)=7
t.eq("p99 of 7 samples rounds up", Hammer.percentile(hepta, 99), 65)      # ceil(693/100)=7
t.eq("mean of 7 samples", Hammer.stat_mean(hepta), 35)                    # 245/7

# Even count (N=4): nearest-rank p50 is the lower-middle sample (20), not the
# interpolated 25 — this is the defining behavior of the nearest-rank method.
quad = [10, 20, 30, 40]
t.eq("nearest-rank p50 of even count is lower-middle", Hammer.percentile(quad, 50), 20)  # ceil(200/100)=2
t.eq("p25 of 4 samples", Hammer.percentile(quad, 25), 10)  # ceil(100/100)=1
t.eq("p75 of 4 samples", Hammer.percentile(quad, 75), 30)  # ceil(300/100)=3

# Single sample: every percentile is that one value.
one = [42]
t.eq("p50 of a single sample", Hammer.percentile(one, 50), 42)
t.eq("p99 of a single sample", Hammer.percentile(one, 99), 42)
t.eq("mean of a single sample", Hammer.stat_mean(one), 42)

# Mean truncates toward zero (integer division): 5 / 3 == 1.
t.eq("mean truncates to an integer", Hammer.stat_mean([1, 2, 2]), 1)

# Empty sample: all summaries are 0, so callers need no emptiness guard.
empty = []
t.eq("percentile of empty sample is 0", Hammer.percentile(empty, 50), 0)
t.eq("min of empty sample is 0", Hammer.stat_min(empty), 0)
t.eq("max of empty sample is 0", Hammer.stat_max(empty), 0)
t.eq("sum of empty sample is 0", Hammer.stat_sum(empty), 0)
t.eq("mean of empty sample is 0", Hammer.stat_mean(empty), 0)

t.done
