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
    req_segments = nil
    i = 0
    n = @routes.size
    while i < n
      route = @routes[i]
      if route.method == method || route.method == :ANY
        if route.static_only
          if route.path == normalized
            return RouteMatch.new(route, {})
        else
          if req_segments == nil
            req_segments = RoutePattern.split_segments(normalized)
          found = route.match_segments(req_segments)
          return found if found != nil
      i += 1
    nil

  -> add_route(method, path, handler)
    pattern = RoutePattern.new(method, self.normalize(path), handler)
    @routes.push(pattern)

  -> normalize(path)
    # Downcase and strip trailing slash
    result = path.downcase
    if result.size > 1 && result.byte_at(result.size - 1) == 47
      result = result.slice(0, result.size - 1)
    result

  # --- Mounting sub-routers ---

  -> mount(prefix, router)
    normalized_prefix = self.normalize(prefix)
    routes = router.routes
    i = 0
    n = routes.size
    while i < n
      route = routes[i]
      self.add_route(
        route.method,
        normalized_prefix + route.path,
        route.handler
      )
      i += 1

  # --- Route pattern matching ---

+ RoutePattern
  ro :method
  ro :path
  ro :handler
  ro :segments
  ro :wildcard
  ro :param_names
  ro :static_only

  -> .split_segments(path)
    parts = path.split("/")
    out = []
    i = 0
    n = parts.size
    while i < n
      s = parts[i]
      out.push(s) unless s.empty?
      i += 1
    out

  -> new(@method, @path, @handler)
    raw = RoutePattern.split_segments(@path)
    # A trailing "*name" (or bare "*") segment is a wildcard splat: it
    # matches one or more remaining path segments — captured, joined by
    # "/", under :name (or :splat for a bare "*"). Splats are how a
    # catch-all like "/assets/*path" or an SPA fallback "/*" is written.
    # Only the LAST segment is treated as a splat; a "*" earlier in the
    # pattern is matched literally.
    @wildcard = nil
    if raw.size > 0 && raw[raw.size - 1].byte_at(0) == 42
      star = raw[raw.size - 1]
      name = star.slice(1, star.size - 1)
      name = "splat" if name.empty?
      @wildcard = name.to_sym
      @segments = raw.slice(0, raw.size - 1)
    else
      @segments = raw

    @param_names = []
    has_dyn = @wildcard != nil
    i = 0
    n = @segments.size
    while i < n
      seg = @segments[i]
      if seg.size > 0 && seg.byte_at(0) == 58
        @param_names.push(seg.slice(1, seg.size - 1).to_sym)
        has_dyn = true
      else
        @param_names.push(nil)
      i += 1
    @static_only = !has_dyn

  -> match(request_path)
    if @static_only
      if request_path == @path
        return RouteMatch.new(self, {})
      return nil
    self.match_segments(RoutePattern.split_segments(request_path))

  -> match_segments(request_segments)
    fixed = @segments.size
    req_len = request_segments.size
    if @wildcard == nil
      return nil if req_len != fixed
    else
      return nil if req_len <= fixed

    params = {}
    i = 0
    while i < fixed
      pname = @param_names[i]
      req_segment = request_segments[i]
      if pname != nil
        params[pname] = req_segment
      elsif @segments[i] != req_segment
        return nil
      i += 1

    if @wildcard != nil
      rest = request_segments.slice(fixed, req_len - fixed)
      params[@wildcard] = rest.join("/")

    RouteMatch.new(self, params)

+ RouteMatch
  ro :route
  ro :params

  -> new(@route, @params)

  -> handler
    @route.handler
