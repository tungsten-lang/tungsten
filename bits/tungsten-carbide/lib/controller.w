# Carbide::Controller — action dispatch, params, rendering, and filters
# Controllers are the C in MVC. Each public method is an action.

in Tungsten:Carbide

+ Controller
  ro :request
  ro :response
  ro :params
  ro :action_name

  # Class-level filter registrations
  @@before_filters = []
  @@after_filters  = []
  @@rescue_handlers = {}

  # --- Filter DSL (class-level) ---

  -> .before_action(method_name, only: nil, except: nil)
    @@before_filters.push({method: method_name, only: only, except: except})

  -> .after_action(method_name, only: nil, except: nil)
    @@after_filters.push({method: method_name, only: only, except: except})

  -> .rescue_from(error_class, with:)
    @@rescue_handlers[error_class] = with

  # --- Instance lifecycle ---

  -> new(@request, @response)
    @params      = @request.params
    @action_name = nil
    @rendered    = false
    @locals      = {}

  # Dispatch an action by name — runs filters, executes, handles errors
  -> dispatch(action)
    @action_name = action

    begin
      run_before_filters
      self.send(action)
      run_after_filters
      render(action) unless @rendered
    rescue error
      handle_error(error)

  # --- Rendering ---

  -> render(template = nil, status: 200, json: nil, text: nil, layout: "application")
    @rendered = true

    case
      json =>
        @response.status = status
        @response.content_type = "application/json"
        @response.body = json |> JSON.encode
      text =>
        @response.status = status
        @response.content_type = "text/plain"
        @response.body = text
      =>
        template_name = template || @action_name
        view = View.new(template_name, layout: layout, locals: @locals)
        @response.status = status
        @response.content_type = "text/html"
        @response.body = view.render

  -> render_json(data, status: 200)
    render(json: data, status: status)

  # --- Response helpers ---

  -> redirect_to(url, status: 302)
    @rendered = true
    @response.status = status
    @response.headers["Location"] = url

  -> head(status)
    @rendered = true
    @response.status = status
    @response.body = ""

  # --- Local variable assignment for views ---

  -> assign(key, value)
    @locals[key] = value

  # --- Session and cookies ---

  -> session
    @request.session

  -> cookies
    @request.cookies

  -> flash
    @request.flash

  # --- Strong parameters ---

  -> permit(*keys)
    @params.slice(*keys)

  -> require_param(key)
    @params[key] || <! ParamMissing.new("Missing required parameter: #{key}")

  # --- Private helpers ---

  -> run_before_filters
    @@before_filters.each -> (filter)
      if should_run_filter?(filter)
        self.send(filter.method)

  -> run_after_filters
    @@after_filters.each -> (filter)
      if should_run_filter?(filter)
        self.send(filter.method)

  -> should_run_filter?(filter)
    case
      filter.only   => filter.only.include?(@action_name)
      filter.except => !filter.except.include?(@action_name)
      =>              true

  -> handle_error(error)
    handler = @@rescue_handlers[error.class]
    if handler
      self.send(handler, error)
    else
      <! error


# Parameter missing error
+ ParamMissing < StandardError
