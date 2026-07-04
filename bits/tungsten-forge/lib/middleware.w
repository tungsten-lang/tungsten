# Forge::Middleware — middleware chain
# Each middleware wraps the next handler: call(request, next) -> response

in Tungsten:Forge

+ Middleware

  # Base middleware class — subclass and override `call`
  + Base
    ro :options

    -> new(**options)
      @options = options

    -> call(request, next_handler)
      next_handler.call(request)

  # --- Middleware chain ---

  + Chain
    ro :stack

    -> new
      @stack = []

    -> add(middleware_class, **options)
      @stack.push({class: middleware_class, options: options})

    -> build(app)
      # Wrap from inside out: last added middleware is outermost
      @stack.reverse.reduce(app) -> (handler, entry)
        middleware = entry[:class].new(**entry[:options])
        -> (request) middleware.call(request, handler)


  # --- Built-in middleware ---

  + Logger < Base
    -> call(request, next_handler)
      start = Time.monotonic
      response = next_handler.call(request)
      duration = Time.monotonic - start

      Tungsten:Logger.info(
        "[request.method] [request.path] [response.status] [self.format_duration(duration)]"
      )
      response

    -> format_duration(seconds)
      case seconds
        s if s < 0.001 => "[(s * 1_000_000).round]µs"
        s if s < 1.0   => "[(s * 1000).round(1)]ms"
        => "[seconds.round(2)]s"

  + Compression < Base
    -> call(request, next_handler)
      response = next_handler.call(request)
      accept = request.headers.get("Accept-Encoding") || ""

      if accept.include?("br") && response.body.size() > 1024
        response.body = Brotli.compress(response.body)
        response.header("Content-Encoding", "br")
      elsif accept.include?("gzip") && response.body.size() > 1024
        response.body = Gzip.compress(response.body)
        response.header("Content-Encoding", "gzip")

      response

  + CORS < Base
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

  + RateLimit < Base
    -> new(**options)
      super(**options)
      @store    = {}
      @requests = @options[:requests] || 100
      @per      = @options[:per] || :minute
      @window   = case @per
        :second => 1
        :minute => 60
        :hour   => 3600

    -> call(request, next_handler)
      key = request.remote_addr
      now = Time.now.to_i
      window_start = now - @window

      @store[key] = @store[key] || []
      @store[key] = @store[key].select(-> (t) t > window_start)

      if @store[key].size >= @requests
        response = Response.new(status: 429, body: "Rate limit exceeded")
        response.header("Retry-After", @window.to_s)
        return response

      @store[key].push(now)
      response = next_handler.call(request)
      response.header("X-RateLimit-Limit", @requests.to_s)
      response.header("X-RateLimit-Remaining", (@requests - @store[key].size).to_s)
      response

  + RequestId < Base
    -> call(request, next_handler)
      id = request.headers.get("X-Request-Id") || Random.uuid
      request.headers.set("X-Request-Id", id)
      response = next_handler.call(request)
      response.header("X-Request-Id", id)
      response
