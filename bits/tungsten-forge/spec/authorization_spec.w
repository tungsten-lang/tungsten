# Forge authentication specs — Credentials (RFC 7235 credential parsing,
# RFC 6750 Bearer, RFC 7617 Basic), the pure Base64Codec decoder, and the
# Request methods that delegate to them (#authorization, #bearer_token,
# #basic_auth, #proxy_authorization).
#
# No sockets: requests are built with Request.parse, so everything here
# runs under both engines. Never chain a call off a `?` method (it lexes as
# safe navigation, which the interpreter does not implement).

use spec_helper

describe "Credentials.parse (RFC 7235)" ->
  it "parses a Bearer scheme and token" ->
    c = Credentials.parse("Bearer abc123")
    expect(c.scheme).to eq("bearer")
    expect(c.credentials).to eq("abc123")

  it "parses a Basic scheme and base64 credentials" ->
    c = Credentials.parse("Basic dXNlcjpwYXNz")
    expect(c.scheme).to eq("basic")
    expect(c.credentials).to eq("dXNlcjpwYXNz")

  it "downcases the scheme but preserves credential case" ->
    c = Credentials.parse("BEARER AbC.DeF")
    expect(c.scheme).to eq("bearer")
    expect(c.credentials).to eq("AbC.DeF")

  it "treats a bare scheme (no space) as empty credentials" ->
    c = Credentials.parse("Negotiate")
    expect(c.scheme).to eq("negotiate")
    expect(c.credentials).to eq("")

  it "trims optional whitespace around the credentials" ->
    c = Credentials.parse("Bearer    token   ")
    expect(c.scheme).to eq("bearer")
    expect(c.credentials).to eq("token")

  it "returns nil for a nil header" ->
    expect(Credentials.parse(nil)).to be_nil

  it "returns nil for an empty or whitespace-only header" ->
    expect(Credentials.parse("")).to be_nil
    expect(Credentials.parse("   ")).to be_nil

describe "Credentials scheme predicates" ->
  it "matches a scheme case-insensitively" ->
    c = Credentials.parse("Bearer x")
    expect(c.scheme?("BEARER")).to eq(true)
    expect(c.scheme?("Basic")).to eq(false)

  it "identifies bearer? and basic?" ->
    b = Credentials.parse("Bearer x")
    expect(b.bearer?).to eq(true)
    expect(b.basic?).to eq(false)
    a = Credentials.parse("Basic dXNlcjpwYXNz")
    expect(a.bearer?).to eq(false)
    expect(a.basic?).to eq(true)

describe "Credentials#token (RFC 6750 Bearer)" ->
  it "returns the token for a Bearer credential" ->
    expect(Credentials.parse("Bearer t0k3n").token).to eq("t0k3n")

  it "is nil for a non-Bearer scheme" ->
    expect(Credentials.parse("Basic dXNlcjpwYXNz").token).to be_nil

  it "is nil for an empty Bearer token" ->
    expect(Credentials.parse("Bearer").token).to be_nil

describe "Base64Codec.decode (RFC 4648)" ->
  it "decodes the classic vectors" ->
    expect(Base64Codec.decode("TWFu")).to eq("Man")
    expect(Base64Codec.decode("TWE=")).to eq("Ma")
    expect(Base64Codec.decode("TQ==")).to eq("M")

  it "decodes userid:password credentials" ->
    expect(Base64Codec.decode("dXNlcjpwYXNz")).to eq("user:pass")
    expect(Base64Codec.decode("QWxhZGRpbjpvcGVuIHNlc2FtZQ==")).to eq("Aladdin:open sesame")

  it "decodes an empty string to an empty string" ->
    expect(Base64Codec.decode("")).to eq("")

  it "returns nil for a nil input" ->
    expect(Base64Codec.decode(nil)).to be_nil

  it "tolerates embedded whitespace" ->
    expect(Base64Codec.decode("TW Fu")).to eq("Man")
    expect(Base64Codec.decode("dXNl\r\ncjpw\r\nYXNz")).to eq("user:pass")

  it "returns nil for an out-of-alphabet byte" ->
    expect(Base64Codec.decode("!!!!")).to be_nil

  it "returns nil for a trailing lone sextet" ->
    expect(Base64Codec.decode("TWFuX")).to be_nil

describe "Credentials Basic decode (RFC 7617)" ->
  it "splits username and password on the first colon" ->
    c = Credentials.parse("Basic dXNlcjpwYXNz")
    expect(c.username).to eq("user")
    expect(c.password).to eq("pass")

  it "keeps later colons in the password" ->
    c = Credentials.parse("Basic dXNlcjpwYTpzcw==")
    expect(c.username).to eq("user")
    expect(c.password).to eq("pa:ss")

  it "treats a colon-less credential as a userid with no password" ->
    c = Credentials.parse("Basic YWxhZGRpbg==")
    expect(c.username).to eq("aladdin")
    expect(c.password).to be_nil

  it "yields an empty password for a trailing colon" ->
    c = Credentials.parse("Basic cm9vdDo=")
    expect(c.username).to eq("root")
    expect(c.password).to eq("")

  it "exposes basic_credentials as a hash" ->
    bc = Credentials.parse("Basic dXNlcjpwYXNz").basic_credentials
    expect(bc[:username]).to eq("user")
    expect(bc[:password]).to eq("pass")

  it "is nil for a non-Basic scheme" ->
    c = Credentials.parse("Bearer dXNlcjpwYXNz")
    expect(c.username).to be_nil
    expect(c.password).to be_nil
    expect(c.basic_credentials).to be_nil

  it "is nil when the base64 is malformed" ->
    c = Credentials.parse("Basic !!!not-base64!!!")
    expect(c.username).to be_nil
    expect(c.basic_credentials).to be_nil

describe "Request#authorization surface" ->
  it "parses a Bearer Authorization header" ->
    req = Request.parse("GET / HTTP/1.1\r\nAuthorization: Bearer abc.def\r\n\r\n")
    creds = req.authorization
    expect(creds.scheme).to eq("bearer")
    expect(req.bearer_token).to eq("abc.def")

  it "parses a Basic Authorization header into basic_auth" ->
    req = Request.parse("GET / HTTP/1.1\r\nAuthorization: Basic dXNlcjpwYXNz\r\n\r\n")
    ba = req.basic_auth
    expect(ba[:username]).to eq("user")
    expect(ba[:password]).to eq("pass")

  it "bearer_token is nil for a Basic Authorization header" ->
    req = Request.parse("GET / HTTP/1.1\r\nAuthorization: Basic dXNlcjpwYXNz\r\n\r\n")
    expect(req.bearer_token).to be_nil

  it "basic_auth is nil for a Bearer Authorization header" ->
    req = Request.parse("GET / HTTP/1.1\r\nAuthorization: Bearer tok\r\n\r\n")
    expect(req.basic_auth).to be_nil

  it "authorization is nil when the header is absent" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.authorization).to be_nil
    expect(req.bearer_token).to be_nil
    expect(req.basic_auth).to be_nil

  it "parses a Proxy-Authorization header" ->
    req = Request.parse("GET / HTTP/1.1\r\nProxy-Authorization: Basic dXNlcjpwYXNz\r\n\r\n")
    pc = req.proxy_authorization
    expect(pc.scheme).to eq("basic")
    expect(pc.username).to eq("user")

  it "proxy_authorization is nil when the header is absent" ->
    req = Request.parse("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    expect(req.proxy_authorization).to be_nil

spec_summary
