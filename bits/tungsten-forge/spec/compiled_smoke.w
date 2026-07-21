# Forge smoke check — runs under BOTH engines and self-verifies:
#   interpreted:  bin/tungsten bits/tungsten-forge/spec/compiled_smoke.w
#   compiled:     bin/tungsten -o /tmp/forge_smoke bits/tungsten-forge/spec/compiled_smoke.w && /tmp/forge_smoke
#
# Guards the spec-covered surface (Router resolution, Response building,
# Config validation) against compiled/interpreted divergence. Prints
# "SMOKE OK <n> checks" and exits 0 on success; exits 1 on any failure.

use forge

$smoke_fail = 0
$smoke_total = 0

-> check(name, ok)
  $smoke_total += 1
  if ok != true
    $smoke_fail += 1
    << "SMOKE FAIL: " + name

router = Router.new
router.get("/users", -> (req) Response.ok("users"))
router.get("/users/:id", -> (req) Response.text("user"))
router.post("/users", -> (req) Response.text("created"))

check("exact path resolves", router.resolve(:GET, "/users") != nil)
check("unknown path is nil", router.resolve(:GET, "/zzz") == nil)
check("method mismatch is nil", router.resolve(:DELETE, "/users") == nil)
check("case-insensitive match", router.resolve(:GET, "/USERS") != nil)
check("trailing slash stripped", router.resolve(:GET, "/users/") != nil)

m = router.resolve(:GET, "/users/42")
check("dynamic segment matches", m != nil)
check("dynamic segment captured", m.params[:id] == "42")

invoked = m.handler.call(nil)
check("handler invocable", invoked != nil)
check("handler response body", invoked.body == "user")
check("handler response status", invoked.status == 200)

api = Router.new
api.get("/bits", -> (req) Response.text("bits"))
root = Router.new
root.mount("/api/v1", api)
check("mounted route resolves", root.resolve(:GET, "/api/v1/bits") != nil)

r = Response.ok("hello")
check("ok status", r.status == 200)
check("ok body", r.body == "hello")
check("ok content type", r.headers["Content-Type"] == "text/html; charset=utf-8")

r2 = Response.not_found
check("not_found status", r2.status == 404)

r3 = Response.text("plain")
check("text content type", r3.headers["Content-Type"] == "text/plain")

http = r.to_http
check("to_http status line", http.starts_with?("HTTP/1.1 200 OK"))
check("to_http carries body", http.ends_with?("hello"))

# Request.parse — the live server's wire-in point (single-pass
# index(needle, offset) scanner; must behave identically in both engines).
raw = "GET /users/42?x=1 HTTP/1.1\r\nHost: localhost\r\nX-Test: yes\r\n\r\n"
req = Request.parse(raw)
check("parse method", req.method == :GET)
check("parse path", req.path == "/users/42")
check("parse query string", req.query_string == "x=1")
check("parse version", req.version == "HTTP/1.1")
check("parse header", req.headers.get("host") == "localhost")
check("parse second header", req.headers.get("X-TEST") == "yes")

