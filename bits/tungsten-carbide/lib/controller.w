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

  -> redirect(location)
    Response.redirect(location)

  -> not_found(message = "Not Found")
    Response.not_found(message)
