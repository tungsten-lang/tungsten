# tungsten-api

HTTP execution service for AI agents that cannot install the toolchain in their
sandbox. POST a Tungsten program, get back stdout, stderr, the exit code, and
structured diagnostics.

```
POST /api/check     diagnostics only; never executes
POST /api/run       compile, then run with the sandbox gate latched
GET  /api/version   version, engine, limits, endpoint list
GET  /api/health    liveness
```

Request body is either the bare source (`Content-Type: text/plain`) or JSON
`{"source": "..."}`. The response is always `application/json`.

```sh
curl -sS --data-binary '<< 6 * 7' https://api.tungsten-lang.org/api/run
```

```json
{"ok": true, "engine": "compiled", "version": "2026.07.04", "mode": "run",
 "outcome": "ok", "raised": false, "exception": null,
 "stdout": "42\n", "stderr": "", "exit_code": 0, "diagnostics": [],
 "compile_ms": 271, "run_ms": 200, "duration_ms": 483, "timed_out": false,
 "truncated": false, "compiled": true,
 "sandbox": {"attempts": 0, "log": []}}
```

`stdout` and `stderr` are captured on separate pipes and never merged, so a
program that writes to both keeps them apart — and whatever it printed *before*
dying is still returned.

### How the run ended

Every response carries every key, so a caller never probes for missing fields.
`outcome` is the one-field summary:

| `outcome` | Meaning |
| --- | --- |
| `ok` | exit 0 |
| `raised` | the program threw — uncaught exception or fatal runtime fault |
| `exit` | the program chose a non-zero exit (`exit 3`) — not a crash |
| `timeout` | killed at the run (or compile) limit |
| `compile_error` | never executed; see `diagnostics` |

`raised` is the boolean form, and `exception` carries the detail:

```json
{"outcome": "raised", "raised": true,
 "exception": {"type": "TypeError",
               "message": "TypeError: no implicit conversion of Integer into String",
               "file": "program.w", "line": 2, "column": 1,
               "uncaught_raise": true},
 "stdout": "partial output\n", "exit_code": 1}
```

`raised` deliberately separates "threw" from "exited non-zero": `exit 3` and an
uncaught `raise` both leave a non-zero code, and only one is a crash.

`uncaught_raise` distinguishes the two fatal kinds, which matters when advising
a fix. `true` is an uncaught `raise` — catchable with `begin`/`rescue`. `false`
is a fatal runtime fault such as `undefined method 'x' for nil`, which unwinds
past any `rescue` and can only be fixed in the code, not caught.

A failing `check` returns `ok: false` plus one entry per diagnostic:

```json
{"severity": "error", "runtime": false, "message": "Unterminated string",
 "file": "program.w", "line": 1, "column": 4,
 "code": "E_LEX_UNTERMINATED_STRING"}
```

Every gated syscall attempt comes back in `sandbox.log`, so a caller can see
exactly what a program reached for:

```json
{"sandbox": "block", "op": "read_file", "detail": "/etc/passwd"}
```

## Pieces

| Path | Role |
| --- | --- |
| `services/api/server.w` | HTTP surface (Forge). Routing, body parsing, response encoding. |
| `services/api/lib/exec.w` | Execution engine. Compiles, enforces per-phase timeouts and output caps, parses diagnostics, classifies the outcome, builds the response document. |
| `services/api/bin/exec.w` | CLI wrapper around the engine; prints the response JSON. |
| `core/sandbox.w` + runtime gate | Containment: blocks/stubs outside-world syscalls and logs every attempt. |
| `spec/api/api_exec_spec.w` | Contract spec for the response shape. `RUN_API_SPECS=1 make specs` |

Everything here is Tungsten, including the execution engine — the service
dogfoods the language it serves. The server calls the engine **in-process**, so
there is no second runtime to shell out to and no JSON round-trip between
layers; `Process.spawn` plus shell redirection gives separate stdout/stderr
captures and an exit code, and a poll loop enforces each deadline.

`server.w` never interprets the runner's output — it passes the JSON straight
through, so the contract lives in exactly one place.

## Running it

```sh
bin/tungsten -o /tmp/tungsten_api services/api/server.w
/tmp/tungsten_api 18099
```

`TUNGSTEN_ROOT` must point at the install (bin/tungsten sets it; a bare launch
falls back to `~/.tungsten`). Other knobs:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TUNGSTEN_API_HOST` | `127.0.0.1` | Bind address. Keep it loopback behind a proxy. |
| `TUNGSTEN_API_RUN_TIMEOUT` | `10` | Seconds a program may execute. |
| `TUNGSTEN_API_COMPILE_TIMEOUT` | `60` | Seconds a compile may take. |

## Where this can run

**Not on Cloudflare Workers or Pages.** Running a submitted program means
`fork` + `exec` of a native binary; a Workers isolate has no processes and no
filesystem, so this service cannot run there at any tier. Pages Functions are
Workers and have the same limit.

That does not mean leaving Cloudflare. The recommended shape keeps the static
site exactly where it is:

- `tungsten-lang.org` — static site on Cloudflare Pages (unchanged).
- `api.tungsten-lang.org` — this service on a small VM or container, with
  Cloudflare DNS proxying in front for TLS, caching, and rate limiting.

A single small instance is plenty to start: a run is a sub-second compile plus a
bounded execution. Fly.io (Firecracker microVMs, scale-to-zero) or a Hetzner VPS
both fit; AWS works but is more operational surface than this needs. Moving the
whole site to AWS buys nothing here — the split above is simpler and keeps
Cloudflare as the edge.

A future alternative is compiling the C bytecode VM
(`implementations/c/`) to WASM, which *would* run on Workers and needs no VM at
all. That is a follow-on idea: the C VM has known gaps against the self-hosted
compiler, and for agents fidelity matters more than cleverness — teaching a
model on an engine that diverges from the real compiler undermines the point.

## Hardening required before public traffic

The Tungsten sandbox bounds what a program can *reach* and logs every attempt,
and the runner bounds CPU time and output size. That is not yet a complete jail:

- **`ccall` reaches any linked symbol** directly, bypassing the gate. This is
  the big one.
- **No memory limit** and **no process-count limit** — nothing here stops a
  fork bomb or an allocation spiral.
- **No rate limiting**; every request costs a compile.

Before exposing this to the internet, add an OS-level jail per run
(nsjail/bubblewrap on Linux, or a Firecracker microVM), an rlimit set
(`RLIMIT_AS`, `RLIMIT_NPROC`, `RLIMIT_FSIZE`), and per-IP rate limiting at the
proxy. Treat the sandbox as defense in depth and observability, not as the
boundary.