post = Request.parse("POST /echo HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
check("parse post method", post.method == :POST)
check("parse post body", post.body == "hello")

bad = Request.parse("GARBAGE\r\n\r\n")
check("parse malformed is nil", bad == nil)

# Parse edges — the single-pass scanner's torture set. Malformed means
# exactly what it meant for the old split parser: a request line with
# fewer than three single-space-separated fields.
check("parse missing version is nil", Request.parse("GET /\r\n\r\n") == nil)
check("parse method only is nil", Request.parse("GET\r\n\r\n") == nil)
check("parse empty is nil", Request.parse("") == nil)
check("parse leading blank line is nil", Request.parse("\r\nGET / HTTP/1.1\r\n\r\n") == nil)

colonv = Request.parse("GET / HTTP/1.1\r\nX-Weird: a: b\r\n\r\n")
check("parse ': ' in header value", colonv.headers.get("x-weird") == "a: b")
emptyv = Request.parse("GET / HTTP/1.1\r\nX-Empty: \r\n\r\n")
check("parse empty header value", emptyv.headers.get("x-empty") == "")
nospace = Request.parse("GET / HTTP/1.1\r\nX-Odd:nospace\r\nHost: h\r\n\r\n")
check("parse colon-no-space line skipped", nospace.headers.get("x-odd") == nil)
check("parse line after skipped line kept", nospace.headers.get("Host") == "h")

# Duplicate headers: LAST value wins (matches the old normalized-hash
# behavior and Server.content_length_in's rindex scan).
dup = Request.parse("GET / HTTP/1.1\r\nHost: a\r\nHOST: b\r\n\r\n")
check("parse duplicate header last-wins", dup.headers.get("host") == "b")

# Body honors Content-Length: a pipelined remainder is not swallowed.
pipe = Request.parse("POST /e HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET /next HTTP/1.1\r\n\r\n")
check("parse body stops at content-length", pipe.body == "hello")
short = Request.parse("POST /e HTTP/1.1\r\nContent-Length: 99\r\n\r\nshort")
check("parse body capped at available", short.body == "short")
nocl = Request.parse("POST /e HTTP/1.1\r\nHost: x\r\n\r\nrest")
check("parse no content-length keeps rest", nocl.body == "rest")

# CRLF edges: truncated head parses with body nil; a bare request line
# (no CRLF anywhere) parses too.
trunc = Request.parse("GET / HTTP/1.1\r\nHost: x")
check("parse truncated head header", trunc.headers.get("host") == "x")
check("parse truncated head body nil", trunc.body == nil)
barel = Request.parse("GET / HTTP/1.1")
check("parse bare request line", barel.version == "HTTP/1.1")
check("parse bare request line body nil", barel.body == nil)
noblank = Request.parse("GET / HTTP/1.1\r\n\r\n")
check("parse empty body is empty string", noblank.body == "")

# Literal-split parity: split(" ") never collapsed runs, so extra fields
# ride along and a fourth field is ignored.
four = Request.parse("GET / HTTP/1.1 extra\r\n\r\n")
check("parse fourth field ignored", four.version == "HTTP/1.1")

# Headers mutation contract (RequestIdMiddleware): set then get, any case.
mut = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
mut.headers.set("X-Request-Id", "abc")
check("headers set/get roundtrip", mut.headers.get("x-request-id") == "abc")
check("headers has? case-insensitive", mut.headers.has?("HOST") == true)

# Keep-alive semantics — the server's connection-loop wire-in. (Never
# chain off a `?` method: `keep_alive?.to_s` lexes as safe navigation,
# which the interpreter lacks — bind to a local first.)
ka = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n").keep_alive?
check("http11 defaults to keep-alive", ka == true)
ka = Request.parse("GET / HTTP/1.1\r\nConnection: Close\r\n\r\n").keep_alive?
check("http11 Connection: close honored", ka == false)
ka = Request.parse("GET / HTTP/1.0\r\nHost: x\r\n\r\n").keep_alive?
check("http10 defaults to close", ka == false)
ka = Request.parse("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n").keep_alive?
check("http10 keep-alive opt-in", ka == true)

# QueryString — the parser Request#query_params / #form_body delegate to.
# String keys, first-'=' split, '+'->space, ASCII percent-decode.
qs = QueryString.parse("a=1&b=hello+world&flag&dup=x&dup=y")
check("qs basic value", qs["a"] == "1")
check("qs plus is space", qs["b"] == "hello world")
check("qs valueless key empty", qs["flag"] == "")
check("qs duplicate last-wins", qs["dup"] == "y")
check("qs percent ascii decode", QueryString.parse("p=%2Fx%3Dy")["p"] == "/x=y")
check("qs first '=' splits, rest kept", QueryString.parse("t=a=b")["t"] == "a=b")
check("qs empty input empty hash", QueryString.parse("").size == 0)
check("qs nil input empty hash", QueryString.parse(nil).size == 0)
check("qs decode leaves bad escape", QueryString.decode("z%ZZ") == "z%ZZ")

qreq = Request.parse("GET /s?name=John+Doe&n=%32 HTTP/1.1\r\nHost: x\r\n\r\n")
qp = qreq.query_params
check("query_params decodes plus", qp["name"] == "John Doe")
check("query_params decodes percent", qp["n"] == "2")
noq = Request.parse("GET /plain HTTP/1.1\r\nHost: x\r\n\r\n").query_params
check("query_params nil without query", noq == nil)

freq = Request.parse("POST /f HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 11\r\n\r\na=1&b=two+3")
fb = freq.form_body
check("form_body parses field", fb["a"] == "1")
check("form_body decodes plus", fb["b"] == "two 3")
notform = Request.parse("POST /f HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 3\r\n\r\na=1").form_body
check("form_body nil for non-form", notform == nil)

# Authorization / Base64Codec — the pure base64 decode + Integer#chr
# reassembly must produce identical bytes compiled and interpreted.
check("base64 decode Man", Base64Codec.decode("TWFu") == "Man")
check("base64 decode padded", Base64Codec.decode("TQ==") == "M")
check("base64 decode creds", Base64Codec.decode("dXNlcjpwYXNz") == "user:pass")
check("base64 malformed nil", Base64Codec.decode("!!!!") == nil)
bearer = Request.parse("GET / HTTP/1.1\r\nAuthorization: Bearer abc.def\r\n\r\n")
check("bearer scheme", bearer.authorization.scheme == "bearer")
check("bearer token", bearer.bearer_token == "abc.def")
basic = Request.parse("GET / HTTP/1.1\r\nAuthorization: Basic dXNlcjpwYXNz\r\n\r\n")
ba = basic.basic_auth
check("basic username", ba[:username] == "user")
check("basic password", ba[:password] == "pass")
check("basic bearer_token nil", basic.bearer_token == nil)
noauth = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
check("no auth header nil", noauth.authorization == nil)

# Request framing (Server.request_length) — buffer carry across reads.
get1 = "GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
post1 = "POST /e HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"
check("framing empty buffer", Server.request_length("") == 0)
check("framing partial header", Server.request_length("GET / HTTP/1.1\r\nHost:") == 0)
check("framing bare GET", Server.request_length(get1) == get1.size)
check("framing with body", Server.request_length(post1) == post1.size)
check("framing body incomplete", Server.request_length("POST /e HTTP/1.1\r\nContent-Length: 5\r\n\r\nhel") == 0)
check("framing pipelined first only", Server.request_length(get1 + post1) == get1.size)

config = Config.new
check("default port", config.port == 443)
check("default host", config.host == "0.0.0.0")
check("workers positive", config.workers > 0)

config.port = -1
raised = false
begin
  config.validate!
rescue e
  raised = true
check("validate! raises on bad port", raised)

if $smoke_fail > 0
  << "SMOKE FAILED: [$smoke_fail] of [$smoke_total] checks"
  exit 1
<< "SMOKE OK [$smoke_total] checks"
