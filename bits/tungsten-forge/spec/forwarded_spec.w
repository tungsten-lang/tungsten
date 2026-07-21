# Forge proxy-forwarding specs — Forwarded (RFC 7239 `Forwarded` header
# and the de-facto `X-Forwarded-*` family) and the Request methods that
# delegate to it (#forwarded, #forwarded_for, #client_ip,
# #forwarded_proto, #forwarded_host, #forwarded_port, #forwarded_ssl?,
# #via_proxy?).
#
# No sockets: requests are built with Request.parse (or Request.new for
# the remote_addr fallback), so everything here runs under both engines.
# Arrays are asserted by size/index rather than `==` (compiled Array
# equality is identity).
#
# Style note: IPv6 literals carry "[" "]", which interpolate inside a
# Tungsten string — they are escaped "\[" "\]" throughout. Never chain a
# call off a `?` method (lexes as safe navigation, unimplemented in the
# interpreter).

use spec_helper

describe "Forwarded.parse (RFC 7239)" ->
  it "parses one element's for/proto/by params" ->
    els = Forwarded.parse("for=192.0.2.60;proto=http;by=203.0.113.43")
    expect(els.size).to eq(1)
    expect(els[0]["for"]).to eq("192.0.2.60")
    expect(els[0]["proto"]).to eq("http")
    expect(els[0]["by"]).to eq("203.0.113.43")

  it "keeps comma-separated elements in order" ->
    els = Forwarded.parse("for=192.0.2.43, for=198.51.100.17")
    expect(els.size).to eq(2)
    expect(els[0]["for"]).to eq("192.0.2.43")
    expect(els[1]["for"]).to eq("198.51.100.17")

  it "downcases param names but preserves value case" ->
    els = Forwarded.parse("For=1.2.3.4;Proto=HTTPS")
    expect(els[0]["for"]).to eq("1.2.3.4")
    expect(els[0]["proto"]).to eq("HTTPS")

  it "unwraps a double-quoted value (IPv6 with port)" ->
    els = Forwarded.parse("for=\"\[2001:db8::1\]:4711\"")
    expect(els[0]["for"]).to eq("\[2001:db8::1\]:4711")

  it "does not split on a comma inside a quoted value" ->
    els = Forwarded.parse("for=\"a,b\";proto=http")
    expect(els.size).to eq(1)
    expect(els[0]["for"]).to eq("a,b")
    expect(els[0]["proto"]).to eq("http")

  it "skips an empty element from a stray comma" ->
    els = Forwarded.parse("for=1.1.1.1, , for=2.2.2.2")
    expect(els.size).to eq(2)
    expect(els[1]["for"]).to eq("2.2.2.2")

  it "skips an element with no name=value param" ->
    expect(Forwarded.parse("garbage").size).to eq(0)

  it "returns an empty array for nil or empty input" ->
    expect(Forwarded.parse(nil).size).to eq(0)
    expect(Forwarded.parse("").size).to eq(0)

describe "Forwarded.node_host" ->
  it "leaves a bare IPv4 unchanged" ->
    expect(Forwarded.node_host("192.0.2.43")).to eq("192.0.2.43")

  it "strips a port from an IPv4:port node" ->
    expect(Forwarded.node_host("192.0.2.43:47011")).to eq("192.0.2.43")

  it "strips brackets and port from a bracketed IPv6 node" ->
    expect(Forwarded.node_host("\[2001:db8:cafe::17\]:4711")).to eq("2001:db8:cafe::17")

  it "strips brackets from a bracketed IPv6 with no port" ->
    expect(Forwarded.node_host("\[2001:db8::1\]")).to eq("2001:db8::1")

  it "leaves a bare IPv6 literal unchanged" ->
    expect(Forwarded.node_host("2001:db8::1")).to eq("2001:db8::1")

  it "leaves obfuscated identifiers unchanged" ->
    expect(Forwarded.node_host("unknown")).to eq("unknown")
    expect(Forwarded.node_host("_hidden")).to eq("_hidden")

  it "is nil for a nil node" ->
    expect(Forwarded.node_host(nil)).to be_nil

