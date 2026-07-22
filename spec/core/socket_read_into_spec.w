# Socket#read_into(buf, offset, n) / Socket#write_slice(buf, offset, len) —
# the allocation-free pooled-buffer twins of read_exact / write_bytes
# (added for tungsten-pg's pgwire read path). Loopback self-test: listener
# and client in one process; small payloads sit in kernel buffers so the
# single-threaded connect → accept → write → read sequencing is safe.
# Needs RUN_CORE_SPECS=1 in scripts/test-specs.sh.

-> fail_check(name, detail = "")
  << "FAIL: [name] [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

port = 39471
l = Socket.listen("127.0.0.1", port)
c = Socket.connect("127.0.0.1", port)
s = l.accept

# --- read_into lands at the offset, count returned, sentinels untouched
payload = u8[10]
i = 0
while i < 10
  payload[i] = 100 + i
  i += 1
c.write_bytes(payload)

buf = u8[16]
i = 0
while i < 16
  buf[i] = 0xEE
  i += 1
got = s.read_into(buf, 3, 10)
check("read_into count", got, 10)
check("read_into sentinel before", buf[2], 0xEE)
check("read_into first", buf[3], 100)
check("read_into last", buf[12], 109)
check("read_into sentinel after", buf[13], 0xEE)

# --- read_into n=0 is a no-op returning 0
check("read_into zero", s.read_into(buf, 0, 0), 0)

# --- out-of-range raises (buffer is never grown)
raised = false
begin
  s.read_into(buf, 10, 10)
rescue e
  raised = true
check("read_into out-of-range raises", raised, true)

raised = false
begin
  s.read_into(buf, 0 - 1, 4)
rescue e
  raised = true
check("read_into negative offset raises", raised, true)

# --- write_slice sends exactly the sub-range
src = u8[12]
i = 0
while i < 12
  src[i] = 200 + i
  i += 1
wrote = s.write_slice(src, 4, 5)      # bytes 204..208
check("write_slice count", wrote, 5)
rcv = c.read_exact(5)
check("write_slice first", rcv[0], 204)
check("write_slice last", rcv[4], 208)

# --- write_slice len=0 writes nothing (marker byte proves stream position)
check("write_slice zero", s.write_slice(src, 0, 0), 0)
marker = u8[1]
marker[0] = 0x7F
s.write_bytes(marker)
rcv2 = c.read_exact(1)
check("write_slice zero sent nothing", rcv2[0], 0x7F)

# --- write_slice out-of-range raises
raised = false
begin
  s.write_slice(src, 8, 8)
rescue e
  raised = true
check("write_slice out-of-range raises", raised, true)

# --- EOF: peer closes → read_into returns nil (read_exact semantics)
c.close
eof = s.read_into(buf, 0, 1)
check("read_into EOF nil", eof, nil)

s.close
l.close
<< "socket_read_into_spec: all passed"
