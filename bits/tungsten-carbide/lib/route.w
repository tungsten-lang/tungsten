# Carbide::Route — HTTP routes mapped to controller actions.
#
# A Route pairs a URL pattern with a controller class and an action
# lambda. Route:Set holds the routes and resolves/dispatches requests;
# it duck-types the forge Router interface (#resolve(method, path) ->
# match with .params and .handler), so forge's HTTP/1.1 Server can use a
# Route:Set as its router directly.
#
# The action is a lambda taking the controller instance — the closest
# thing Tungsten has to a method reference (Object#send is bodyless in
# both engines):
#
#   set.get("/users/:id", UsersController, -> (c) c.show)
#
# Top-level (no `in` namespace): namespaced bit classes are unreachable
# from consumers and specs — same convention as forge and koala.

+ Route
  ro :method
  ro :path
  ro :controller
  ro :action
  ro :name
  ro :constraints
  ro :segments

  # options: {name:, constraints:} — explicit hash, not kwargs (kwargs
  # diverge between engines and break interp constructor dispatch).
  -> new(@method, @path, @controller, @action, options = {})
    @name = options[:name]
    @constraints = options[:constraints] || {}
    @segments = parse_segments(@path)

  # Check if this route matches a given request
  -> matches?(request)
    return false unless @method == request.method || @method == :ANY

    match_path?(request.path)

  # Extract named parameters from a matched path
  -> extract_params(request_path)
    params = {}
    request_parts = request_path.split("/").reject -> (s) s.empty?

    @segments.each_with_index -> (segment, i)
      if segment[:type] == :param || segment[:type] == :glob
        params[segment[:name]] = request_parts[i]

    params

  # No early returns: the self-hosted interpreter mis-executes an early
  # `return` from a method that also contains block closures
  # ("expected string or symbol" dispatch crash on a later call).
  -> match_path?(request_path)
    request_parts = request_path.split("/").reject -> (s) s.empty?
    matched = request_parts.size == @segments.size

    if matched
      @segments.each_with_index -> (segment, i)
        if segment[:type] == :literal && segment[:value] != request_parts[i]
          matched = false
    matched

  -> parse_segments(path)
    parts = path.split("/").reject -> (s) s.empty?
    parts.map -> (part)
      if part.starts_with?(":")
        {type: :param, name: part.slice(1, part.size - 1).to_sym}
      elsif part.starts_with?("*")
        {type: :glob, name: part.slice(1, part.size - 1).to_sym}
      else
        {type: :literal, value: part}


# Route::Set — holds all routes; resolves and dispatches requests.
+ Route:Set
  ro :routes

  -> new
    @routes = []
    @named  = {}

  -> add(method, path, controller, action, options = {})
    route = Route.new(method, path, controller, action, options)
    @routes.push(route)
    @named[options[:name]] = route if options[:name]
    route

  # Generate the URL for a named route, substituting :param segments
  # from the params hash. nil for unknown names or missing params.
  -> path_for(name, params = {})
    route = @named[name]
    result = nil
    if route != nil
      parts = []
      ok = true
      route.segments.each -> (segment)
        if segment[:type] == :literal
          parts.push(segment[:value])
        else
          value = params[segment[:name]]
          if value == nil
            ok = false
          else
            parts.push(value.to_s)
      if ok
        result = "/" + parts.join("/")
    result

  # --- HTTP verb sugar ---

  -> get(path, controller, action, options = {})
    self.add(:GET, path, controller, action, options)

  -> post(path, controller, action, options = {})
    self.add(:POST, path, controller, action, options)

  -> put(path, controller, action, options = {})
    self.add(:PUT, path, controller, action, options)

  -> patch(path, controller, action, options = {})
    self.add(:PATCH, path, controller, action, options)

  -> delete(path, controller, action, options = {})
    self.add(:DELETE, path, controller, action, options)

  # --- Resolution ---

  # forge Router duck-type: the forge Server calls
  # router.resolve(request.method, request.path) and expects nil or a
  # match exposing .params and .handler (handler.call(request) -> Response).
  -> resolve(method, path)
    found = nil
    @routes.each -> (route)
      if found == nil && (route.method == method || route.method == :ANY)
        if route.match_path?(path)
          found = route
    result = nil
    if found != nil
      result = Route:Match.new(found, found.extract_params(path))
    result

  # Pure request -> response dispatch (no sockets): mirrors what the
  # forge Server does with a resolved match. Used by specs and by
  # Carbide#dispatch.
  -> dispatch(request)
    match = self.resolve(request.method, request.path)
    result = nil
    if match == nil
      result = Response.not_found("Not Found: " + request.path)
    else
      request.params = match.params
      handler = match.handler
      result = handler.call(request)
    result


# Route::Match — a resolved route plus its extracted path params.
# The match is itself the request handler (Rack-style callable object):
# the forge Server invokes match.handler.call(request), and #handler
# returns self. A callable object rather than a closure on purpose —
# compiled closures capturing per-request state (class values
# especially) miscompile today (corrupted captures / segfaults on later
# calls), while plain method dispatch is solid in both engines.
+ Route:Match
  ro :route
  ro :params

  -> new(@route, @params)

  -> handler
    self

  # Instantiate the route's controller with the request and invoke the
  # route's action lambda on it.
  -> call(request)
    controller = @route.controller.new(request)
    controller.dispatch(@route.action)
