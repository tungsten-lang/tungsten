# Forge::Router — request routing with path normalization
# All paths are downcased and trailing slashes stripped before matching

in Tungsten:Forge

+ Router
  ro :routes

  -> new
    @routes = []

  -> draw(&block)
    self.instance_eval(&block)

  # --- HTTP method DSL ---

  -> get(path, &handler)
    self.add_route(:GET, path, handler)

  -> post(path, &handler)
    self.add_route(:POST, path, handler)

  -> put(path, &handler)
    self.add_route(:PUT, path, handler)

  -> patch(path, &handler)
    self.add_route(:PATCH, path, handler)

  -> delete(path, &handler)
    self.add_route(:DELETE, path, handler)

  -> head(path, &handler)
    self.add_route(:HEAD, path, handler)

  -> options(path, &handler)
    self.add_route(:OPTIONS, path, handler)

  -> websocket(path, &handler)
    self.add_route(:WEBSOCKET, path, handler)

  # --- Route resolution ---

  -> resolve(method, path)
    normalized = self.normalize(path)

    @routes.each -> (route)
      next unless route.method == method || route.method == :ANY
      match = route.match(normalized)
      return match if match

    nil

  -> add_route(method, path, handler)
    pattern = RoutePattern.new(method, self.normalize(path), handler)
    @routes.push(pattern)

  -> normalize(path)
    # Downcase and strip trailing slash
    result = path.downcase
    result = result.chomp("/") if result.size > 1
    result

  # --- Mounting sub-routers ---

  -> mount(prefix, router)
    normalized_prefix = self.normalize(prefix)
    router.routes.each -> (route)
      self.add_route(
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

    -> new(@method, @path, @handler)
      @segments = @path.split("/").reject(-> (s) s.empty?)

    -> match(request_path)
      request_segments = request_path.split("/").reject(-> (s) s.empty?)
      return nil unless request_segments.size == @segments.size

      params = {}

      @segments.each_with_index -> (segment, i)
        req_segment = request_segments[i]
        case segment
          # Dynamic segment :name
          s if s.start_with?(":") =>
            params[s[1..].to_sym] = req_segment
          # Exact match
          s if s == req_segment =>
            nil
          =>
            return nil

      RouteMatch.new(self, params)

  + RouteMatch
    ro :route
    ro :params

    -> new(@route, @params)

    -> handler
      @route.handler
