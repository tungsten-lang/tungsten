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
