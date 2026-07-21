# Forge request-parsing specs — QueryString (application/x-www-form-
# urlencoded) and the Request methods that delegate to it
# (Request#query_params over the "?..." portion, Request#form_body over a
# form POST body). Before QueryString existed both delegators referenced
# an undefined class and crashed at runtime; these lock in the behaviour.
#
# No sockets: requests are built with Request.parse, so everything here
# runs under both engines (interpreted and compiled).
#
# Style note: never chain a call off a `?` method (`form?.to_s` lexes as
# safe navigation, which the interpreter does not implement).

use spec_helper

describe "QueryString.parse" ->
  it "splits pairs on & and key/value on the first =" ->
    q = QueryString.parse("a=1&b=2")
    expect(q["a"]).to eq("1")
    expect(q["b"]).to eq("2")

  it "keeps everything after the first = in the value" ->
    q = QueryString.parse("token=a=b=c")
    expect(q["token"]).to eq("a=b=c")

  it "decodes + to a space" ->
    q = QueryString.parse("name=hello+world")
    expect(q["name"]).to eq("hello world")

  it "percent-decodes ASCII escapes" ->
    q = QueryString.parse("path=%2Fusers%2F42&op=%3D")
    expect(q["path"]).to eq("/users/42")
    expect(q["op"]).to eq("=")

  it "treats a valueless key as present with an empty value" ->
    q = QueryString.parse("debug&page=2")
    expect(q["debug"]).to eq("")
    expect(q["page"]).to eq("2")

  it "keeps an explicit empty value" ->
    q = QueryString.parse("q=")
    expect(q["q"]).to eq("")

  it "skips empty pairs from stray or trailing ampersands" ->
    q = QueryString.parse("&a=1&&b=2&")
    expect(q["a"]).to eq("1")
    expect(q["b"]).to eq("2")

  it "lets the last value win for a duplicate key" ->
    q = QueryString.parse("x=1&x=2&x=3")
    expect(q["x"]).to eq("3")

  it "returns an empty hash for nil or empty input" ->
    expect(QueryString.parse(nil).size).to eq(0)
    expect(QueryString.parse("").size).to eq(0)

  it "decodes percent-escapes in the key too" ->
    q = QueryString.parse("a%20b=c")
    expect(q["a b"]).to eq("c")

describe "QueryString.decode" ->
  it "leaves a malformed percent-escape literal" ->
    expect(QueryString.decode("a%ZZb")).to eq("a%ZZb")

  it "leaves a truncated trailing percent literal" ->
    expect(QueryString.decode("100%")).to eq("100%")

  it "decodes lowercase and uppercase hex digits alike" ->
    expect(QueryString.decode("%2f%2F")).to eq("//")

describe "Request#query_params" ->
  it "parses the query string of a parsed request" ->
    req = Request.parse("GET /search?name=John+Doe&city=NYC HTTP/1.1\r\nHost: x\r\n\r\n")
    params = req.query_params
    expect(params["name"]).to eq("John Doe")
    expect(params["city"]).to eq("NYC")

  it "is nil when the request has no query string" ->
    req = Request.parse("GET /plain HTTP/1.1\r\nHost: x\r\n\r\n")
    params = req.query_params
    expect(params).to be_nil

describe "Request#form_body" ->
  it "parses an urlencoded form POST body" ->
    req = Request.parse("POST /f HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 15\r\n\r\na=1&b=two+words")
    form = req.form_body
    expect(form["a"]).to eq("1")
    expect(form["b"]).to eq("two words")

  it "is nil when the content type is not a form" ->
    req = Request.parse("POST /f HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 7\r\n\r\na=1&b=2")
    form = req.form_body
    expect(form).to be_nil

describe "Cookie.parse" ->
  it "splits pairs on ; and name/value on the first =" ->
    c = Cookie.parse("sessionid=abc123; theme=dark")
    expect(c["sessionid"]).to eq("abc123")
    expect(c["theme"]).to eq("dark")

  it "keeps everything after the first = in the value" ->
    c = Cookie.parse("token=a=b=c")
    expect(c["token"]).to eq("a=b=c")

  it "trims whitespace around names and values" ->
    c = Cookie.parse("  a = 1 ;   b=2  ")
    expect(c["a"]).to eq("1")
    expect(c["b"]).to eq("2")

  it "treats a valueless segment as present with an empty value" ->
    c = Cookie.parse("consent; page=2")
    expect(c["consent"]).to eq("")
    expect(c["page"]).to eq("2")

  it "keeps an explicit empty value" ->
    c = Cookie.parse("q=")
    expect(c["q"]).to eq("")

  it "unwraps a double-quoted value" ->
    c = Cookie.parse("token=\"abc def\"")
    expect(c["token"]).to eq("abc def")

  it "does not percent-decode cookie octets" ->
    c = Cookie.parse("path=%2Fusers%2F42")
    expect(c["path"]).to eq("%2Fusers%2F42")

  it "lets the first value win for a duplicate name" ->
    c = Cookie.parse("x=1; x=2; x=3")
    expect(c["x"]).to eq("1")

  it "skips empty segments from stray or trailing semicolons" ->
    c = Cookie.parse("; a=1;; b=2;")
    expect(c["a"]).to eq("1")
    expect(c["b"]).to eq("2")

  it "skips a segment whose name is empty" ->
    c = Cookie.parse("=orphan; real=yes")
    expect(c.key?("real")).to eq(true)
    expect(c.size).to eq(1)

  it "returns an empty hash for nil or empty input" ->
    expect(Cookie.parse(nil).size).to eq(0)
    expect(Cookie.parse("").size).to eq(0)

describe "Request#cookies" ->
  it "parses the Cookie header of a parsed request" ->
    req = Request.parse("GET /x HTTP/1.1\r\nHost: x\r\nCookie: sid=42; theme=dark\r\n\r\n")
    jar = req.cookies
    expect(jar["sid"]).to eq("42")
    expect(jar["theme"]).to eq("dark")

  it "is an empty hash when the request has no Cookie header" ->
    req = Request.parse("GET /x HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.cookies.size).to eq(0)

describe "Request#cookie" ->
  it "returns a single cookie value by name" ->
    req = Request.parse("GET /x HTTP/1.1\r\nCookie: sid=42; theme=dark\r\n\r\n")
    expect(req.cookie("theme")).to eq("dark")

  it "is nil for an absent cookie" ->
    req = Request.parse("GET /x HTTP/1.1\r\nCookie: sid=42\r\n\r\n")
    expect(req.cookie("nope")).to be_nil

spec_summary
