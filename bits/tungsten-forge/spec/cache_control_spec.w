# Forge Cache-Control specs — CacheControl directive parsing (RFC 7234
# §5.2, with RFC 8246 immutable and RFC 5861 stale-while-revalidate /
# stale-if-error), plus the Request#cache_control and
# Response#cache_control delegators. Before this the request/response
# surface could only WRITE a Cache-Control string, never read one back
# into structured form.
#
# Pure header logic: no sockets, no clock. Requests are built with
# Request.parse and responses with the Response writers, so every example
# runs under both the interpreter and compiled. Symbols (:any) compare by
# value; Array results are checked by size + element, never by == (which
# is identity for compiled Arrays).

use spec_helper

describe "CacheControl.parse — shape" ->
  it "is empty for nil or blank input" ->
    expect(CacheControl.parse(nil).empty?).to eq(true)
    expect(CacheControl.parse("").empty?).to eq(true)
    expect(CacheControl.parse("   ").empty?).to eq(true)

  it "parses a single flag directive" ->
    cc = CacheControl.parse("no-cache")
    expect(cc.empty?).to eq(false)
    expect(cc.has?("no-cache")).to eq(true)
    expect(cc.get("no-cache")).to eq(true)

  it "parses a single value directive" ->
    cc = CacheControl.parse("max-age=3600")
    expect(cc.get("max-age")).to eq("3600")
    expect(cc.max_age).to eq(3600)

  it "parses multiple directives" ->
    cc = CacheControl.parse("public, max-age=600, must-revalidate")
    expect(cc.public?).to eq(true)
    expect(cc.max_age).to eq(600)
    expect(cc.must_revalidate?).to eq(true)

  it "lower-cases directive names (case-insensitive)" ->
    cc = CacheControl.parse("No-Cache, Max-Age=60, PUBLIC")
    expect(cc.no_cache?).to eq(true)
    expect(cc.max_age).to eq(60)
    expect(cc.public?).to eq(true)

  it "tolerates sloppy whitespace around directives and '='" ->
    cc = CacheControl.parse("  public ,   max-age=120 ,,  no-store  ")
    expect(cc.public?).to eq(true)
    expect(cc.max_age).to eq(120)
    expect(cc.no_store?).to eq(true)

  it "keeps the FIRST value on a duplicate directive" ->
    cc = CacheControl.parse("max-age=1, max-age=999")
    expect(cc.max_age).to eq(1)

  it "unquotes a quoted-string value" ->
    cc = CacheControl.parse("no-cache=\"Set-Cookie\"")
    expect(cc.get("no-cache")).to eq("Set-Cookie")

  it "does not split on a comma inside a quoted-string" ->
    cc = CacheControl.parse("private=\"X-A, X-B\", max-age=5")
    expect(cc.get("private")).to eq("X-A, X-B")
    expect(cc.max_age).to eq(5)

describe "CacheControl — flag directives" ->
  it "reports each response flag" ->
    cc = CacheControl.parse("public, no-store, no-transform, must-revalidate, proxy-revalidate, immutable")
    expect(cc.public?).to eq(true)
    expect(cc.no_store?).to eq(true)
    expect(cc.no_transform?).to eq(true)
    expect(cc.must_revalidate?).to eq(true)
    expect(cc.proxy_revalidate?).to eq(true)
    expect(cc.immutable?).to eq(true)

  it "reports request-only flags" ->
    cc = CacheControl.parse("no-cache, only-if-cached")
    expect(cc.no_cache?).to eq(true)
    expect(cc.only_if_cached?).to eq(true)

  it "reports false for absent flags" ->
    cc = CacheControl.parse("max-age=1")
    expect(cc.no_cache?).to eq(false)
    expect(cc.public?).to eq(false)
    expect(cc.private?).to eq(false)
    expect(cc.immutable?).to eq(false)
    expect(cc.only_if_cached?).to eq(false)

