# Minimal live Forge app — HTTP/1.1 over the compiled runtime Socket.
#
# Compile and run (from the repo root):
#   bin/tungsten -o /tmp/forge_hello bits/tungsten-forge/examples/hello.w
#   /tmp/forge_hello 18090
#
# Then:
#   curl -i http://127.0.0.1:18090/hello
#   curl -i http://127.0.0.1:18090/users/42
#   curl -i http://127.0.0.1:18090/missing      # -> 404
#
# The port is the first CLI argument (default 18090). Compiled-only:
# Socket is a compiled-runtime builtin the interpreter cannot resolve.

use forge

port = 18090
args = argv()
if args.size > 0
  port = args[0].to_i

# Positional-lambda route registration (the form that works compiled;
# see compiled_smoke.w — trailing blocks on class methods are interp-only).
router = Forge.instance.router
router.get("/hello", -> (req) Response.text("world"))
router.get("/users/:id", -> (req) Response.text("user " + req.params[:id]))
router.post("/echo", -> (req) Response.text("echo:" + req.body.to_s))

Forge.run("127.0.0.1", port)
