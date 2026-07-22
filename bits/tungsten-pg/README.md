# tungsten-pg

PostgreSQL for Tungsten, two ways:

1. **`lib/pgwire.w` — pure-Tungsten wire-protocol (v3) client. The default.**
   No libpq, no C, no link dependency: `Socket.connect` + core crypto speak
   the protocol directly on port 5432.
2. **`native/pg_bridge.c` — optional libpq fast path.** A thin `ccall`
   surface (`w_pg_connect`, `w_pg_exec`, `w_pg_exec_params`, `w_pg_copy_*`,
   `w_pg_last_error`) that `dlopen`s libpq at first use. Linked into any
   project whose Bitfile has `requires ["tungsten-pg"]`; if libpq is absent
   it raises with install instructions (`TUNGSTEN_PG_LIBPQ` overrides the
   search path).

## Pure client

```tungsten
use tungsten-pg/pgwire

c = PgWire.connect("postgres:///mydb")        # → 127.0.0.1:5432, TCP only
rows = c.exec("SELECT key, value FROM t")      # poly rows of String/nil
r = c.exec_params("SELECT $1::int + 1", ["41"])
c.copy_start("COPY t FROM STDIN")
c.copy_write("1\thello\n")                     # chunks need not align to rows
c.copy_finish                                  # → "COPY 1"
c.close
```

Also: `command_tag`, `notices`, `param_status(name)`, `in_txn`, `last_error`.
Errors raise `"PG: <severity> <sqlstate> <message>"` after draining to
ReadyForQuery — the connection stays usable.

### Protocol coverage

| Area | Status |
|---|---|
| Startup / ParameterStatus / BackendKeyData | ✔ |
| Auth: trust, cleartext, md5, SCRAM-SHA-256 (RFC 7677, server-signature verified) | ✔ |
| Auth: SCRAM-SHA-256-PLUS (channel binding), GSS/SSPI, TLS | ✖ |
| Simple query, multi-statement (last result set returned) | ✔ |
| Extended query (Parse/Bind/Execute/Sync), text format, NULL params | ✔ |
| COPY FROM STDIN (chunked, mid-row splits fine) | ✔ |
| COPY TO STDOUT | ✖ (raises) |
| Notices, NotificationResponse (ignored), NegotiateProtocolVersion (ignored) | ✔ |
| Cancel requests, prepared-statement reuse, binary format | ✖ |

**TCP only**: the runtime has no unix-socket surface, so `postgres:///db`
and host-less URLs mean `127.0.0.1:5432`. Passwords are ASCII (no SASLprep);
use `PGPASSWORD` for passwords containing `:` or `@`.

Throughput: ~700k rows/sec on a local 20k-row × 2-col text result
(Apple Silicon, `--release`).

## Tests

```sh
test/run_tests.sh          # PGWIRE_TEST_DB=0 skips the live-server tests
```

`scram_test.w` pins the auth math to RFC 4231 / RFC 7677 vectors byte-for-byte;
`wire_test.w` runs the full live matrix (params, NULLs, errors-then-reuse,
notices, transactions, chunk-split COPY, CopyFail recovery, 20k-row framing)
against `postgres:///chessbot` with trust auth.

## attic/

Pre-rewrite Ruby-dialect sources that never compiled under the self-hosted
toolchain. Reference only.
