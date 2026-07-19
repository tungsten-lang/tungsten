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

spec_summary
