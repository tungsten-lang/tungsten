# Focused spec for Round 3 Tranches 15, 16, and 18:
# - WIRE CSE load-load forwarding & cross-call unescaped slot preservation
# - Mixed-type slot safety (pipeline fusion i64/f64 reuse)
# - setjmp / begin-rescue DSE and CSE safety
# - i48 constant boxing boundaries (signed & unsigned)
# - Leaf WIRE inlining (ro/rw getters/setters, passthrough, binop, forwarding wrappers)
# - Box-unbox roundtrip elimination (i64, u64, f64, including >i48 BigInt values)

-> check(label, cond)
  if !cond
    << "FAIL: " + label
    exit(1)

+ LeafBox
  ro :x
  rw :y

  -> new(x, y)
    @x = x
    @y = y

-> leaf_passthrough(a)
  a

-> leaf_add(a, b)
  a + b

-> leaf_fwd_len(s)
  s.size()

-> side_effect_noop(v)
  v

# 1. Cross-call load-load CSE & unescaped local preservation
-> test_cross_call_cse(n)
  total = 0
  x = n + 5
  side_effect_noop(x)
  total += x
  side_effect_noop(total)
  total += x
  total

check("cross_call_cse", test_cross_call_cse(10) == 30)

# 2. Escaped closure slot must NOT falsely forward across calls that mutate it
-> test_escaped_closure_cse
  x = 10
  bump = -> (d)
    x = x + d
  a = x
  bump.call(5)
  b = x
  bump.call(7)
  c = x
  [a, b, c]

esc_res = test_escaped_closure_cse()
check("escaped_closure_cse", esc_res[0] == 10 && esc_res[1] == 15 && esc_res[2] == 22)

# 3. setjmp / begin-rescue DSE and CSE safety:
#    stores before a raising call MUST survive into rescue!
-> maybe_raise(flag)
  if flag
    raise "boom"
  99

-> test_setjmp_dse_safety(flag)
  state = 1
  begin
    state = 2
    maybe_raise(flag)
    state = 3
  rescue e
    return state
  state

check("setjmp_dse_rescue", test_setjmp_dse_safety(true) == 2)
check("setjmp_dse_normal", test_setjmp_dse_safety(false) == 3)

# 4. Mixed-type slot safety in fused f64 pipelines
-> test_pipeline_f64_mixed_slot
  xs = f64[4]
  xs[0] = ~1.5
  xs[1] = ~2.5
  xs[2] = ~3.0
  xs[3] = ~4.0
  s = xs.map(-> (v) v * ~2.0).sum()
  mn = xs.map(-> (v) v + ~1.0).min()
  mx = xs.map(-> (v) v + ~1.0).max()
  empty = f64[0]
  es = empty.map(-> (v) v * ~2.0).sum()
  [s, mn, mx, es]

pf = test_pipeline_f64_mixed_slot()
check("pipeline_f64_sum", pf[0] == ~22.0)
check("pipeline_f64_min", pf[1] == ~2.5)
check("pipeline_f64_max", pf[2] == ~5.0)
check("pipeline_f64_empty_sum", pf[3] == 0)

# 5. i48 constant boxing boundaries (signed & unsigned)
-> test_i48_boxing_boundaries
  a = 0 ## i64
  b = 1 ## i64
  c = -1 ## i64
  max48 = 140737488355327 ## i64
  min48 = -140737488355328 ## i64
  over48 = 140737488355328 ## i64
  under48 = -140737488355329 ## i64
  u0 = 0 ## u64
  umax48 = 140737488355327 ## u64
  uover48 = 140737488355328 ## u64
  ubig = 9223372036854775808 ## u64
  boxed = [a, b, c, max48, min48, over48, under48, u0, umax48, uover48, ubig]
  check("i48_0", boxed[0] == 0)
  check("i48_1", boxed[1] == 1)
  check("i48_neg1", boxed[2] == -1)
  check("i48_max", boxed[3] == 140737488355327)
  check("i48_min", boxed[4] == -140737488355328)
  check("i48_over", boxed[5] == 140737488355328)
  check("i48_under", boxed[6] == -140737488355329)
  check("u48_0", boxed[7] == 0)
  check("u48_max", boxed[8] == 140737488355327)
  check("u48_over", boxed[9] == 140737488355328)
  check("u64_big", boxed[10] == 9223372036854775808)
  true

test_i48_boxing_boundaries()

# 6. Leaf WIRE inlining (ro, rw, passthrough, binop, forwarding wrapper)
lb = LeafBox.new(42, 7)
check("leaf_ro", lb.x == 42)
lb.y = 99
check("leaf_rw", lb.y == 99)
check("leaf_passthrough", leaf_passthrough(123) == 123)
check("leaf_add", leaf_add(17, 25) == 42)
check("leaf_fwd_len", leaf_fwd_len("tungsten") == 8)

# 7. Box-unbox roundtrip elimination (i64, u64, f64, including >i48 values & loops)
-> test_box_unbox_roundtrips(n)
  arr = i64[4]
  arr[0] = 1000000000000000000 ## i64
  arr[1] = -1000000000000000000 ## i64
  arr[2] = 42 ## i64
  arr[3] = 7 ## i64
  acc = 0 ## i64
  i = 0
  while i < n
    v = arr[i & 3]
    # Re-enter machine i64 arithmetic from boxed slot v
    w = (v + (1 ## i64)) ## i64
    acc = (acc + w) ## i64
    i += 1
  acc

check("box_unbox_i64_big", test_box_unbox_roundtrips(4) == 53)

-> test_box_unbox_u64_f64
  uarr = u64[2]
  uarr[0] = 10000000000000000000 ## u64
  uarr[1] = 5 ## u64
  uv = uarr[0]
  u2 = (uv + (uarr[1] ## u64)) ## u64
  farr = f64[2]
  farr[0] = ~1.25
  farr[1] = ~2.75
  fv = farr[0]
  f2 = (fv + farr[1]) ## f64
  check("box_unbox_u64", u2 == 10000000000000000005)
  check("box_unbox_f64", f2 == ~4.0)
  true

test_box_unbox_u64_f64()

<< "PASS wire_opt_and_inline_spec"
