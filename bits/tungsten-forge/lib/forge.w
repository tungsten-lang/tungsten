# Forge — high-performance HTTP server for Tungsten
# TLS by default, HTTP/3 (QUIC), work-stealing thread pool

use version
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
  -> .configure(&)
    self.instance.configure(-> (c) &(c))

  # Forge.routes -> (r) ... — yields the Router object.
  -> .routes(&)
    self.instance.router.draw(-> (r) &(r))

  -> .use(middleware, options = {})
    self.instance.middleware_chain.add(middleware, options)

  -> .start
    self.instance.start

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

  -> start
    @config.validate!

    pool = ThreadPool.new(
      workers: @config.workers,
      max_queue: @config.max_connections
    )

    listener = Listener.new(
      host: @config.host,
      port: @config.port,
      tls: @config.tls_config,
      protocols: @config.protocols
    )

    @server = Server.new(
      listener: listener,
      pool: pool,
      router: @router,
      middleware: @middleware_chain,
      config: @config
    )

    @started_at = Time.now
    << "Forge [Version.string] ignited on [@config.host]:[@config.port]"
    << "  Workers: [@config.workers]"
    << "  TLS: [@config.tls_description]"
    << "  Protocols: [@config.protocols.join(", ")]"

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
