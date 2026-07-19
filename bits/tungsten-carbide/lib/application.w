# Carbide — the application object: routes + the live Forge server.
#
# A Carbide app registers routes on a Route:Set and serves them through
# forge's HTTP/1.1 Server (bits/tungsten-forge). Route:Set duck-types the
# forge Router interface (#resolve -> match with .params/.handler), so
# the forge Server consults carbide's routing core directly — no
# translation layer.
#
#   use application
#
#   + HelloController < Controller
#     -> index
#       render_text("hi")
#
#   routes = Carbide.instance.routes
#   routes.get("/hello", HelloController, -> (c) c.index)
#   Carbide.run("127.0.0.1", 8080)
#
# Serving is COMPILED-ONLY (forge's Socket path); pure dispatch —
# Carbide.instance.dispatch(request) — works in both engines and is what
# the specs exercise.

use forge
use route
use controller

+ Carbide
  ro :routes

  @@instance = nil

  -> .instance
    @@instance = @@instance || self.new

  # Drop the singleton — next .instance call builds a fresh one.
  # Used by the specs to isolate examples.
  -> .reset
    @@instance = nil

  # Boot and serve over forge HTTP/1.1. Compiled-only; blocks until the
  # process is stopped.
  -> .run(host = "127.0.0.1", port = 8080)
    self.instance.run(host, port)

  # --- Instance ---

  -> new
    @routes = Route:Set.new

  # Pure request -> response dispatch (both engines, no sockets).
  -> dispatch(request)
    @routes.dispatch(request)

  # Serve via forge: our Route:Set rides in as the forge Server's router.
  -> run(host, port)
    config = Config.new
    config.host = host
    config.port = port
    server = Server.new(@routes, MiddlewareChain.new, config)
    << "Carbide serving on http://[host]:[port] via Forge (HTTP/1.1)"
    server.start