describe "CacheControl — delta-seconds accessors" ->
  it "parses every delta-seconds directive as an Integer" ->
    cc = CacheControl.parse("max-age=100, s-maxage=200, min-fresh=30, stale-while-revalidate=60, stale-if-error=90")
    expect(cc.max_age).to eq(100)
    expect(cc.s_maxage).to eq(200)
    expect(cc.min_fresh).to eq(30)
    expect(cc.stale_while_revalidate).to eq(60)
    expect(cc.stale_if_error).to eq(90)

  it "accepts an explicit zero" ->
    cc = CacheControl.parse("max-age=0")
    expect(cc.max_age).to eq(0)

  it "is nil for an absent delta-seconds directive" ->
    cc = CacheControl.parse("public")
    expect(cc.max_age).to be_nil
    expect(cc.s_maxage).to be_nil

  it "is nil for a non-numeric (malformed) value" ->
    cc = CacheControl.parse("max-age=abc")
    expect(cc.max_age).to be_nil
    expect(cc.get("max-age")).to eq("abc")

  it "is nil for a valueless delta-seconds directive" ->
    cc = CacheControl.parse("max-age")
    expect(cc.max_age).to be_nil

describe "CacheControl#max_stale" ->
  it "is nil when absent" ->
    expect(CacheControl.parse("no-cache").max_stale).to be_nil

  it "is :any when present without a value" ->
    expect(CacheControl.parse("max-stale").max_stale).to eq(:any)

  it "is the Integer bound when present with a value" ->
    expect(CacheControl.parse("max-stale=120").max_stale).to eq(120)

  it "is :any when present with a malformed value" ->
    expect(CacheControl.parse("max-stale=soon").max_stale).to eq(:any)

describe "CacheControl — field-name lists" ->
  it "reads a no-cache field list" ->
    fields = CacheControl.parse("no-cache=\"Set-Cookie, X-Token\"").no_cache_fields
    expect(fields.size).to eq(2)
    expect(fields[0]).to eq("Set-Cookie")
    expect(fields[1]).to eq("X-Token")

  it "reads a private field list" ->
    fields = CacheControl.parse("private=\"X-Field\"").private_fields
    expect(fields.size).to eq(1)
    expect(fields[0]).to eq("X-Field")

  it "is an empty list for a bare flag or absent directive" ->
    expect(CacheControl.parse("no-cache").no_cache_fields.size).to eq(0)
    expect(CacheControl.parse("public").private_fields.size).to eq(0)

describe "CacheControl — generic access" ->
  it "has? and get are case-insensitive" ->
    cc = CacheControl.parse("Max-Age=42")
    expect(cc.has?("MAX-AGE")).to eq(true)
    expect(cc.get("max-age")).to eq("42")

  it "get is nil for an absent directive" ->
    expect(CacheControl.parse("public").get("max-age")).to be_nil

describe "Request#cache_control" ->
  it "parses the request Cache-Control header" ->
    req = Request.parse("GET / HTTP/1.1\r\nCache-Control: no-cache, max-age=0\r\n\r\n")
    cc = req.cache_control
    expect(cc.no_cache?).to eq(true)
    expect(cc.max_age).to eq(0)

  it "honours only-if-cached and max-stale from a client" ->
    req = Request.parse("GET / HTTP/1.1\r\nCache-Control: only-if-cached, max-stale=30\r\n\r\n")
    cc = req.cache_control
    expect(cc.only_if_cached?).to eq(true)
    expect(cc.max_stale).to eq(30)

  it "is an empty CacheControl when the header is absent" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.cache_control.empty?).to eq(true)

describe "Response#cache_control" ->
  it "reads back what Response#cache wrote" ->
    resp = Response.ok("hi").cache(3600)
    cc = resp.cache_control
    expect(cc.public?).to eq(true)
    expect(cc.max_age).to eq(3600)

  it "reads back a private cache directive" ->
    resp = Response.ok("hi").cache(60, {public: false})
    expect(resp.cache_control.private?).to eq(true)

  it "reads back what Response#no_cache wrote" ->
    resp = Response.ok("hi").no_cache
    cc = resp.cache_control
    expect(cc.no_store?).to eq(true)
    expect(cc.no_cache?).to eq(true)
    expect(cc.must_revalidate?).to eq(true)

  it "finds the header case-insensitively" ->
    resp = Response.ok("hi").header("cache-control", "max-age=99, immutable")
    cc = resp.cache_control
    expect(cc.max_age).to eq(99)
    expect(cc.immutable?).to eq(true)

  it "is an empty CacheControl when no Cache-Control header is set" ->
    resp = Response.ok("hi")
    expect(resp.cache_control.empty?).to eq(true)

spec_summary
