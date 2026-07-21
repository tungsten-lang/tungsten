# Carbide::Controller — request-facing action host.
#
# A controller wraps one forge Request; each action is a method that
# returns a forge Response (usually via the render_* helpers). Actions
# are invoked through Route:Set dispatch with an action lambda:
#
#   routes.get("/users/:id", UsersController, -> (c) c.show)
#
# The action lambda stands in for dynamic method dispatch — Object#send
# is bodyless in both engines, so a symbol cannot be turned into a call.
#
# Top-level (no `in` namespace): namespaced bit classes are unreachable
# from consumers and specs — same convention as route.w.

+ Controller
  ro :request
  ro :params

  -> new(@request)
    @params = @request.params

  # --- Action filters (Rails-style before/after callbacks) ---
  #
  # Override in a subclass to return an array of filter lambdas; both
  # default to empty, so a controller with no filters dispatches its
  # action directly (behavior unchanged).
  #
  #   before_actions -> [ -> (c) ... ]
  #     Runs before the action, in order. A filter returns nil to
  #     continue, or a Response to HALT: the action and every remaining
  #     before filter are skipped, the after filters do NOT run, and the
  #     returned Response becomes the dispatch result. (Mirrors Rails: a
  #     before_action that renders or redirects halts the request.)
  #
  #   after_actions -> [ -> (c, resp) ... ]
  #     Runs after the action (only when no before filter halted), in
  #     order. Each filter receives the controller and the current
  #     Response; it may mutate the Response in place (status/headers/body
  #     are rw) and return nil to keep it, or return a new Response to
  #     replace it for the remaining filters and the caller.
  #
  # Filters are instance methods returning lambda arrays — the same
  # override pattern as Model#validations — because a symbol cannot be
  # turned into a method call (Object#send is bodyless in both engines)
  # and inherited class methods are invisible to compiled binaries. A
  # filter lambda receives the controller, so `-> (c) c.require_login`
  # calls a controller method. Build the array with push (a bare `[a, b]`
  # array-literal statement of lambda vars does not parse). Keep filter
  # lambdas free of captured per-request state — compiled closures that
  # capture class/instance values miscompile (same caution as route.w).
  -> before_actions
    []

  -> after_actions
    []

  # Invoke an action lambda against this controller instance, running the
  # before/after filter chain around it (see Action filters above). No
  # early `return`: an early return from a closure-bearing method corrupts
  # the self-hosted interpreter (same flag-style flow as route.w/model.w).
  -> dispatch(action)
    me = self
    halted = nil
    before_actions.each -> (f)
      if halted == nil
        halted = f.call(me)
    response = nil
    if halted != nil
      response = halted
    else
      response = action.call(me)
      after_actions.each -> (g)
        replacement = g.call(me, response)
        if replacement != nil
          response = replacement
    response

  # --- Param access ---

  -> param(name)
    @params[name]

  # --- Response helpers (forge Response factories) ---

  -> render_text(body)
    Response.text(body)

  -> render_html(body)
    Response.html(body)

  # JSON body via carbide's Serializer (both engines; core JSON.encode
  # is compiled-only). options: {status:} — explicit hash, not kwargs.
  #
  #   render_json(task.to_h)
  #   render_json({errors: task.errors}, {status: 422})
  -> render_json(data, options = {})
    status = options[:status] || 200
    Response.new({status: status, headers: {"Content-Type" => "application/json"}, body: Serializer.encode(data)})

  # Validation-failure convenience: 422 with an {"errors": [...]} body.
  -> render_errors(errors, options = {})
    status = options[:status] || 422
    render_json({errors: errors}, {status: status})

  # HTML page via the Template engine (template.w). Accepts a compiled
  # Template (compile once, render per request) or a raw template
  # string (compiled on the spot). options: {status:} — explicit hash,
  # not kwargs. A malformed template renders a plain-text 500 —
  # Template.compile returns nil for bad sources, and a broken view
  # must not take the process down.
  #
  #   render_template(page_template, {title: "Tasks", tasks: rows})
  -> render_template(template, params = {}, options = {})
    t = template
    if type(template) == "String"
      t = Template.compile(template)
    if t == nil
      Response.new({status: 500, headers: {"Content-Type" => "text/plain"}, body: "template compile error"})
    else
      status = options[:status] || 200
      Response.html(t.render(params), {status: status})

  -> redirect(location)
    Response.redirect(location)

  -> not_found(message = "Not Found")
    Response.not_found(message)
