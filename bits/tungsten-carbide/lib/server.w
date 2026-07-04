# Carbide::Server — boot wiring for Forge + goroutine scheduler
# Connects the Carbide application to the Forge HTTP server

in Tungsten:Carbide

+ Server

  -> .start(port: 3000, host: "0.0.0.0", workers: 0)
    app = Carbide:Application.instance

    unless app && app.booted
      raise "Carbide application not initialized. Call Carbide.app.initialize! first."

    # Initialize the M:P goroutine scheduler
    Scheduler.init
    Scheduler.start(workers)  # 0 = auto-detect CPU count

    # Build the Forge server with Carbide as the request handler
    listener = Forge:Listener.new(
      host: host,
      port: port,
      tls: app.config.tls || {enabled: false},
      protocols: [:http11]
    )

    server = Forge:Server.new(
      listener: listener,
      router: app.routes,
      middleware: app.middleware,
      config: app.config
    )

    Logger.info("Carbide #{Carbide::VERSION} starting on #{host}:#{port} (#{app.environment})")
    Logger.info("=> Use Ctrl-C to stop")

    server.start

  -> .stop
    Scheduler.stop
