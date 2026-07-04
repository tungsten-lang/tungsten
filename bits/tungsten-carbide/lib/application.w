# Carbide::Application — the application lifecycle manager
# Handles configuration, middleware stack, boot sequence, and request dispatch

in Tungsten:Carbide

+ Application
  ro :config
  ro :middleware
  ro :routes
  ro :environment
  ro :root
  ro :booted

  # Singleton instance
  @@instance = nil

  -> .instance
    @@instance

  -> new(config = {})
    @@instance   = self
    @config      = Config.new(config)
    @middleware  = MiddlewareStack.new
    @routes      = Route:Set.new
    @environment = ENV["CARBIDE_ENV"] || "development"
    @root        = Dir.pwd
    @booted      = false

  # Full boot sequence
  -> initialize!
    load_environment
    configure_defaults
    load_initializers
    build_middleware_stack
    load_routes
    @booted = true
    self

  -> load_environment
    env_file = "config/environments/#{@environment}.w"
    if File.exists?(env_file)
      use env_file

  -> configure_defaults
    @config.set_defaults(
      secret_key:       ENV["SECRET_KEY"],
      session_store:    :cookie,
      log_level:        case @environment
                          "production"  => :info
                          "test"        => :warn
                          =>              :debug,
      static_files:     @environment != "production",
      cache_classes:    @environment == "production",
      eager_load:       @environment == "production",
      force_ssl:        false,
      default_headers:  {
        "X-Frame-Options":        "SAMEORIGIN",
        "X-Content-Type-Options": "nosniff",
        "X-XSS-Protection":      "1; mode=block"
      }
    )

  -> load_initializers
    Dir.glob("config/initializers/**/*.w").sort.each -> (file)
      use file

  -> build_middleware_stack
    @middleware.use Middleware:RequestId
    @middleware.use Middleware:Logger
    @middleware.use Middleware:Static if @config.static_files
    @middleware.use Middleware:Session, store: @config.session_store
    @middleware.use Middleware:Params
    @middleware.use Middleware:Cookies
    @middleware.use Middleware:Flash
    @middleware.use Middleware:SSL if @config.force_ssl
    @middleware.use Middleware:ExceptionHandler

  -> load_routes
    route_file = "config/routes.w"
    if File.exists?(route_file)
      use route_file

  # Handle an incoming request through the middleware stack and router
  -> call(env)
    request  = Request.new(env)
    response = Response.new

    @middleware.call(request, response) ->
      @routes.dispatch(request, response)

    response

  # Configuration DSL — yields config for block-style setup
  -> configure
    yield @config

  # Check environment
  -> development? = @environment == "development"
  -> production?  = @environment == "production"
  -> test?        = @environment == "test"


# Nested config object with dot-access and defaults
+ Config
  rw :settings

  -> new(initial = {})
    @settings = initial

  -> set_defaults(defaults)
    defaults.each -> (key, value)
      @settings[key] = value unless @settings.has_key?(key)

  -> method_missing(name, *args)
    if name.ends_with?("=")
      @settings[name.chop.to_sym] = args.first
    else
      @settings[name.to_sym]


# Middleware stack — ordered list of middleware that wrap request handling
+ MiddlewareStack
  ro :layers

  -> new
    @layers = []

  -> use(middleware, **options)
    @layers.push({middleware: middleware, options: options})
    self

  -> call(request, response, &app)
    chain = @layers.reverse.reduce(app) -> (next_app, layer)
      -> (req, res)
        layer.middleware.new(layer.options).call(req, res, next_app)
    chain.call(request, response)
