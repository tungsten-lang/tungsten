# tungsten-api — HTTP execution service for agents without a local toolchain.
#
# The endpoints behind api.tungsten-lang.org: POST a Tungsten program, get back
# stdout/stderr/exit code and structured diagnostics. An agent that cannot
# install the compiler in its sandbox can still write Tungsten, check it, run
# it, and read the results.
#
#   POST /api/check     -> diagnostics only; never executes
#   POST /api/run       -> compile, then run with the sandbox gate latched
#   GET  /api/version   -> version, engine, and the current limits
#   GET  /api/health    -> liveness
#
# Request body is either the bare source (Content-Type: text/plain) or JSON
# {"source": "..."}. Response is always application/json — see
# services/api/lib/exec.w, which owns compilation, timeouts, output caps,
# diagnostic parsing, and outcome classification. This file is only the HTTP
# surface, and it calls the engine in-process.
#
# Build and run (from the repo root):
#   bin/tungsten -o /tmp/tungsten_api services/api/server.w
#   /tmp/tungsten_api 18099
#
#   curl -sS --data-binary '<< 1 + 1' http://127.0.0.1:18099/api/run
#
# Compiled-only: Socket and OS.capture are compiled-runtime builtins.
#
# DEPLOYMENT — this cannot run on Cloudflare Workers/Pages. Executing a
# program means fork+exec of a native binary, which a Workers isolate cannot
# do at all. It needs a VM or container with the toolchain installed; front it
# with Cloudflare DNS/proxy for TLS, caching, and rate limiting. Before taking
# public traffic, add an OS-level jail (nsjail/bubblewrap/Firecracker), rlimits
# for memory and process count, and per-IP rate limiting: the Tungsten sandbox
# bounds a program's REACH and logs its attempts, but ccall can still call any
# linked symbol, and nothing here caps memory or stops a fork bomb.

use forge
use lib/exec

MAX_SOURCE_BYTES = 262144

# Responses always go through Response.json — never hand-written JSON, because
# `[` and `]` inside a Tungsten string literal interpolate.
-> error_response(message, status)
  Response.json({ok: false, error: message, diagnostics: []}, {status: status})

# Pull the program out of the request: JSON {"source": …} when the caller sent
# JSON, otherwise the raw body.
#
# The String check is load-bearing, not defensive clutter: `{"source": 12345}`
# yields an Integer, and calling .size() on it is an "undefined method" abort —
# which is FATAL and NOT catchable by begin/rescue, so it kills the whole
# server process rather than failing one request. Every value that reaches
# execute() must be type-checked here.
-> extract_source(req)
  raw = req.body
  if raw == nil
    return nil
  if req.json?
    parsed = req.json_body
    if parsed == nil
      return nil
    found = parsed["source"]
    if type(found) != "String"
      return nil
    return found
  if type(raw) != "String"
    return nil
  raw

# Shared path for both modes. The engine runs IN-PROCESS (services/api/lib/exec.w)
# and returns the response document as a Hash, so there is no second interpreter
# to shell out to and no JSON round-trip between layers. The program text never
# reaches a shell: the engine writes it to a file and passes only that path.
-> execute(req, mode)
  source = extract_source(req)
  if source == nil || source == ""
    return error_response("request body must be Tungsten source, or JSON {\"source\": \"...\"}", 400)
  if source.size() > MAX_SOURCE_BYTES
    return error_response("source exceeds " + MAX_SOURCE_BYTES.to_s + " bytes", 413)

  Response.json(ApiExec.execute(source, mode))

# Capability discovery: what an agent needs to know before posting.
-> version_response
  version = env("TUNGSTEN_VERSION")
  if version == nil || version == ""
    version = "dev"
  endpoints = []
  endpoints.push("POST /api/check")
  endpoints.push("POST /api/run")
  endpoints.push("GET /api/version")
  endpoints.push("GET /api/health")
  Response.json({ok: true, version: version, engine: "compiled", max_source_bytes: MAX_SOURCE_BYTES, endpoints: endpoints})

# A raised exception escaping a handler kills the connection thread AND the
# process, so every request path is wrapped. This catches `raise`d errors only —
# an "undefined method" abort is fatal and unwinds past any rescue, which is why
# extract_source type-checks its result instead of relying on this net.
-> guarded(req, mode)
  begin
    execute(req, mode)
  rescue e
    << "handler error (" + mode + "): [e]"
    error_response("internal error handling request", 500)

router = Forge.instance.router

router.post("/api/check", -> (req) guarded(req, "check"))
router.post("/api/run", -> (req) guarded(req, "run"))
router.get("/api/version", -> (req) version_response)
router.get("/api/health", -> (req) Response.json({ok: true}))

port = 18099
args = argv()
if args.size > 0
  port = args[0].to_i

host = env("TUNGSTEN_API_HOST")
if host == nil || host == ""
  host = "127.0.0.1"

<< "tungsten-api listening on [host]:[port]"
Forge.run(host, port)
