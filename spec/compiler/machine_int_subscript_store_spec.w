# Fused machine-int subscript WRITE: `recv[i] = v` with v machine-int typed
# and recv a plain untyped :var lowers to w_index_set_raw_i64/u64 — typed
# integer arrays store raw (no boxed temporary; the old path heap-boxed
# values past 2^48 once per write, the write-side twin of the read leak).
# All other receivers keep byte-identical dynamic dispatch: poly arrays
# store the box, u1 stays strict, Hash/custom []= overloads dispatch,
# floats coerce, OOB is a silent no-op, negative indices wrap, and
# assignment-as-expression still yields the value. Round-3 bug 4,
# 2026-07-22.
#
# Run: `bin/tungsten -o /tmp/mss spec/compiler/machine_int_subscript_store_spec.w && /tmp/mss`

+ SetBox
  -> new(@log) ro
  -> []=(i, v)
    @log.push(i + v)

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> store_i(recv, i, v ## i64)
  recv[i] = v
  recv

-> store_u_big(recv, i)
  s = 88172645463325252 ## u64
  recv[i] = s
  recv

-> store_expr_value(recv)
  v = 7 ## i64
  r = (recv[0] = v)
  r + 1

-> pump(cell, n)
  s = 88172645463325252 ## u64
  i = 0 ## i64
  while i < n
    s = s ^ (s >> 12)
    s = s ^ (s << 25)
    s = s ^ (s >> 27)
    cell[0] = s
    i += 1
  cell[0] ## u64

cell = i64[4]
store_u_big(cell, 0)
check("store.typed_big", cell[0] == 88172645463325252)
store_i(cell, 1, 0 - 9)
check("store.typed_negative", cell[1] == 0 - 9)
store_i(cell, 0 - 1, 77)
check("store.negative_index_wraps", cell[3] == 77)
store_i(cell, 99, 5)
check("store.oob_silent_noop", cell[0] == 88172645463325252)

poly = [1, 2, 3]
store_u_big(poly, 1)
check("store.poly_receiver", poly[1] == 88172645463325252)

h = {}
store_i(h, 5, 10)
check("store.hash_receiver", h[5] == 10)

sb = SetBox.new([])
store_i(sb, 3, 4)
check("store.custom_overload", sb.log[0] == 7)

fl = f64[2]
store_i(fl, 0, 42)
check("store.float_fallback", fl[0] == ~42.0)

check("store.expr_value", store_expr_value(cell) == 8)

# 200k round-trips through the fused write + fused read: exact state per
# the xorshift64* recurrence (independent oracle), and the loop shape that
# leaked ~32 bytes/write before the fix.
rt = i64[2]
final = pump(rt, 200_000)
check("store.loop_roundtrip_exact", final.to_s(16) == "16652e9454e83b5")
