# Forge server / configuration specs

use spec_helper

describe "Forge configuration" ->
  it "has sensible defaults" ->
    config = Config.new
    expect(config.host).to eq("0.0.0.0")
    expect(config.port).to eq(443)
    expect(config.workers > 0).to eq(true)
    expect(config.max_connections).to eq(10_000)
    # Array == is identity in both engines — compare a stringified form.
    expect(config.protocols.join(",")).to eq("h3,h2,http11")
    expect(config.normalize_paths).to eq(true)

  it "validates configuration" ->
    config = Config.new
    config.port = -1
    expect(-> () config.validate!).to raise_error(ConfigError)

  it "configures TLS" ->
    Forge.reset
    Forge.configure -> (config)
      config.tls auto: true
      config.port = 8443
    expect(Forge.instance.config.tls_config[:auto]).to eq(true)

describe "Forge request handling" ->
  it "routes GET requests" ->
    Forge.reset
    Forge.routes -> (r)
      r.get "/hello" -> (request)
        Response.ok("world")

    router = Forge.instance.router
    match = router.resolve(:GET, "/hello")
    expect(match).not_to be_nil

  it "normalizes paths to lowercase" ->
    Forge.reset
    Forge.routes -> (r)
      r.get "/hello" -> (request)
        Response.ok("world")

    router = Forge.instance.router
    match = router.resolve(:GET, "/HELLO")
    expect(match).not_to be_nil

  it "strips trailing slashes" ->
    Forge.reset
    Forge.routes -> (r)
      r.get "/api/bits" -> (request)
        Response.json([])

    router = Forge.instance.router
    match = router.resolve(:GET, "/api/bits/")
    expect(match).not_to be_nil

  it "returns nil for unmatched routes" ->
    Forge.reset
    Forge.routes -> (r)
      r.get "/" -> (request)
        Response.ok("home")

    router = Forge.instance.router
    match = router.resolve(:GET, "/nonexistent")
    expect(match).to be_nil

spec_summary
