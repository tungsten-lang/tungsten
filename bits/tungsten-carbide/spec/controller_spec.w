# Carbide controller-filter specs — Rails-style before/after action
# callbacks around Controller#dispatch. A before filter may halt the
# request by returning a Response (action + after filters skipped); an
# after filter observes/rewrites the built Response. Pure dispatch, no
# sockets — identical on both engines.
# Run: bin/tungsten bits/tungsten-carbide/spec/controller_spec.w

use spec
use carbide

# before filter stamps a param the action reads back — proves the
# before filter runs, and runs before the action.
+ FilterStampController < Controller
  -> before_actions
    stamp = -> (c)
      c.params[:stamped] = "yes"
      nil
    out = []
    out.push(stamp)
    out

  -> show
    render_text("stamp=" + param(:stamped).to_s)

# before filter returns a Response — halts, action must not run.
+ FilterGuardController < Controller
  -> before_actions
    guard = -> (c)
      c.render_text("blocked")
    out = []
    out.push(guard)
    out

  -> show
    render_text("secret")

# three before filters; the middle one halts. first must run, third
# must NOT (log stays "1", never "13").
+ FilterOrderController < Controller
  -> before_actions
    first = -> (c)
      c.params[:log] = c.param(:log) + "1"
      nil
    second = -> (c)
      c.render_text("halt-at-2")
    third = -> (c)
      c.params[:log] = c.param(:log) + "3"
      nil
    out = []
    out.push(first)
    out.push(second)
    out.push(third)
    out

  -> show
    render_text("action")

# after filter replaces the response by returning a new Response.
+ FilterWrapController < Controller
  -> after_actions
    wrap = -> (c, resp)
      Response.text("(" + resp.body + ")")
    out = []
    out.push(wrap)
    out

  -> show
    render_text("body")

# after filter mutates the response in place and returns nil (keep it).
+ FilterHeaderController < Controller
  -> after_actions
    add = -> (c, resp)
      resp.header("X-Test", "on")
      nil
    out = []
    out.push(add)
    out

  -> show
    render_text("hi")

# two after filters — proves they run in order and chain.
+ FilterChainController < Controller
  -> after_actions
    a = -> (c, resp)
      Response.text(resp.body + "-a")
    b = -> (c, resp)
      Response.text(resp.body + "-b")
    out = []
    out.push(a)
    out.push(b)
    out

  -> show
    render_text("x")

# before filter halts AND an after filter is declared — the after filter
# must be skipped when a before filter halted.
+ FilterSkipAfterController < Controller
  -> before_actions
    block = -> (c)
      c.render_text("stop")
    out = []
    out.push(block)
    out

  -> after_actions
    boom = -> (c, resp)
      Response.text("SHOULD-NOT-APPEAR")
    out = []
    out.push(boom)
    out

  -> show
    render_text("action")

# no filters declared — base defaults ([]) leave dispatch unchanged.
+ FilterPlainController < Controller
  -> show
    render_text("plain")

-> ctl(klass)
  request = Request.new({method: "GET", path: "/x"})
  klass.new(request)

describe "Controller filters" ->
  describe "before filters" ->
    it "runs a before filter before the action" ->
      response = ctl(FilterStampController).dispatch(-> (c) c.show)
      expect(response.body).to eq("stamp=yes")

    it "halts dispatch when a before filter returns a Response" ->
      response = ctl(FilterGuardController).dispatch(-> (c) c.show)
      expect(response.body).to eq("blocked")

    it "runs before filters in order and stops the chain at the first halt" ->
      request = Request.new({method: "GET", path: "/x"})
      request.params = {log: ""}
      c = FilterOrderController.new(request)
      response = c.dispatch(-> (ctrl) ctrl.show)
      expect(response.body).to eq("halt-at-2")
      expect(c.param(:log)).to eq("1")

  describe "after filters" ->
    it "lets an after filter replace the response" ->
      response = ctl(FilterWrapController).dispatch(-> (c) c.show)
      expect(response.body).to eq("(body)")

    it "lets an after filter mutate the response in place and keep it" ->
      response = ctl(FilterHeaderController).dispatch(-> (c) c.show)
      expect(response.body).to eq("hi")
      expect(response.headers["X-Test"]).to eq("on")

    it "runs multiple after filters in order" ->
      response = ctl(FilterChainController).dispatch(-> (c) c.show)
      expect(response.body).to eq("x-a-b")

  describe "halt semantics" ->
    it "skips after filters when a before filter halts" ->
      response = ctl(FilterSkipAfterController).dispatch(-> (c) c.show)
      expect(response.body).to eq("stop")

  describe "no filters" ->
    it "dispatches the action directly when no filters are declared" ->
      response = ctl(FilterPlainController).dispatch(-> (c) c.show)
      expect(response.status).to eq(200)
      expect(response.body).to eq("plain")

spec_summary
