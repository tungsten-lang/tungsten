# Carbide dispatch specs — the pure request -> controller -> response
# path, no sockets. Controller resolution and response building are
# exactly what the forge Server invokes when serving live.
# Run: bin/tungsten bits/tungsten-carbide/spec/dispatch_spec.w

use spec
use carbide

+ DispatchUsersController < Controller
  -> show
    render_text("user " + param(:id).to_s)

+ DispatchEchoController < Controller
  -> create
    render_text("echo:" + @request.body.to_s)

+ DispatchHomeController < Controller
  -> index
    render_html("<h1>home</h1>")

describe "dispatch" ->
  describe "controller resolution" ->
    it "resolves a match with extracted params" ->
      set = Route:Set.new
      set.get("/users/:id", DispatchUsersController, -> (c) c.show)
      match = set.resolve(:GET, "/users/7")
      expect(match.params[:id]).to eq("7")

    it "returns nil when nothing matches" ->
      set = Route:Set.new
      set.get("/users/:id", DispatchUsersController, -> (c) c.show)
      expect(set.resolve(:GET, "/nope")).to be_nil

    it "does not match across methods" ->
      set = Route:Set.new
      set.get("/users/:id", DispatchUsersController, -> (c) c.show)
      expect(set.resolve(:POST, "/users/7")).to be_nil

    it "exposes a callable handler that runs the controller action" ->
      set = Route:Set.new
      set.get("/users/:id", DispatchUsersController, -> (c) c.show)
      match = set.resolve(:GET, "/users/9")
      request = Request.new({method: "GET", path: "/users/9"})
      request.params = match.params
      handler = match.handler
      response = handler.call(request)
      expect(response.body).to eq("user 9")

  describe "response building" ->
    it "routes a dynamic segment to the controller action" ->
      set = Route:Set.new
      set.get("/users/:id", DispatchUsersController, -> (c) c.show)
      request = Request.new({method: "GET", path: "/users/42"})
      response = set.dispatch(request)
      expect(response.status).to eq(200)
      expect(response.body).to eq("user 42")

    it "returns 404 for an unknown path" ->
      set = Route:Set.new
      request = Request.new({method: "GET", path: "/missing"})
      response = set.dispatch(request)
      expect(response.status).to eq(404)

    it "hands the request body to the controller" ->
      set = Route:Set.new
      set.post("/echo", DispatchEchoController, -> (c) c.create)
      request = Request.new({method: "POST", path: "/echo", body: "ping"})
      response = set.dispatch(request)
      expect(response.status).to eq(200)
      expect(response.body).to eq("echo:ping")

  describe "application" ->
    it "dispatches through the Carbide singleton" ->
      Carbide.reset
      routes = Carbide.instance.routes
      routes.get("/", DispatchHomeController, -> (c) c.index)
      request = Request.new({method: "GET", path: "/"})
      response = Carbide.instance.dispatch(request)
      expect(response.status).to eq(200)
      expect(response.body).to eq("<h1>home</h1>")

spec_summary
