# Sandbox

Run an untrusted Tungsten program with its access to the outside world cut off,
and a record of everything it tried to reach.

```sh
bin/tungsten sandbox untrusted.w
bin/tungsten sandbox --log attempts.jsonl untrusted.w
```

The program runs normally — it computes, it prints, it exits with its own status
— but file IO, sockets, process control, and environment access are intercepted.
Every attempt is logged as one JSON line:

```json
{"sandbox":"block","op":"read_file","detail":"/etc/passwd"}
{"sandbox":"block","op":"system","detail":"curl http://evil.example.com"}
{"sandbox":"stub","op":"env","detail":"HOME"}
```

The log is the point. Prevention alone could be had from an OS jail; the reason
the gate lives *inside* the runtime is that it can name the operation and its
argument — which file, which host, which command — in a form you can feed to
analysis, training, or an alert.

## Two responses: block and stub

An **action** is blocked: the attempt is logged and a catchable error is raised.

```
begin
  data = File.read("/etc/passwd")
rescue e
  << "blocked: [e]"          # sandbox: read_file blocked
```

An **observation** is stubbed: the attempt is logged and a benign value comes
back, so a program that merely *looks* around keeps running instead of dying on
a probe it could have handled.

| Response | Operations |
| --- | --- |
| **block** (raises) | `read_file`, `write_file`, `append_file`, `append_file_to`, `read_dir`, `mmap`, `rename`, `unlink`, `mkdir_p`, `mkdtemp`, `temp_file_for`, `fsync_path`, `fsync_parent`, `system`, `capture`, `proc_spawn`, `proc_wait`, `proc_kill`, `setenv`, `socket_connect`, `socket_listen`, `socket_accept`, `serve_http`, `http3_serve`, and the 14 `w_sci_*` scientific-format readers/writers |
| **stub** (benign value) | `env` → nil, `file_exists` → false, `file_directory` → false, `file_size` → nil, `file_mtime_ns` → nil, `file_id` → nil, `proc_alive` → false |

**Never gated:** stdout and stderr, stdin, clocks, threads, memory, and all pure
computation. A sandboxed program still prints its results — that is what makes
the output worth reading.

## Using it

### CLI

```sh
tungsten sandbox FILE.w [args...]     # compile, then run gated
tungsten sandbox --log PATH FILE.w    # attempt log to PATH instead of stderr
```

Arguments after the source file are passed through to the program untouched.
The exit status is the program's own, so `exit 3` stays `3` and is
distinguishable from a crash.

`--log PATH` matters whenever you are reading the program's output
programmatically: it keeps the attempt log out of stderr, so the two streams
stay separable.

### From Tungsten

```
<< Sandbox.active?     # is the gate latched?
<< Sandbox.attempts    # how many operations have been blocked or stubbed
Sandbox.enable         # latch it for the rest of this process (one-way)
```

`Sandbox.enable` is deliberately one-way: there is no disable, so a program
cannot turn the gate off partway through.

### Environment

| Variable | Effect |
| --- | --- |
| `TUNGSTEN_SANDBOX=1` | Latch the gate for the process. |
| `TUNGSTEN_SANDBOX_LOG=PATH` | Append the attempt log to PATH instead of stderr. |

The CLI sets both for the child, so the child inherits the gate. That is also
how the HTTP service does it — see `services/api/`.

## What it does not protect against

Read this before pointing it at anything hostile. The gate bounds what a program
can *reach through the normal library surface*, and records what it tried. It is
not a complete jail.

- **`ccall` bypasses it.** A program can call any symbol linked into the binary
  directly, including the ungated C entry points behind the gated ones. This is
  the big one, and it is not fixable inside the runtime — `ccall`'s whole
  purpose is raw access.
- **No memory limit.** Nothing stops an allocation spiral.
- **No process-count limit.** `proc_spawn` is gated, but a program that reaches
  `fork` another way is not bounded.
- **No CPU bound.** The gate does not stop an infinite loop; the CLI does not
  impose a timeout (the HTTP service does).
- **A killed run leaks its build directory.** `tungsten sandbox` compiles into a
  `mkdtemp` directory under `TMPDIR` and removes it after the program exits. If
  the run is interrupted, that directory survives until the OS reaps it.
  Tungsten does not expose signal handlers, so this is not currently trappable.

For untrusted code from strangers, run the sandbox *inside* an OS-level jail
(nsjail, bubblewrap, or a Firecracker microVM) with `RLIMIT_AS`, `RLIMIT_NPROC`,
and `RLIMIT_FSIZE` set. Treat this gate as defense in depth and as your
observability layer, not as the boundary.

## How it works

The gate lives in the C runtime (`runtime/runtime.c`). Two functions sit at the
head of every extern that reaches outside the process:

- `w_sandbox_gate(op, detail)` — logs the attempt, then raises.
- `w_sandbox_stub(op, detail)` — logs the attempt and returns 1, letting the
  caller answer with a benign value.

Both are no-ops when the sandbox is off, resolved once into a static, so an
unsandboxed program pays a single predictable branch per call and nothing else.
`core/sandbox.w` exposes the state to Tungsten; `bin/commands/sandbox.w` is the
CLI, written in Tungsten.

`tungsten sandbox` compiles first and runs the binary second, rather than
interpreting. The interpreter would need to read the source file *through* the
gate, which is itself a blocked operation.

Coverage is maintained by auditing the runtime for externs that touch the
filesystem, network, or process table without a gate — that audit is what caught
the atomic-publish family (`unlink`, `mkdir_p`, `temp_file_for`, `fsync_*`,
`append_file_to`), which reaches the filesystem without going through
`File.read`/`File.write`. When adding a runtime extern that touches the outside
world, gate it and add a case to `spec/core/sandbox_spec.w`.

## Testing

`spec/core/sandbox_spec.w` runs in both modes from one file:

```sh
bin/tungsten -o /tmp/sbx spec/core/sandbox_spec.w && /tmp/sbx   # gate OFF
bin/tungsten sandbox spec/core/sandbox_spec.w                   # gate ON
```

Off, it asserts real IO still works and nothing is logged — the zero-impact
half. On, it asserts each operation is blocked or stubbed and counted. Both
halves matter: a gate that broke normal execution would be just as wrong as one
that failed to block.

## See also

- `core/sandbox.w` — the class, and the authoritative op list
- `bin/commands/sandbox.w` — the CLI
- `services/api/` — the HTTP execution service built on this gate, which adds
  per-phase timeouts, output caps, and returns the attempt log to the caller
- `doc/TUNGSTEN.md` — the `sandbox` subcommand in the man page
