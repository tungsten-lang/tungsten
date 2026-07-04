# Forge::Router specs

use spec
use forge

describe Forge:Router ->
  let :router -> Router.new

  describe "route matching" ->
    it "matches exact paths" ->
      router.get "/users" -> (req) Response.ok("users")
      match = router.resolve(:GET, "/users")
      expect(match).not_to be_nil

    it "matches dynamic segments" ->
      router.get "/users/:id" -> (req) Response.ok("user #{req.params[:id]}")
      match = router.resolve(:GET, "/users/42")
      expect(match).not_to be_nil
      expect(match.params[:id]).to eq("42")

    it "matches nested dynamic segments" ->
      router.get "/users/:user_id/bits/:id" -> (req)
        Response.ok("bit")
      match = router.resolve(:GET, "/users/1/bits/99")
      expect(match.params[:user_id]).to eq("1")
      expect(match.params[:id]).to eq("99")

    it "downcases paths before matching" ->
      router.get "/api/bits" -> (req) Response.json([])
      match = router.resolve(:GET, "/API/BITS")
      expect(match).not_to be_nil

    it "strips trailing slashes" ->
      router.get "/api" -> (req) Response.ok("api")
      match = router.resolve(:GET, "/api/")
      expect(match).not_to be_nil

    it "returns nil for non-matching methods" ->
      router.get "/users" -> (req) Response.ok("users")
      match = router.resolve(:POST, "/users")
      expect(match).to be_nil

  describe "HTTP methods" ->
    it "supports all standard methods" ->
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
      api = Router.new
      api.get "/bits" -> (req) Response.json([])

      router.mount "/api/v1", api
      match = router.resolve(:GET, "/api/v1/bits")
      expect(match).not_to be_nil
