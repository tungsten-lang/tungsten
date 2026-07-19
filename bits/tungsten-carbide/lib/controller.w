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

  # Invoke an action lambda against this controller instance.
  -> dispatch(action)
    action.call(self)

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
