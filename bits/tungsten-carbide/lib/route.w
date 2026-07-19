# Carbide::Route — DSL for defining HTTP routes
# Maps URL patterns to controller actions with support for
# RESTful resources, namespaces, scopes, and constraints.
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

  # options: {name:, constraints:} — explicit hash, not kwargs (kwargs
  # diverge between engines and break interp constructor dispatch).
  -> new(@method, @path, @controller, @action, options = {})
    @name = options[:name]
    @constraints = options[:constraints] || {}
    @segments = parse_segments(@path)

  # Check if this route matches a given request
  -> matches?(request)
    return false unless @method == request.method || @method == :any

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


# Route::Set — the router that holds all routes and dispatches requests
+ Route:Set
  ro :routes

  -> new
    @routes = []
    @named  = {}

  -> draw(&block)
    dsl = Route:DSL.new(self)
    dsl.instance_eval(&block)

  -> add(method, path, controller, action, options = {})
    route = Route.new(method, path, controller, action, options)
    @routes.push(route)
    @named[options[:name]] = route if options[:name]
    route

  -> dispatch(request, response)
    route = @routes.find(-> (r) r.matches?(request))

    unless route
      response.status = 404
      response.body = "Not Found"
      return response

    # Extract URL params and merge with request params
    url_params = route.extract_params(request.path)
    request.merge_params(url_params)

    # Instantiate controller and dispatch action
    controller = route.controller.new(request, response)
    controller.dispatch(route.action)
    response


# Route::DSL — the block DSL for config/routes.w
+ Route:DSL
  -> new(@set, prefix: "", namespace: nil)

  # HTTP verb methods
  -> get(path, to:, name: nil, **opts)
    full = "#{@prefix}#{path}"
    controller, action = parse_target(to)
    @set.add(:GET, full, controller, action, name: name, **opts)

  -> post(path, to:, name: nil, **opts)
    full = "#{@prefix}#{path}"
    controller, action = parse_target(to)
    @set.add(:POST, full, controller, action, name: name, **opts)

  -> put(path, to:, name: nil, **opts)
    full = "#{@prefix}#{path}"
    controller, action = parse_target(to)
    @set.add(:PUT, full, controller, action, name: name, **opts)

  -> patch(path, to:, name: nil, **opts)
    full = "#{@prefix}#{path}"
    controller, action = parse_target(to)
    @set.add(:PATCH, full, controller, action, name: name, **opts)

  -> delete(path, to:, name: nil, **opts)
    full = "#{@prefix}#{path}"
    controller, action = parse_target(to)
    @set.add(:DELETE, full, controller, action, name: name, **opts)

  # RESTful resource routing — generates all 7 standard routes
  -> resources(name, only: nil, except: nil, &block)
    controller = name.to_s.classify + "Controller"
    actions = [:index, :show, :new, :create, :edit, :update, :destroy]
    actions = actions.select(-> (a) only.include?(a)) if only
    actions = actions.reject(-> (a) except.include?(a)) if except

    prefix = "#{@prefix}/#{name}"

    actions.each -> (action)
      case action
        :index   => @set.add(:GET,    prefix,              controller, :index,   name: name)
        :show    => @set.add(:GET,    "#{prefix}/:id",     controller, :show,    name: "#{name}_show")
        :new     => @set.add(:GET,    "#{prefix}/new",     controller, :new,     name: "#{name}_new")
        :create  => @set.add(:POST,   prefix,              controller, :create,  name: "#{name}_create")
        :edit    => @set.add(:GET,    "#{prefix}/:id/edit", controller, :edit,   name: "#{name}_edit")
        :update  => @set.add(:PATCH,  "#{prefix}/:id",     controller, :update,  name: "#{name}_update")
        :destroy => @set.add(:DELETE, "#{prefix}/:id",     controller, :destroy, name: "#{name}_destroy")

    # Nested resources via block
    if block
      nested = Route:DSL.new(@set, prefix: "#{prefix}/:#{name.to_s.singularize}_id")
      nested.instance_eval(&block)

  # Namespace — adds a URL prefix and module namespace
  -> namespace(name, &block)
    nested = Route:DSL.new(@set, prefix: "#{@prefix}/#{name}", namespace: name)
    nested.instance_eval(&block)

  # Scope — adds a URL prefix without module namespace
  -> scope(path, &block)
    nested = Route:DSL.new(@set, prefix: "#{@prefix}#{path}")
    nested.instance_eval(&block)

  # Root route
  -> root(to:)
    controller, action = parse_target(to)
    @set.add(:GET, "/", controller, action, name: :root)

  -> parse_target(target)
    parts = target.split("#")
    controller = parts[0].classify + "Controller"
    action = parts[1].to_sym
    [controller, action]
