# Carbide::Route — DSL for defining HTTP routes
# Maps URL patterns to controller actions with support for
# RESTful resources, namespaces, scopes, and constraints.

in Tungsten:Carbide

+ Route
  ro :method
  ro :path
  ro :controller
  ro :action
  ro :name
  ro :constraints

  -> new(@method, @path, @controller, @action, name: nil, constraints: {})
    @name = name
    @constraints = constraints
    @segments = parse_segments(@path)

  # Check if this route matches a given request
  -> matches?(request)
    return false unless @method == request.method || @method == :any

    match_path?(request.path)

  # Extract named parameters from a matched path
  -> extract_params(request_path)
    params = {}
    request_parts = request_path.split("/").reject(s -> s.empty?)

    @segments.zip(request_parts).each -> (segment, part)
      case segment
        {type: :param, name: name} => params[name] = part
        {type: :glob, name: name}  => params[name] = part  # simplified

    params

  -> match_path?(request_path)
    request_parts = request_path.split("/").reject(s -> s.empty?)
    return false unless request_parts.size == @segments.size

    @segments.zip(request_parts).all? -> (segment, part)
      case segment
        {type: :literal, value: v} => v == part
        {type: :param}             => true
        {type: :glob}              => true

  -> parse_segments(path)
    path.split("/").reject(s -> s.empty?).map -> (part)
      case part
        /^:(.+)$/  => {type: :param, name: $1.to_sym}
        /^\*(.+)$/ => {type: :glob, name: $1.to_sym}
        =>           {type: :literal, value: part}


# Route::Set — the router that holds all routes and dispatches requests
+ Route:Set
  ro :routes

  -> new
    @routes = []
    @named  = {}

  -> draw(&block)
    dsl = Route:DSL.new(self)
    dsl.instance_eval(&block)

  -> add(method, path, controller, action, **options)
    route = Route.new(method, path, controller, action, **options)
    @routes.push(route)
    @named[options[:name]] = route if options[:name]
    route

  -> dispatch(request, response)
    route = @routes.find(r -> r.matches?(request))

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
    actions = actions.select(a -> only.include?(a)) if only
    actions = actions.reject(a -> except.include?(a)) if except

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
