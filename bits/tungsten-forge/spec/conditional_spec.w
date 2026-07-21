# Forge conditional-request specs — ETag (RFC 7232 §2.3 entity-tag parsing
# and §2.3.2 strong/weak comparison) and Conditional (the RFC 7232 §6
# precedence over If-Match / If-Unmodified-Since / If-None-Match /
# If-Modified-Since), plus the Request delegators (#date, #if_none_match,
# #if_match, #if_modified_since, #if_unmodified_since, #preconditions).
# Before this the request surface could not evaluate any precondition, so
# 304 Not Modified and 412 Precondition Failed were unreachable.
#
# Pure header logic and HttpDate: no sockets, no clock. Requests are built
# with Request.parse, so every example runs under both engines. Symbols
# (:ok / :not_modified / :precondition_failed / :any) compare by value.

use spec_helper

describe "ETag.parse" ->
  it "is nil for nil or empty input" ->
    expect(ETag.parse(nil)).to be_nil
    expect(ETag.parse("")).to be_nil

  it "parses a single strong tag" ->
    tags = ETag.parse("\"xyzzy\"")
    expect(tags.size).to eq(1)
    expect(tags[0][:tag]).to eq("xyzzy")
    expect(tags[0][:weak]).to eq(false)

  it "parses a weak tag" ->
    tags = ETag.parse("W/\"xyzzy\"")
    expect(tags[0][:tag]).to eq("xyzzy")
    expect(tags[0][:weak]).to eq(true)

  it "parses a comma-separated list, mixed strong and weak" ->
    tags = ETag.parse("\"a\", W/\"b\", \"c\"")
    expect(tags.size).to eq(3)
    expect(tags[0][:tag]).to eq("a")
    expect(tags[1][:weak]).to eq(true)
    expect(tags[2][:tag]).to eq("c")

  it "recognises the wildcard as :any" ->
    expect(ETag.parse("*")).to eq(:any)

  it "keeps a comma that occurs inside a quoted opaque-tag" ->
    tags = ETag.parse("\"a,b\", \"c\"")
    expect(tags.size).to eq(2)
    expect(tags[0][:tag]).to eq("a,b")
    expect(tags[1][:tag]).to eq("c")

  it "skips an unquoted (malformed) member" ->
    tags = ETag.parse("bogus, \"good\"")
    expect(tags.size).to eq(1)
    expect(tags[0][:tag]).to eq("good")

describe "ETag.compare (RFC 7232 §2.3.2)" ->
  it "strong comparison requires equal opaque forms and neither weak" ->
    strong_a = {weak: false, tag: "x"}
    strong_b = {weak: false, tag: "x"}
    expect(ETag.compare(strong_a, strong_b, :strong)).to eq(true)

  it "strong comparison fails when either tag is weak" ->
    weak = {weak: true, tag: "x"}
    strong = {weak: false, tag: "x"}
    expect(ETag.compare(weak, strong, :strong)).to eq(false)

  it "weak comparison ignores the weakness flags" ->
    weak = {weak: true, tag: "x"}
    strong = {weak: false, tag: "x"}
    expect(ETag.compare(weak, strong, :weak)).to eq(true)

  it "any comparison fails on differing opaque forms" ->
    a = {weak: false, tag: "x"}
    b = {weak: false, tag: "y"}
    expect(ETag.compare(a, b, :weak)).to eq(false)

describe "ETag.list_matches?" ->
  it "matches the wildcard against any present representation" ->
    expect(ETag.list_matches?(:any, {weak: false, tag: "x"}, :strong)).to eq(true)

  it "matches when a list member equals the resource tag" ->
    list = ETag.parse("\"a\", \"b\"")
    expect(ETag.list_matches?(list, {weak: false, tag: "b"}, :strong)).to eq(true)

  it "does not match when no member equals the resource tag" ->
    list = ETag.parse("\"a\", \"b\"")
    expect(ETag.list_matches?(list, {weak: false, tag: "z"}, :strong)).to eq(false)

  it "does not match a specific tag when the resource has none" ->
    list = ETag.parse("\"a\"")
    expect(ETag.list_matches?(list, nil, :weak)).to eq(false)

