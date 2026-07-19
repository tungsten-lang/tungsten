# Forge middleware — middleware chain
# Each middleware wraps the next handler: call(request, next) -> response

# Base middleware class — subclass and override `call`
+ Middleware
  ro :options

  -> new(options = {})
    @options = options

  -> call(request, next_handler)
    next_handler.call(request)

# --- Middleware chain ---

+ MiddlewareChain
  ro :stack

  -> new
    @stack = []

  -> add(middleware_class, options = {})
    @stack.push({class: middleware_class, options: options})

  -> build(app)
    # Wrap from inside out: last added middleware is outermost
    @stack.reverse.reduce(app) -> (handler, entry)
      middleware = entry[:class].new(entry[:options])
      -> (request) middleware.call(request, handler)

# --- Built-in middleware ---

+ LoggingMiddleware < Middleware
  -> call(request, next_handler)
    start = Time.monotonic
    response = next_handler.call(request)
    duration = Time.monotonic - start
    << "[request.method] [request.path] [response.status] [self.format_duration(duration)]"
    response

  -> format_duration(seconds)
    return "[(seconds * 1_000_000).round]µs" if seconds < 0.001
    return "[(seconds * 1000).round(1)]ms" if seconds < 1.0
    "[seconds.round(2)]s"

+ CompressionMiddleware < Middleware
  -> call(request, next_handler)
    response = next_handler.call(request)
    accept = request.headers.get("Accept-Encoding") || ""

    if accept.include?("br") && response.body.size > 1024
      response.body = Brotli.compress(response.body)
      response.header("Content-Encoding", "br")
    elsif accept.include?("gzip") && response.body.size > 1024
      response.body = Gzip.compress(response.body)
      response.header("Content-Encoding", "gzip")

    response

+ CorsMiddleware < Middleware
  -> call(request, next_handler)
    origin = request.headers.get("Origin")
    allowed = @options[:origins] || ["*"]

    if request.method == :OPTIONS
      response = Response.no_content
    else
      response = next_handler.call(request)

    if origin && (allowed.include?("*") || allowed.include?(origin))
      response.header("Access-Control-Allow-Origin", origin)
      response.header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
      response.header("Access-Control-Allow-Headers", "Content-Type, Authorization")
      response.header("Access-Control-Max-Age", "86400")

    response

+ RateLimitMiddleware < Middleware
  -> new(options = {})
    @options  = options
    @store    = {}
    @requests = @options[:requests] || 100
    @per      = @options[:per] || :minute
    @window   = 60
    @window   = 1 if @per == :second
    @window   = 3600 if @per == :hour

  # No early returns: the self-hosted interpreter mis-executes an early
  # `return` from a method that also contains block closures.
  -> call(request, next_handler)
    key = request.remote_addr
    now = Time.now.to_i
    window_start = now - @window

    @store[key] = @store[key] || []
    @store[key] = @store[key].select -> (t) t > window_start

    if @store[key].size >= @requests
      response = Response.new({status: 429, body: "Rate limit exceeded"})
      response.header("Retry-After", @window.to_s)
      response
    else
      @store[key].push(now)
      response = next_handler.call(request)
      response.header("X-RateLimit-Limit", @requests.to_s)
      response.header("X-RateLimit-Remaining", (@requests - @store[key].size).to_s)
      response

+ RequestIdMiddleware < Middleware
  -> call(request, next_handler)
    id = request.headers.get("X-Request-Id") || Random.uuid
    request.headers.set("X-Request-Id", id)
    response = next_handler.call(request)
    response.header("X-Request-Id", id)
    response
