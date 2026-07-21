# Forge Router specs

use spec_helper

describe "Router" ->
  describe "route matching" ->
    it "matches exact paths" ->
      router = Router.new
      router.get "/users" -> (req) Response.ok("users")
      match = router.resolve(:GET, "/users")
      expect(match).not_to be_nil

    it "matches dynamic segments" ->
      router = Router.new
      router.get "/users/:id" -> (req) Response.ok("user")
      match = router.resolve(:GET, "/users/42")
      expect(match).not_to be_nil
      expect(match.params[:id]).to eq("42")

    it "matches nested dynamic segments" ->
      router = Router.new
      router.get "/users/:user_id/bits/:id" -> (req)
        Response.ok("bit")
      match = router.resolve(:GET, "/users/1/bits/99")
      expect(match.params[:user_id]).to eq("1")
      expect(match.params[:id]).to eq("99")

    it "downcases paths before matching" ->
      router = Router.new
      router.get "/api/bits" -> (req) Response.json([])
      match = router.resolve(:GET, "/API/BITS")
      expect(match).not_to be_nil

    it "strips trailing slashes" ->
      router = Router.new
      router.get "/api" -> (req) Response.ok("api")
      match = router.resolve(:GET, "/api/")
      expect(match).not_to be_nil

    it "returns nil for non-matching methods" ->
      router = Router.new
      router.get "/users" -> (req) Response.ok("users")
      match = router.resolve(:POST, "/users")
      expect(match).to be_nil

  describe "HTTP methods" ->
    it "supports all standard methods" ->
      router = Router.new
      router.get    "/r" -> (req) Response.ok("get")
      router.post   "/r" -> (req) Response.ok("post")
      router.put    "/r" -> (req) Response.ok("put")
      router.patch  "/r" -> (req) Response.ok("patch")
      router.delete "/r" -> (req) Response.ok("delete")

      expect(router.resolve(:GET, "/r")).not_to be_nil
      expect(router.resolve(:POST, "/r")).not_to be_nil
      expect(router.resolve(:PUT, "/r")).not_to be_nil
      expect(router.resolve(:PATCH, "/r")).not_to be_nil
      expect(router.resolve(:DELETE, "/r")).not_to be_nil

  describe "mounting" ->
    it "mounts sub-routers with prefix" ->
      router = Router.new
      api = Router.new
      api.get "/bits" -> (req) Response.json([])

      router.mount "/api/v1", api
      match = router.resolve(:GET, "/api/v1/bits")
      expect(match).not_to be_nil

  describe "wildcard splat routes" ->
    it "captures the remaining path under the splat name" ->
      router = Router.new
      router.get "/assets/*path" -> (req) Response.ok("asset")
      match = router.resolve(:GET, "/assets/css/app.css")
      expect(match).not_to be_nil
      expect(match.params[:path]).to eq("css/app.css")

    it "captures a single trailing segment" ->
      router = Router.new
      router.get "/files/*path" -> (req) Response.ok("file")
      match = router.resolve(:GET, "/files/readme")
      expect(match.params[:path]).to eq("readme")

    it "captures a bare wildcard under :splat" ->
      router = Router.new
      router.get "/*" -> (req) Response.ok("catch-all")
      match = router.resolve(:GET, "/a/b/c")
      expect(match.params[:splat]).to eq("a/b/c")

    it "requires at least one segment for the splat" ->
      router = Router.new
      router.get "/assets/*path" -> (req) Response.ok("asset")
      match = router.resolve(:GET, "/assets")
      expect(match).to be_nil

    it "combines dynamic segments with a trailing splat" ->
      router = Router.new
      router.get "/users/:id/files/*path" -> (req) Response.ok("user file")
      match = router.resolve(:GET, "/users/42/files/docs/report.pdf")
      expect(match.params[:id]).to eq("42")
      expect(match.params[:path]).to eq("docs/report.pdf")

    it "lets an earlier static route win over a splat" ->
      router = Router.new
      router.get "/assets/logo.png" -> (req) Response.ok("logo")
      router.get "/assets/*path" -> (req) Response.ok("asset")
      match = router.resolve(:GET, "/assets/logo.png")
      expect(match.params[:path]).to be_nil

spec_summary
