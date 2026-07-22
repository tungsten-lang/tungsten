# Live wire-protocol integration against postgres:///chessbot (trust auth).
use tungsten-pg/pgwire

fails = 0

-> check(label, ok)
  if ok
    << "  ok  [label]"
    0
  else
    << "  FAIL [label]"
    1

c = PgWire.connect("postgres:///chessbot")

# startup captured server params
sv = c.param_status("server_version")
fails += check("param_status server_version ([sv])", sv != nil && sv != "")

# simple query over a real table
rows = c.exec("SELECT key, value FROM schema_meta ORDER BY key")
fails += check("schema_meta rows", rows.size >= 2)
fails += check("schema_meta first row", rows[0][0] == "schema_version")

# exec_params: int param + NULL round-trip
r2 = c.exec_params("SELECT $1::int + 1, NULL::text, $2", ["41", "x"])
fails += check("exec_params arithmetic", r2[0][0] == "42")
fails += check("exec_params NULL cell is nil", r2[0][1] == nil)
fails += check("exec_params text param", r2[0][2] == "x")

# multi-statement: LAST result set wins
r3 = c.exec("SELECT 1; SELECT 2 AS two; SELECT 3 AS three")
fails += check("multi-statement last set", r3[0][0] == "3")
fails += check("command_tag", c.command_tag == "SELECT 1")

# error path: bogus SQL raises, connection stays usable
raised = false
begin
  c.exec("SELECT * FROM table_that_does_not_exist_xyz")
rescue e
  raised = true
  << "  (raised: [e])"
fails += check("error raises", raised)
r4 = c.exec("SELECT 7")
fails += check("connection usable after error", r4[0][0] == "7")

# notices collected
before = c.notices.size
c.exec("DROP TABLE IF EXISTS pgwire_no_such_table")
fails += check("notice captured", c.notices.size > before)

# in_txn tracking
c.exec("BEGIN")
fails += check("in_txn true after BEGIN", c.in_txn)
c.exec("ROLLBACK")
fails += check("in_txn false after ROLLBACK", !c.in_txn)

# COPY round-trip with a chunk split mid-row
c.exec("CREATE TEMP TABLE pgwire_copy(a INT, b TEXT)")
c.copy_start("COPY pgwire_copy FROM STDIN")
c.copy_write("1\thel")
c.copy_write("lo\n2\tworld\n3\t")
c.copy_write("chunks\n")
tag = c.copy_finish()
fails += check("copy tag ([tag])", tag == "COPY 3")
r5 = c.exec("SELECT count(*), min(b), max(b) FROM pgwire_copy")
fails += check("copy contents", r5[0][0] == "3" && r5[0][1] == "chunks" && r5[0][2] == "world")

# exec refuses COPY FROM STDIN (CopyFail path) and stays usable
raised = false
begin
  c.exec("COPY pgwire_copy FROM STDIN")
rescue e
  raised = true
fails += check("exec of COPY raises", raised)
r6 = c.exec("SELECT 8")
fails += check("usable after CopyFail", r6[0][0] == "8")

# pooled-buffer growth: one message bigger than the 64KB initial pool
# (200KB cell forces ensure_rbuf to double mid-connection), then a small
# query proves the connection still frames correctly afterwards.
rbig = c.exec("SELECT length(repeat('x', 200000)), repeat('y', 70000)")
fails += check("200k-cell message", rbig[0][0] == "200000")
fails += check("70k cell intact", rbig[0][1].bytes.size == 70000)
rafter = c.exec("SELECT 11")
fails += check("small frame after growth", rafter[0][0] == "11")

# copy_write_slice: stream sub-ranges of one staging buffer
c.exec("CREATE TEMP TABLE pgwire_slice(a INT, b TEXT)")
c.copy_start("COPY pgwire_slice FROM STDIN")
stage = pgw_str_to_bytes("IGNORED1\tsliced\n2\tcopy\nIGNORED")
c.copy_write_slice(stage, 7, 9)      # "1\tsliced\n"
c.copy_write_slice(stage, 16, 7)     # "2\tcopy\n"
c.copy_write_slice(stage, 0, 0)      # no-op
tag2 = c.copy_finish()
fails += check("copy_write_slice tag ([tag2])", tag2 == "COPY 2")
r5b = c.exec("SELECT b FROM pgwire_slice ORDER BY a")
fails += check("copy_write_slice contents", r5b[0][0] == "sliced" && r5b[1][0] == "copy")

# framing robustness + throughput: 20k rows (> 64KB of data)
t0 = clock()
big = c.exec("SELECT g, 'row-' || g FROM generate_series(1, 20000) g")
dt = clock() - t0
fails += check("20k rows arrived", big.size == 20000)
fails += check("20k first/last", big[0][0] == "1" && big[19999][1] == "row-20000")
rps = ~20000.0 / dt
<< "  (20k rows in [dt]s ≈ [rps] rows/sec)"

fails += check("trust path recorded", c.auth_method == "trust")
c.close()

# URL with explicit host:port + user
c2 = PgWire.connect("postgres://erik@127.0.0.1:5432/chessbot")
r7 = c2.exec("SELECT current_database()")
fails += check("explicit-URL connect", r7[0][0] == "chessbot")
c2.close()

# --- live SCRAM-SHA-256: role pgwire_scram is forced to scram-sha-256 by
# pg_hba for chessbot_test over 127.0.0.1/::1. The password is a local
# dev-only test credential for that scratch database — fine to hardcode.
c3 = PgWire.connect("postgres://pgwire_scram:pgwire-scram-test-pw@127.0.0.1:5432/chessbot_test")
fails += check("scram connect used scram", c3.auth_method == "scram-sha-256")
r8 = c3.exec("SELECT 1")
fails += check("scram connection queries", r8[0][0] == "1")
c3.close()

# wrong password → clean auth-failure raise (no hang, no crash)
raised = false
msg = ""
begin
  PgWire.connect("postgres://pgwire_scram:wrong-password@127.0.0.1:5432/chessbot_test")
rescue e
  raised = true
  msg = "[e]"
fails += check("scram wrong password raises ([msg])", raised && msg.starts_with?("PG:"))

if fails > 0
  << "wire_test: [fails] FAILED"
  exit(1)
<< "wire_test: all passed"
