# Forge::Server specs

use spec
use forge

describe Forge:Server ->
  describe "configuration" ->
    it "has sensible defaults" ->
      config = Forge:Config.new
      expect(config.host).to eq("0.0.0.0")
      expect(config.port).to eq(443)
      expect(config.workers).to eq(System.cpu_count)
      expect(config.max_connections).to eq(10_000)
      expect(config.protocols).to eq([:h3, :h2, :http11])
      expect(config.normalize_paths).to eq(true)

    it "validates configuration" ->
      config = Forge:Config.new
      config.port = -1
      expect(-> config.validate!).to raise_error(Forge:ConfigError)

    it "configures TLS" ->
      Forge.configure ->
        tls auto: true
        port 443
      expect(Forge.instance.config.tls_config[:auto]).to eq(true)

  describe "request handling" ->
    it "routes GET requests" ->
      Forge.routes ->
        get "/hello" -> (request)
          Response.ok("world")

      router = Forge.instance.router
      match = router.resolve(:GET, "/hello")
      expect(match).not_to be_nil

    it "normalizes paths to lowercase" ->
      Forge.routes ->
        get "/hello" -> (request)
          Response.ok("world")

      router = Forge.instance.router
      match = router.resolve(:GET, "/HELLO")
      expect(match).not_to be_nil

    it "strips trailing slashes" ->
      Forge.routes ->
        get "/api/bits" -> (request)
          Response.json([])

      router = Forge.instance.router
      match = router.resolve(:GET, "/api/bits/")
      expect(match).not_to be_nil

    it "returns nil for unmatched routes" ->
      Forge.routes ->
        get "/" -> (request)
          Response.ok("home")

      router = Forge.instance.router
      match = router.resolve(:GET, "/nonexistent")
      expect(match).to be_nil
