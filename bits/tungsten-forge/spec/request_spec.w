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

spec_summary
