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

# Request.parse — the live server's wire-in point (split-based parser;
# must behave identically in both engines).
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