describe "Request conditional delegators" ->
  it "parses the Date header to epoch seconds" ->
    req = Request.parse("GET / HTTP/1.1\r\nDate: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.date).to eq(784111777)

  it "parses If-Modified-Since and If-Unmodified-Since to epochs" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-Modified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\nIf-Unmodified-Since: Thu, 01 Jan 1970 00:00:00 GMT\r\n\r\n")
    expect(req.if_modified_since).to eq(784111777)
    expect(req.if_unmodified_since).to eq(0)

  it "parses If-None-Match to entity-tags and If-Match to :any" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-None-Match: W/\"v1\"\r\nIf-Match: *\r\n\r\n")
    expect(req.if_none_match[0][:tag]).to eq("v1")
    expect(req.if_none_match[0][:weak]).to eq(true)
    expect(req.if_match).to eq(:any)

  it "is nil for an absent conditional header" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.date).to be_nil
    expect(req.if_modified_since).to be_nil
    expect(req.if_none_match).to be_nil

describe "Request#preconditions — If-None-Match" ->
  it "is :not_modified when a GET's tag matches (weak comparison)" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-None-Match: \"v1\"\r\n\r\n")
    expect(req.preconditions("\"v1\"", nil)).to eq(:not_modified)

  it "matches a weak request tag against a strong resource tag" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-None-Match: W/\"v1\"\r\n\r\n")
    expect(req.preconditions("\"v1\"", nil)).to eq(:not_modified)

  it "is :ok when the tag does not match" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-None-Match: \"v1\"\r\n\r\n")
    expect(req.preconditions("\"v2\"", nil)).to eq(:ok)

  it "is :precondition_failed for a matching tag on an unsafe method" ->
    req = Request.parse("PUT / HTTP/1.1\r\nIf-None-Match: \"v1\"\r\n\r\n")
    expect(req.preconditions("\"v1\"", nil)).to eq(:precondition_failed)

  it "wildcard matches any current representation" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-None-Match: *\r\n\r\n")
    expect(req.preconditions("\"anything\"", nil)).to eq(:not_modified)

describe "Request#preconditions — If-Modified-Since" ->
  it "is :not_modified when the resource is no newer than the date" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-Modified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions(nil, 784000000)).to eq(:not_modified)

  it "is :ok when the resource is newer than the date" ->
    req = Request.parse("GET / HTTP/1.1\r\nIf-Modified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions(nil, 785000000)).to eq(:ok)

  it "is ignored for an unsafe method" ->
    req = Request.parse("POST / HTTP/1.1\r\nIf-Modified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions(nil, 784000000)).to eq(:ok)

describe "Request#preconditions — If-Match (strong)" ->
  it "is :ok when a tag matches" ->
    req = Request.parse("PUT / HTTP/1.1\r\nIf-Match: \"v1\"\r\n\r\n")
    expect(req.preconditions("\"v1\"", nil)).to eq(:ok)

  it "is :precondition_failed when no tag matches" ->
    req = Request.parse("PUT / HTTP/1.1\r\nIf-Match: \"v1\"\r\n\r\n")
    expect(req.preconditions("\"v2\"", nil)).to eq(:precondition_failed)

  it "fails a weak request tag under strong comparison" ->
    req = Request.parse("PUT / HTTP/1.1\r\nIf-Match: W/\"v1\"\r\n\r\n")
    expect(req.preconditions("\"v1\"", nil)).to eq(:precondition_failed)

describe "Request#preconditions — If-Unmodified-Since" ->
  it "is :ok when the resource is no newer than the date" ->
    req = Request.parse("PUT / HTTP/1.1\r\nIf-Unmodified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions(nil, 784000000)).to eq(:ok)

  it "is :precondition_failed when the resource is newer than the date" ->
    req = Request.parse("PUT / HTTP/1.1\r\nIf-Unmodified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions(nil, 785000000)).to eq(:precondition_failed)

describe "Request#preconditions — RFC 7232 §6 precedence" ->
  it "evaluates If-Match ahead of If-Unmodified-Since" ->
    # If-Match matches, so the failing If-Unmodified-Since is not consulted.
    req = Request.parse("PUT / HTTP/1.1\r\nIf-Match: \"v1\"\r\nIf-Unmodified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions("\"v1\"", 785000000)).to eq(:ok)

  it "evaluates If-None-Match ahead of If-Modified-Since" ->
    # If-None-Match does not match, so the resource is served even though
    # If-Modified-Since alone would have yielded 304.
    req = Request.parse("GET / HTTP/1.1\r\nIf-None-Match: \"v2\"\r\nIf-Modified-Since: Sun, 06 Nov 1994 08:49:37 GMT\r\n\r\n")
    expect(req.preconditions("\"v1\"", 784000000)).to eq(:ok)

  it "is :ok when no precondition header is present" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.preconditions("\"v1\"", 784000000)).to eq(:ok)

spec_summary
