# Forge Router — request routing with path normalization
# All paths are downcased and trailing slashes stripped before matching.
#
# Handlers may be given either as a trailing block:
#   router.get "/users" -> (req) Response.ok("users")
# or as a positional lambda:
#   router.get("/users", -> (req) Response.ok("users"))

+ Router
  ro :routes

  -> new
    @routes = []

  # Yields self so callers can register routes:
  #   router.draw -> (r) r.get(...)
  -> draw(registrar)
    registrar.call(self)
    self

  # --- HTTP method DSL ---

  -> get(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:GET, path, handler)

  -> post(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:POST, path, handler)

  -> put(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:PUT, path, handler)

  -> patch(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:PATCH, path, handler)

  -> delete(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:DELETE, path, handler)

  -> head(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:HEAD, path, handler)

  -> options(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:OPTIONS, path, handler)

  -> websocket(path, handler = nil, &)
    if handler == nil
      handler = -> (req) &(req)
    self.add_route(:WEBSOCKET, path, handler)

  # --- Route resolution ---

  -> resolve(method, path)
    normalized = self.normalize(path)
    found = nil
    @routes.each -> (route)
      if found == nil && (route.method == method || route.method == :ANY)
        found = route.match(normalized)
    found

  -> add_route(method, path, handler)
    pattern = RoutePattern.new(method, self.normalize(path), handler)
    @routes.push(pattern)

  -> normalize(path)
    # Downcase and strip trailing slash
    result = path.downcase
    if result.size > 1 && result.ends_with?("/")
      result = result.slice(0, result.size - 1)
    result

  # --- Mounting sub-routers ---

  -> mount(prefix, router)
    normalized_prefix = self.normalize(prefix)
    # Capture self: inside an Enumerable block the interpreter binds
    # `self` to the current element, not the enclosing receiver.
    target = self
    router.routes.each -> (route)
      target.add_route(
        route.method,
        normalized_prefix + route.path,
        route.handler
      )

  # --- Route pattern matching ---

+ RoutePattern
  ro :method
  ro :path
  ro :handler
  ro :segments
  ro :wildcard

  -> new(@method, @path, @handler)
    raw = @path.split("/").reject -> (s) s.empty?
    # A trailing "*name" (or bare "*") segment is a wildcard splat: it
    # matches one or more remaining path segments — captured, joined by
    # "/", under :name (or :splat for a bare "*"). Splats are how a
    # catch-all like "/assets/*path" or an SPA fallback "/*" is written.
    # Only the LAST segment is treated as a splat; a "*" earlier in the
    # pattern is matched literally.
    @wildcard = nil
    if raw.size > 0 && raw[raw.size - 1].starts_with?("*")
      star = raw[raw.size - 1]
      name = star.slice(1, star.size - 1)
      name = "splat" if name.empty?
      @wildcard = name.to_sym
      @segments = raw.slice(0, raw.size - 1)
    else
      @segments = raw

  # No early returns here: the self-hosted interpreter mis-executes an
  # early `return` from a method that also contains block closures
  # ("expected string or symbol" dispatch crash on a later call).
  -> match(request_path)
    request_segments = request_path.split("/").reject -> (s) s.empty?
    result = nil
    fixed = @segments.size

    # A plain route needs an exact segment count; a splat route needs the
    # fixed prefix plus at least one segment for the splat to capture.
    size_ok = false
    if @wildcard == nil
      size_ok = request_segments.size == fixed
    else
      size_ok = request_segments.size > fixed

    if size_ok
      params = {}
      matched = true

      @segments.each_with_index -> (segment, i)
        if matched
          req_segment = request_segments[i]
          if segment.starts_with?(":")
            # Dynamic segment :name
            params[segment.slice(1, segment.size - 1).to_sym] = req_segment
          elsif segment != req_segment
            matched = false

      if matched && @wildcard != nil
        rest = request_segments.slice(fixed, request_segments.size - fixed)
        params[@wildcard] = rest.join("/")

      if matched
        result = RouteMatch.new(self, params)

    result

+ RouteMatch
  ro :route
  ro :params

  -> new(@route, @params)

  -> handler
    @route.handler
