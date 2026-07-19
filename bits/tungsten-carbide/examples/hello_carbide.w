# Minimal live Carbide app — routes + controllers served through forge's
# HTTP/1.1 Server. Compiled-only: Socket is a compiled-runtime builtin.
#
# Compile and run (from the repo root):
#   bin/tungsten -o /tmp/carbide_hello bits/tungsten-carbide/examples/hello_carbide.w
#   /tmp/carbide_hello 18100
#
# Then:
#   curl -i http://127.0.0.1:18100/hello
#   curl -i http://127.0.0.1:18100/users/42
#   curl -i -X POST -d 'ping' http://127.0.0.1:18100/echo
#   curl -i http://127.0.0.1:18100/missing      # -> 404
#
# The port is the first CLI argument (default 18100). `use application`
# rather than `use carbide`: the bit manifest carries the CLI entry
# (run_cli), and compiled binaries execute use'd top-level code.

use application

+ HelloController < Controller
  -> index
    render_text("carbide says hello")

+ UsersController < Controller
  -> show
    render_text("user " + param(:id).to_s)

+ EchoController < Controller
  -> create
    render_text("echo:" + @request.body.to_s)

port = 18100
args = argv()
if args.size > 0
  port = args[0].to_i

routes = Carbide.instance.routes
routes.get("/hello", HelloController, -> (c) c.index)
routes.get("/users/:id", UsersController, -> (c) c.show)
routes.post("/echo", EchoController, -> (c) c.create)

Carbide.run("127.0.0.1", port)
