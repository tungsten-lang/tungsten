# Carbide::Middleware — first-class middleware primitive
# Each middleware receives a request and a `next` handler.
# Call `next.call(request)` to continue the chain, or return early.

in Tungsten:Carbide

+ Middleware
  ro :options

  -> new(**options)
    @options = options

  # Override in subclasses
  -> call(request, next_handler)
    next_handler.call(request)

  # --- Middleware stack ---

  + Stack
    ro :middleware

    -> new
      @middleware = []

    -> use(klass, **options)
      @middleware.push({class: klass, options: options})
      self

    -> build(app)
      @middleware.reverse.reduce(app) -> (handler, entry)
        instance = entry[:class].new(**entry[:options])
        -> (request) instance.call(request, handler)


  # --- Built-in middleware ---

  + Authentication < Middleware
    -> call(request, next_handler)
      token = request.headers.get("Authorization")&.sub("Bearer ", "")

      if token
        account = Account.find_by_token(token)
        request.params[:current_account] = account

      if self.requires_auth?(request) && !request.params[:current_account]
        << Response.new(status: 401, body: "Unauthorized")

      next_handler.call(request)

    -> requires_auth?(request)
      @options[:except]&.none?(-> (path) request.path.start_with?(path)) ?? true

  + CSRF < Middleware
    -> call(request, next_handler)
      if request.method != :GET && request.method != :HEAD
        token = request.headers.get("X-CSRF-Token") || request.params[:csrf_token]
        expected = request.session[:csrf_token]

        unless token && token == expected
          << Response.new(status: 422, body: "Invalid CSRF token")

      next_handler.call(request)

  + Timing < Middleware
    -> call(request, next_handler)
      start = Time.monotonic
      response = next_handler.call(request)
      duration = Time.monotonic - start
      response.header("X-Runtime", "#{(duration * 1000).round(2)}ms")
      response

  + ErrorHandler < Middleware
    -> call(request, next_handler)
      begin
        next_handler.call(request)
      rescue NotAuthorizedError => error
        Response.new(status: 403, body: "Forbidden")
      rescue RecordNotFound => error
        Response.new(status: 404, body: "Not Found")
      rescue error
        Logger.error("#{error.class}: #{error.message}")
        Response.error("Internal Server Error")
