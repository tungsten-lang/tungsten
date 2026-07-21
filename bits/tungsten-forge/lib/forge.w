# Forge — high-performance HTTP server for Tungsten
# TLS by default, HTTP/3 (QUIC), work-stealing thread pool

use version
use query_string
use cookie
use multipart
use negotiation
use byte_range
use forwarded
use http_date
use conditional
use cache_control
use request
use response
use router
use thread_pool
use tls
use middleware
use static
use websocket
use connection
use listener
use server

+ Forge
  ro :config
  ro :router
  ro :server
  ro :middleware_chain
  ro :started_at

  @@instance = nil

  -> .instance
    @@instance = @@instance || self.new

  # Drop the singleton — next .instance call builds a fresh one.
  # Used by the specs to isolate examples.
  -> .reset
    @@instance = nil

  # Forge.configure -> (config) ... — yields the Config object.
  # Dual-form like Router#get: block binding diverges between engines
  # (interp binds trailing blocks to &, compiled binds positional
  # lambdas), so accept either a positional setup lambda or a block.
  -> .configure(setup = nil, &)
    if setup == nil
      setup = -> (c) &(c)
    self.instance.configure(setup)

  # Forge.routes -> (r) ... — yields the Router object.
  -> .routes(registrar = nil, &)
    if registrar == nil
      registrar = -> (r) &(r)
    self.instance.router.draw(registrar)

  -> .use(middleware, options = {})
    self.instance.middleware_chain.add(middleware, options)

  -> .start
    self.instance.start

  # Minimal live-server API: bind host:port and serve HTTP/1.1 with the
  # routes registered via Forge.routes. Compiled-only (Socket is a
  # compiled-runtime builtin). Blocks until the process is stopped.
  -> .run(host = "127.0.0.1", port = 8080)
    self.instance.run(host, port)

  -> .stop
    self.instance.stop

  -> .uptime
    return 0 unless self.instance.started_at
    Time.now - self.instance.started_at

  # --- Instance ---

  -> new
    @config = Config.new
    @router = Router.new
    @middleware_chain = MiddlewareChain.new
    @server = nil
    @started_at = nil

  -> configure(setup)
    setup.call(@config)
    self

  -> run(host, port)
    @config.host = host
    @config.port = port
    self.start

  # v1 live path: single-threaded HTTP/1.1 Server (see server.w).
  # ThreadPool / Listener / TLS wiring returns when those layers land.
  -> start
    @config.validate!

    @server = Server.new(@router, @middleware_chain, @config)
    # NOTE: no wall-clock stamp — Time/Instant.now are not implemented in
    # either engine yet, so @started_at stays nil and uptime reports 0.
    << "Forge [Version.string] listening on http://[@config.host]:[@config.port] (HTTP/1.1)"

    @server.start

  -> stop
    if @server
      << "Forge shutting down..."
      @server.stop
      @started_at = nil


  # --- Configuration DSL ---

+ Config
  rw :host
  rw :port
  rw :workers
  rw :max_connections
  rw :protocols
  rw :normalize_paths
  rw :read_timeout
  rw :write_timeout
  rw :idle_timeout
  rw :static_dir
  rw :cache_control
  rw :etag
  rw :tls_config

  -> new
    @host            = "0.0.0.0"
    @port            = 443
    @workers         = Config.detect_cpu_count
    @max_connections = 10_000
    @protocols       = [:h3, :h2, :http11]
    @normalize_paths = true
    @read_timeout    = 30
    @write_timeout   = 30
    @idle_timeout    = 120
    @static_dir      = nil
    @cache_control   = "public, max-age=3600"
    @etag            = true
    @tls_config      = {enabled: true, auto: false}

  # Active CPU count. Mirrors core/system.w System.cpu_count — that class
  # is not registered in the core autoload manifest yet, so bits cannot
  # reference it. TODO: switch to System.cpu_count once core/tungsten.w
  # carries an `auto :System` entry.
  -> .detect_cpu_count
    raw = capture("sysctl -n hw.activecpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1")
    return 1 if raw == nil
    count = raw.strip.to_i
    return 1 if count < 1
    count

  -> tls(options = {})
    @tls_config = {enabled: true}.merge(options)

  -> tls_description
    if @tls_config[:auto] == true
      return "auto (Let's Encrypt)"
    if @tls_config[:enabled] == false
      return "disabled"
    "enabled"

  -> validate!
    <! ConfigError.new("Host is required") unless @host
    <! ConfigError.new("Port must be positive") unless @port > 0
    <! ConfigError.new("Workers must be positive") unless @workers > 0

+ ConfigError < Error
