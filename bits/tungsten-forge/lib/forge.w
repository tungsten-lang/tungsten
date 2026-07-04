# Forge — high-performance HTTP server for Tungsten
# TLS by default, HTTP/3 (QUIC), work-stealing thread pool

in Tungsten

use version
use server
use router
use thread_pool
use tls
use middleware
use static
use websocket

+ Forge
  ro :config
  ro :router
  ro :server
  ro :middleware_chain
  ro :started_at

  @@instance = nil

  -> .instance
    @@instance = @@instance || self.new

  -> .configure(&block)
    self.instance.configure(&block)

  -> .routes(&block)
    self.instance.router.draw(&block)

  -> .use(middleware, **options)
    self.instance.middleware_chain.add(middleware, **options)

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
    @middleware_chain = Middleware:Chain.new
    @server = nil
    @started_at = nil

  -> configure(&block)
    @config.instance_eval(&block)
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
    Logger.info("Forge [Version:VERSION] ignited on [@config.host]:[@config.port]")
    Logger.info("  Workers: [@config.workers]")
    Logger.info("  TLS: [@config.tls_description]")
    Logger.info("  Protocols: [@config.protocols.join(", ")]")

    @server.start

  -> stop
    if @server
      Logger.info("Forge shutting down...")
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
      @workers         = System.cpu_count
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

    -> tls(**options)
      @tls_config = {enabled: true}.merge(options)

    -> tls_description
      case @tls_config
        {auto: true} => "auto (Let's Encrypt)"
        {enabled: true} => "enabled"
        {enabled: false} => "disabled"
        => "enabled"

    -> validate!
      <! ConfigError.new("Host is required") unless @host
      <! ConfigError.new("Port must be positive") unless @port > 0
      <! ConfigError.new("Workers must be positive") unless @workers > 0

  + ConfigError < StandardError
