# Forge

**High-performance HTTP server for Tungsten.** Tungsten is forged at extreme temperatures.

Forge is the built-in web server for Carbide applications — multi-threaded, TLS by default, with HTTP/3 (QUIC), HTTP/2, and HTTP/1.1 support.

## Quick Start

```tungsten
use Forge

Forge.configure ->
  host "0.0.0.0"
  port 443
  workers System.cpu_count

Forge.routes ->
  get "/" -> (request)
    Response.ok("Welcome to Forge")

  get "/health" -> (request)
    Response.json({status: "ok", uptime: Forge.uptime})

Forge.start
```

## Configuration

```tungsten
Forge.configure ->
  host "0.0.0.0"
  port 443
  tls auto: true          # Let's Encrypt auto-provisioning
  workers System.cpu_count
  max_connections 10_000

  # HTTP/3 enabled by default
  protocols [:h3, :h2, :http11]

  # All paths downcased and trailing-slash stripped
  normalize_paths true

  # Timeouts
  read_timeout 30
  write_timeout 30
  idle_timeout 120

  # Static files with zero-copy sendfile
  static_dir "public"
  cache_control "public, max-age=3600"
```

## Design Principles

- **TLS by default** — plain HTTP requires explicit `tls: false`
- **HTTP/3 (QUIC)** with HTTP/2 and HTTP/1.1 fallback
- **Downcased paths** — router normalizes all paths to lowercase before matching
- **Multi-threaded** — work-stealing thread pool, configurable worker count
- **Zero-copy** where possible — sendfile for static assets
- **Auto-cert** — built-in Let's Encrypt ACME client for production TLS

## Middleware

```tungsten
Forge.use Forge:Middleware:Logger
Forge.use Forge:Middleware:Compression
Forge.use Forge:Middleware:CORS, origins: ["https://example.com"]
Forge.use Forge:Middleware:RateLimit, requests: 100, per: :minute
```

## WebSocket

```tungsten
Forge.routes ->
  websocket "/ws" -> (socket)
    socket.on :message -> (data)
      socket.send("echo: #{data}")

    socket.on :close ->
      Logger.info("Client disconnected")
```

## Behind a Proxy

When Forge runs behind a reverse proxy or load balancer, `request.remote_addr` is the *proxy's* address. The request surface parses both the RFC 7239 `Forwarded` header and the de-facto `X-Forwarded-*` family so handlers can recover the real client:

```tungsten
get "/whoami" -> (request)
  Response.json({
    ip:     request.client_ip,       # leftmost forwarded address, or remote_addr
    chain:  request.forwarded_for,   # full address chain, client-first, hosts bare
    proto:  request.forwarded_proto, # "https" / "http" (RFC 7239 proto or X-Forwarded-Proto)
    host:   request.forwarded_host,  # original Host
    port:   request.forwarded_port,  # X-Forwarded-Port as an Integer
    secure: request.forwarded_ssl?,  # true when the client used TLS
    proxied: request.via_proxy?
  })
```

`request.forwarded` returns the structured RFC 7239 elements (each a hash of `for`/`by`/`host`/`proto`). **Security:** these headers are client-forgeable — trust `client_ip` only when a proxy you control sanitizes the inbound value.

## Caching

Forge parses `Cache-Control` into structured directives on both the request and response surface, so handlers can honour a client's freshness demands and a cache layer can read back the lifetime a response declares:

```tungsten
get "/data" -> (request)
  cc = request.cache_control        # a CacheControl (never nil)

  if cc.no_cache? || cc.max_age == 0
    revalidate                      # client forced a fresh check

  Response.json(payload).cache(3600)
```

`CacheControl` exposes the RFC 7234 directive set as query methods:

```tungsten
cc = request.cache_control
cc.no_cache?           # / no_store? / no_transform? / only_if_cached?
cc.public?             # / private? / must_revalidate? / proxy_revalidate? / immutable?
cc.max_age             # delta-seconds as an Integer, or nil (also s_maxage,
                       # min_fresh, stale_while_revalidate, stale_if_error)
cc.max_stale           # nil / :any (no bound) / an Integer bound
cc.no_cache_fields     # field-name list from no-cache="…" (and private_fields)
cc.get("max-age")      # raw directive value, or nil
```

