# Carbide::Route specs — pure routing logic.
# Run: bin/tungsten bits/tungsten-carbide/spec/route_spec.w
# (The same assertions also run via `carbide selftest`.)

use spec
use carbide

describe "Route" ->
  describe "path matching" ->
    it "matches a param segment" ->
      r = Route.new(:GET, "/users/:id", "UsersController", :show)
      expect(r.match_path?("/users/42")).to be_true

    it "requires the same number of segments" ->
      r = Route.new(:GET, "/users/:id", "UsersController", :show)
      expect(r.match_path?("/users")).to be_false

    it "rejects a literal mismatch" ->
      r = Route.new(:GET, "/users/:id", "UsersController", :show)
      expect(r.match_path?("/posts/42")).to be_false

    it "matches a glob segment" ->
      r = Route.new(:GET, "/files/*path", "FilesController", :show)
      expect(r.match_path?("/files/a")).to be_true

  describe "param extraction" ->
    it "captures named params" ->
      r = Route.new(:GET, "/users/:id", "UsersController", :show)
      expect(r.extract_params("/users/42")[:id]).to eq("42")

  describe "route sets" ->
    it "holds added routes" ->
      set = Route:Set.new
      set.add(:GET, "/health", "HealthController", :index)
      expect(set.routes.size).to eq(1)

  describe "named routes" ->
    it "generates a URL for a named route with params" ->
      set = Route:Set.new
      set.add(:GET, "/users/:id/posts/:post_id", "PostsController", :show, {name: :user_post})
      expect(set.path_for(:user_post, {id: 7, post_id: 42})).to eq("/users/7/posts/42")

    it "generates a literal-only URL" ->
      set = Route:Set.new
      set.add(:GET, "/health", "HealthController", :index, {name: :health})
      expect(set.path_for(:health)).to eq("/health")

    it "returns nil for unknown names and missing params" ->
      set = Route:Set.new
      set.add(:GET, "/users/:id", "UsersController", :show, {name: :user})
      expect(set.path_for(:nope)).to be_nil
      expect(set.path_for(:user)).to be_nil

  describe "param constraints" ->
    it "matches a param that satisfies an :int constraint" ->
      r = Route.new(:GET, "/users/:id", "UsersController", :show, {constraints: {id: :int}})
      expect(r.match_path?("/users/42")).to be_true

    it "rejects a param that violates an :int constraint" ->
      r = Route.new(:GET, "/users/:id", "UsersController", :show, {constraints: {id: :int}})
      expect(r.match_path?("/users/abc")).to be_false

    it "enforces an :alpha constraint" ->
      r = Route.new(:GET, "/u/:name", "UsersController", :show, {constraints: {name: :alpha}})
      expect(r.match_path?("/u/bob")).to be_true
      expect(r.match_path?("/u/b0b")).to be_false

    it "enforces a :slug constraint" ->
      r = Route.new(:GET, "/posts/:slug", "PostsController", :show, {constraints: {slug: :slug}})
      expect(r.match_path?("/posts/hello-world")).to be_true
      expect(r.match_path?("/posts/Hello")).to be_false

    it "enforces an allow-list (enum) constraint" ->
      r = Route.new(:GET, "/p/:fmt", "PostsController", :show, {constraints: {fmt: ["json", "xml"]}})
      expect(r.match_path?("/p/json")).to be_true
      expect(r.match_path?("/p/yaml")).to be_false

    it "treats an unknown constraint as permissive" ->
      r = Route.new(:GET, "/x/:id", "XController", :show, {constraints: {id: :bogus}})
      expect(r.match_path?("/x/anything")).to be_true

    it "disambiguates prefix-sharing routes by constraint at resolve time" ->
      set = Route:Set.new
      set.add(:GET, "/users/:id", "IntController", :show, {constraints: {id: :int}})
      set.add(:GET, "/users/:name", "AlphaController", :show, {constraints: {name: :alpha}})
      expect(set.resolve(:GET, "/users/42").route.controller).to eq("IntController")
      expect(set.resolve(:GET, "/users/bob").route.controller).to eq("AlphaController")
      expect(set.resolve(:GET, "/users/!!")).to be_nil

spec_summary