describe "Forwarded.split_list" ->
  it "splits on commas and trims each token" ->
    list = Forwarded.split_list("a, b ,c")
    expect(list.size).to eq(3)
    expect(list[0]).to eq("a")
    expect(list[1]).to eq("b")
    expect(list[2]).to eq("c")

  it "skips empty tokens from stray or trailing commas" ->
    list = Forwarded.split_list(", a ,, b,")
    expect(list.size).to eq(2)
    expect(list[0]).to eq("a")
    expect(list[1]).to eq("b")

  it "returns an empty array for nil or empty input" ->
    expect(Forwarded.split_list(nil).size).to eq(0)
    expect(Forwarded.split_list("").size).to eq(0)

describe "Request#forwarded and #forwarded_for" ->
  it "exposes the structured RFC 7239 elements" ->
    req = Request.parse("GET / HTTP/1.1\r\nForwarded: for=192.0.2.60;proto=https\r\n\r\n")
    expect(req.forwarded.size).to eq(1)
    expect(req.forwarded[0]["proto"]).to eq("https")

  it "builds the address chain from Forwarded, client-first, hosts bare" ->
    req = Request.parse("GET / HTTP/1.1\r\nForwarded: for=192.0.2.43, for=\"\[2001:db8::1\]:4711\"\r\n\r\n")
    chain = req.forwarded_for
    expect(chain.size).to eq(2)
    expect(chain[0]).to eq("192.0.2.43")
    expect(chain[1]).to eq("2001:db8::1")

  it "falls back to X-Forwarded-For when Forwarded is absent" ->
    req = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-For: 203.0.113.1, 70.41.3.18, 150.172.238.178\r\n\r\n")
    chain = req.forwarded_for
    expect(chain.size).to eq(3)
    expect(chain[0]).to eq("203.0.113.1")
    expect(chain[2]).to eq("150.172.238.178")

  it "is an empty chain when the request did not come through a proxy" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.forwarded_for.size).to eq(0)

describe "Request#client_ip" ->
  it "is the leftmost forwarded address" ->
    req = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-For: 203.0.113.1, 70.41.3.18\r\n\r\n")
    expect(req.client_ip).to eq("203.0.113.1")

  it "falls back to remote_addr with no forwarding headers" ->
    req = Request.new({path: "/", remote_addr: "10.0.0.5"})
    expect(req.client_ip).to eq("10.0.0.5")

describe "Request#forwarded_proto and #forwarded_ssl?" ->
  it "reads X-Forwarded-Proto, downcased" ->
    req = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-Proto: HTTPS\r\n\r\n")
    expect(req.forwarded_proto).to eq("https")

  it "prefers the RFC 7239 proto param over X-Forwarded-Proto" ->
    req = Request.parse("GET / HTTP/1.1\r\nForwarded: proto=http\r\nX-Forwarded-Proto: https\r\n\r\n")
    expect(req.forwarded_proto).to eq("http")

  it "is nil when no proto is forwarded" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.forwarded_proto).to be_nil

  it "forwarded_ssl? is true for https and false for http" ->
    https = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-Proto: https\r\n\r\n")
    http  = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-Proto: http\r\n\r\n")
    expect(https.forwarded_ssl?).to eq(true)
    expect(http.forwarded_ssl?).to eq(false)

describe "Request#forwarded_host and #forwarded_port" ->
  it "reads X-Forwarded-Host" ->
    req = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-Host: app.example.com\r\n\r\n")
    expect(req.forwarded_host).to eq("app.example.com")

  it "prefers the RFC 7239 host param over X-Forwarded-Host" ->
    req = Request.parse("GET / HTTP/1.1\r\nForwarded: host=canonical.example\r\nX-Forwarded-Host: other.example\r\n\r\n")
    expect(req.forwarded_host).to eq("canonical.example")

  it "reads X-Forwarded-Port as an integer" ->
    req = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-Port: 8443\r\n\r\n")
    expect(req.forwarded_port).to eq(8443)

  it "forwarded_port is nil when the header is absent" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.forwarded_port).to be_nil

describe "Request#via_proxy?" ->
  it "is true when a forwarded address is present" ->
    req = Request.parse("GET / HTTP/1.1\r\nX-Forwarded-For: 203.0.113.1\r\n\r\n")
    expect(req.via_proxy?).to eq(true)

  it "is false for a direct request" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.via_proxy?).to eq(false)

spec_summary