Directive names are case-insensitive, `no-cache="Set-Cookie"` values are unquoted, and a comma inside a quoted-string is not a separator. `Response#cache_control` reads back whatever `#cache` / `#no_cache` (or a raw `#header`) wrote — the read counterpart to the response writers.

## Authentication

Forge parses the `Authorization` (and `Proxy-Authorization`) header into a structured `Credentials`, with conveniences for the two schemes almost every app reads — Bearer tokens and Basic credentials. The Basic base64 decode is a pure Tungsten codec, so it behaves identically whether a route runs compiled or interpreted:

```tungsten
get "/api/data" -> (request)
  token = request.bearer_token         # RFC 6750 Bearer token, or nil
  return Response.new(status: 401) if token == nil
  Response.json(lookup(token))

get "/admin" -> (request)
  creds = request.basic_auth           # {username:, password:} (RFC 7617), or nil
  if creds == nil || !authenticate(creds[:username], creds[:password])
    Response.new(status: 401).header("WWW-Authenticate", "Basic realm=\"admin\"")
  else
    Response.ok("welcome")
```

`request.authorization` returns the raw `Credentials` for any scheme:

```tungsten
creds = request.authorization    # nil when no Authorization header
creds.scheme                     # downcased scheme token ("bearer", "basic", "digest", …)
creds.scheme?("Bearer")          # case-insensitive scheme test
creds.credentials                # the raw token68 / base64 / auth-param string
creds.token                      # the Bearer token, or nil when not Bearer
creds.username / creds.password  # decoded Basic userid / password, or nil
creds.basic_credentials          # {username:, password:} for Basic, else nil
```

Basic credentials split on the **first** colon (a userid may not contain one; a password may). Malformed base64, or a non-matching scheme, yields nil rather than raising. `Base64Codec.decode` is available directly for any standard-alphabet base64 the request surface hands you.

## Static Files

```tungsten
Forge.configure ->
  static_dir "public"
  cache_control "public, max-age=31536000, immutable"
  etag true
```

Static files are served with zero-copy `sendfile`, automatic ETag generation, and configurable `Cache-Control` headers.

## Benchmarks (requests/sec, hello world, 64 concurrent connections)

| Server        | Language   | req/s      | Notes                          |
|---------------|------------|------------|--------------------------------|
| Forge         | Tungsten   | 850,000    | io_uring, zero-alloc hot path  |
| Actix-web     | Rust/Tokio | 720,000    | work-stealing, epoll/io_uring  |
| Bun.serve     | Zig/JS     | 520,000    | io_uring, single-threaded      |
| Fasthttp      | Go         | 480,000    | goroutines, netpoller          |
| Cowboy        | Elixir     | 290,000    | BEAM processes, ranch           |
| Puma          | Ruby       | 120,000    | thread pool, GVL               |

*Aspirational targets. Actual benchmarks will be published with the first stable release.*

### Why Forge can be this fast

- **io_uring** (Linux) / kqueue (macOS) — batch I/O submissions, zero-syscall completions
- **Zero allocation hot path** — request/response object pools, ring buffers for I/O, arena allocators for per-request scratch
- **No GC in the server loop** — all server internals are pre-allocated; GC only touches application objects
- **M:N scheduling** — lightweight tasks on work-stealing thread pool
- **HTTP/2 multiplexing** — many requests over one TCP connection, persistent keep-alive
- **In-place parsing** — HTTP headers parsed directly from the read buffer, no copy

### Built-in infrastructure (no external dependencies)

- **Message queues** — built-in persistent job queue. No RabbitMQ, no Redis, no Sidekiq. Enqueue work, workers pull from the queue, retries and dead-letter handling included.
- **Pub/sub** — built-in publish/subscribe channels for real-time events. WebSocket clients subscribe to topics, server publishes. No need for a separate pub/sub service.
- **Canned responses** — pre-rendered response buffers for known endpoints. `/health`, `/ping`, static JSON responses are served directly from memory without touching the handler chain. Zero-alloc, zero-parse, just write the pre-built bytes to the socket.

## License

MIT
