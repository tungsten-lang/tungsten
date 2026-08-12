use core/url

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

url = URL.parse("HTTPS://user:pass@Example.COM:8443/a/b?x=1#frag")
check("url.scheme", url.scheme == "https")
check("url.username", url.username == "user")
check("url.password", url.password == "pass")
check("url.host", url.host == "example.com")
check("url.port", url.port == 8443)
check("url.path", url.path == "/a/b")
check("url.query", url.query == "x=1")
check("url.fragment", url.fragment == "frag")
check("url.to_s", url.to_s == "https://user:pass@example.com:8443/a/b?x=1#frag")
check("url.origin", url.origin == "https://example.com:8443")
check("url.request_target", url.request_target == "/a/b?x=1")
check("url.userinfo", url.userinfo == "user:pass")

default_port = URL.parse("https://example.com")
check("url.default_port", default_port.default_port == 443)
check("url.effective_port", default_port.effective_port == 443)
check("url.default_origin", default_port.origin == "https://example.com")
check("url.empty_path_target", default_port.request_target == "/")

ipv6 = URL.parse("http://\[2001:db8::1\]:8080/")
check("url.ipv6.host", ipv6.host == "2001:db8::1")
check("url.ipv6.port", ipv6.port == 8080)
check("url.ipv6.roundtrip", ipv6.to_s == "http://\[2001:db8::1\]:8080/")

file_url = URL.parse("file:///tmp/tungsten")
check("url.file.host", file_url.host == "")
check("url.file.path", file_url.path == "/tmp/tungsten")
check("url.file.roundtrip", file_url.to_s == "file:///tmp/tungsten")

mailto = URL.parse("mailto:user@example.com")
check("url.opaque.host", mailto.host == nil)
check("url.opaque.path", mailto.path == "user@example.com")
check("url.opaque.roundtrip", mailto.to_s == "mailto:user@example.com")

empty_parts = URL.parse("http://example.com/?#")
check("url.empty_query", empty_parts.query == "")
check("url.empty_fragment", empty_parts.fragment == "")
check("url.empty_parts.roundtrip", empty_parts.to_s == "http://example.com/?#")

valid_escaped = URL.parse("https://example.com/a%20b?q=%2F")
check("url.escaped.roundtrip", valid_escaped.to_s == "https://example.com/a%20b?q=%2F")

invalid = [
  "",
  "example.com/path",
  "1http://example.com",
  "http://",
  "http://exa mple.com",
  "http://example.com:bad/",
  "http://example.com:65536/",
  "http://2001:db8::1/",
  "http://\[2001:db8::1/",
  "http://\[1:2:3\]/",
  "http://\[1:2:3:4:5:6:7:8:9\]/",
  "http://\[1::2::3\]/",
  "http://\[:::1\]/",
  "http://\[::ffff:192.168.001.1\]/",
  "http://example.com/%zz",
  "http://example.com/<bad>",
  "http://example.com/a" + 92.chr + "b",
  "http://a@b@example.com/"
]
i = 0
while i < invalid.size
  check("url.invalid." + i.to_s, URL.try_parse(invalid[i]) == nil)
  i += 1

<< "url_spec: all checks passed"
