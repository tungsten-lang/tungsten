# spec: compiled -- tests compiled w_check_array_ebits guards, WIRE lowering, and closed-world fast builtins
# Regression spec for Round 4 compiler, lowering, WIRE, and fast-builtin improvements:
#   - Confirmed typed-array ivar inference & soundness (lazy init, subclass, untyped write, early self escape)
#   - Same-BB w_check_array_ebits CSE
#   - String interpolation fast path (w_str_concat_any) incl. cached heap string from custom to_s
#   - Proven-i48 nanbox_int narrowing & >i48 BigInt boundary preservation
#   - Wave-2 closed-world fast builtins (has_key?, keys, empty?, starts_with?, ends_with?, slice, byte_at, strip, index, abs)
#   - Fixed-layout i128/u128/f64/f32 WIRE constructors, i128/u128 param unboxing, and direct-buffer emitter parity
#   - Sound return-type inference over yield/untyped/missing-else branches and recursive SCCs

$ok = true
$fail_count = 0

-> check(cond, label)
  if !cond
    << "FAIL: " + label
    $ok = false
    $fail_count += 1

# ---- 1. Confirmed typed-array ivars & soundness ----

-> sum_i64_arr(a, n) (i64[] i64) i64
  acc = 0 ## i64
  i = 0 ## i64
  while i < n
    acc += a[i]
    i += 1
  acc

-> sum_u32_arr(a, n) (u32[] i64) i64
  acc = 0 ## i64
  i = 0 ## i64
  while i < n
    acc += a[i]
    i += 1
  acc

-> sum_u8_arr(a, n) (u8[] i64) i64
  acc = 0 ## i64
  i = 0 ## i64
  while i < n
    acc += a[i]
    i += 1
  acc

+ SealedArrays
  -> new(flag)
    @a64 = i64[4]
    @a32 = u32[4]
    @a8 = u8[4]
    @cond_a64 = flag ? i64[4] : i64[2]
    @a64[0] = 10
    @a64[1] = 20
    @a64[2] = 30
    @a64[3] = 40
    @a32[0] = 1
    @a32[1] = 2
    @a32[2] = 3
    @a32[3] = 4
    @a8[0] = 5
    @a8[1] = 6
    @a8[2] = 7
    @a8[3] = 8
    @cond_a64[0] = 100
    @cond_a64[1] = 200

  -> totals
    sum_i64_arr(@a64, 4) + sum_u32_arr(@a32, 4) + sum_u8_arr(@a8, 4) + sum_i64_arr(@cond_a64, 2)

sa1 = SealedArrays.new(true)
sa2 = SealedArrays.new(false)
check(sa1.totals == 436, "sealed confirmed typed-array ivars (true arm)")
check(sa2.totals == 436, "sealed confirmed typed-array ivars (false arm)")

# Soundness 1: lazy/uninitialized ivar is not confirmed (must stay guarded / nil-safe)
+ LazyArrayHolder
  -> new
    @ready = false
  -> init_buf
    @buf = i64[3]
    @buf[0] = 7
    @buf[1] = 8
    @buf[2] = 9
    @ready = true
  -> read_sum
    if @buf == nil
      return -1
    sum_i64_arr(@buf, 3)

lh = LazyArrayHolder.new
check(lh.read_sum == -1, "uninitialized lazy ivar observed as nil before init")
lh.init_buf
check(lh.read_sum == 24, "lazy ivar succeeds after init")

# Soundness 2: subclass mutating ivar width must still be guarded
+ BaseArrHolder
  -> new
    @arr = i64[3]
    @arr[0] = 1
    @arr[1] = 2
    @arr[2] = 3
  -> total
    sum_i64_arr(@arr, 3)

+ SubArrHolder < BaseArrHolder
  -> swap_to_u32
    @arr = u32[3]

sub_h = SubArrHolder.new
check(sub_h.total == 6, "subclass base i64[] total works")
sub_h.swap_to_u32
sub_raised = false
begin
  sub_h.total
rescue e
  sub_raised = true
check(sub_raised, "subclass mutating @arr to u32[] still triggers ebits guard")

# Soundness 3: untyped setter invalidates confirmed ivar proof
+ MutableArrHolder
  -> new
    @arr = i64[2]
    @arr[0] = 11
    @arr[1] = 22
  -> set_arr(x)
    @arr = x
  -> total
    sum_i64_arr(@arr, 2)

mh = MutableArrHolder.new
check(mh.total == 33, "mutable holder initial i64[] works")
mh.set_arr(u32[2])
mh_raised = false
begin
  mh.total
rescue e
  mh_raised = true
check(mh_raised, "untyped setter to u32[] still triggers ebits guard")

# Soundness 4: self-call inside new before ivar assignment must not confirm ivar
+ EarlyEscapeHolder
  -> new
    @early_saw_nil = (self.peek_late == -1)
    @late = i64[2]
    @late[0] = 4
    @late[1] = 5
  -> peek_late
    if @late == nil
      return -1
    sum_i64_arr(@late, 2)
  -> early_saw_nil?
    @early_saw_nil

eeh = EarlyEscapeHolder.new
check(eeh.early_saw_nil?, "early self-call before ivar init sees nil (not confirmed)")
check(eeh.peek_late == 9, "ivar after init works")

# Same-BB w_check_array_ebits CSE on untyped local
-> double_sum_untyped(a)
  sum_i64_arr(a, 3) + sum_i64_arr(a, 3)

raw_a = i64[3]
raw_a[0] = 2
raw_a[1] = 3
raw_a[2] = 5
check(double_sum_untyped(raw_a) == 20, "same-BB ebits CSE on valid i64[]")
cse_raised = false
begin
  double_sum_untyped(u32[3])
rescue e
  cse_raised = true
check(cse_raised, "same-BB ebits CSE still rejects wrong width u32[]")

# ---- 2. String interpolation fast path & custom cached-string to_s ----

+ CachedToS
  -> new(prefix)
    # Build a heap (>61 byte) string owned by @cached so freeing it would UAF.
    @cached = prefix + "_0123456789_0123456789_0123456789_0123456789_0123456789_0123456789"
  -> to_s
    @cached

-> interp_poly(a, b, c, d, e)
  "A=[a]|B=[b]|C=[c]|D=[d]|E=[e]"

ct = CachedToS.new("cached")
s_interp_1 = interp_poly("hello", -42, :sym_ok, nil, true)
check(s_interp_1 == "A=hello|B=-42|C=sym_ok|D=|E=true", "w_str_concat_any fast arms")
s_interp_2 = interp_poly(false, 10**25, ct, 3.5, "world")
expected_ct = "cached_0123456789_0123456789_0123456789_0123456789_0123456789_0123456789"
check(s_interp_2 == "A=false|B=10000000000000000000000000|C=" + expected_ct + "|D=3.5|E=world", "w_str_concat_any slow arms + custom to_s")
# Call a second time to verify ct.@cached was NOT freed by interpolation
check("again:[ct]:end" == "again:" + expected_ct + ":end", "cached heap string from custom to_s survives repeated interpolation")

# Known-string part skips w_to_s
-> interp_known_str(x)
  s = "val_" + x.to_s()
  "<[s]>"
check(interp_known_str(7) == "<val_7>", "known-string interpolation arm")

# ---- 3. Proven-i48 nanbox_int & >i48 BigInt boundaries ----

i32_buf = i32[3]
i32_buf[0] = -2147483648
i32_buf[1] = 2147483647
i32_buf[2] = -1
u32_buf = u32[2]
u32_buf[0] = 4294967295
u32_buf[1] = 0

-> box_proven_i48(a32, au32, idx, flag) (i32[] u32[] i64 bool)
  v1 = a32[idx]
  v2 = au32[0]
  sel = flag ? a32[0] : a32[1]
  masked = (v2 & 65535)
  shifted = (v2 >> 20)
  [v1, v2, sel, masked, shifted, a32.size]

bp_t = box_proven_i48(i32_buf, u32_buf, 2, true)
bp_f = box_proven_i48(i32_buf, u32_buf, 1, false)
check(bp_t[0] == -1 && bp_t[1] == 4294967295 && bp_t[2] == -2147483648 && bp_t[3] == 65535 && bp_t[4] == 4095 && bp_t[5] == 3, "proven-i48 nanbox_int values (true)")
check(bp_f[0] == 2147483647 && bp_f[2] == 2147483647, "proven-i48 nanbox_int select_i64 (false)")

# Values beyond signed i48 MUST NOT be truncated to i48
i64_big = i64[3]
one64 = 1 ## i64
i64_big[0] = (one64 << 47)
i64_big[1] = (one64 << 55) + 12345
i64_big[2] = -(one64 << 55) - 6789

-> box_wide_i64(a, i) (i64[] i64)
  a[i]

check(box_wide_i64(i64_big, 0) == 140737488355328, "2^47 promotes to BigInt (not truncated)")
check(box_wide_i64(i64_big, 1) == 36028797018976313, "2^55 + 12345 preserves full i64")
check(box_wide_i64(i64_big, 2) == -36028797018970757, "-(2^55) - 6789 preserves full i64")

# ---- 4. Wave-2 closed-world fast builtins + custom class fallback ----

+ CustomFastTarget
  -> has_key?(k)
    k == :magic
  -> keys
    [:custom_k]
  -> empty?
    false
  -> starts_with?(p)
    p == "cust"
  -> ends_with?(s)
    s == "end"
  -> slice(a, b)
    a * 10 + b
  -> byte_at(i)
    900 + i
  -> strip
    "custom_stripped"
  -> index(x)
    x == :hit ? 77 : nil
  -> abs
    999

-> call_has_key(r, k)
  r.has_key?(k)
-> call_keys(r)
  r.keys
-> call_empty(r)
  r.empty?
-> call_starts_with(r, p)
  r.starts_with?(p)
-> call_ends_with(r, s)
  r.ends_with?(s)
-> call_slice2(r, a, b)
  r.slice(a, b)
-> call_byte_at(r, i)
  r.byte_at(i)
-> call_strip(r)
  r.strip
-> call_index(r, x)
  r.index(x)
-> call_abs(r)
  r.abs

h = {a: 1, b: 2}
h_empty = {}
arr = [10, 20, 30, 40]
arr_empty = []
s_short = "abcde"
s_long = "  hello_tungsten_world  "
cft = CustomFastTarget.new

check(call_has_key(h, :a) == true && call_has_key(h, :z) == false, "w_fast_has_key Hash")
check(call_has_key(cft, :magic) == true && call_has_key(cft, :no) == false, "w_fast_has_key fallback")

check(call_keys(h).size == 2 && call_keys(cft)[0] == :custom_k, "w_fast_keys Hash + fallback")

check(call_empty(arr_empty) == true && call_empty(arr) == false, "w_fast_empty Array")
check(call_empty(h_empty) == true && call_empty(h) == false, "w_fast_empty Hash")
check(call_empty("") == true && call_empty(s_short) == false && call_empty(s_long) == false, "w_fast_empty String")
check(call_empty(cft) == false, "w_fast_empty fallback")

check(call_starts_with(s_short, "ab") == true && call_starts_with(s_short, "ac") == false && call_starts_with(s_short, "") == true && call_starts_with(s_short, "abcdef") == false, "w_fast_starts_with SSO-5")
check(call_starts_with(s_long, "  hello") == true && call_starts_with(s_long, "world") == false, "w_fast_starts_with long")
check(call_starts_with(cft, "cust") == true && call_starts_with(cft, "no") == false, "w_fast_starts_with fallback")

check(call_ends_with(s_short, "de") == true && call_ends_with(s_short, "ce") == false && call_ends_with(s_short, "") == true && call_ends_with(s_short, "xabcde") == false, "w_fast_ends_with SSO-5")
check(call_ends_with(s_long, "world  ") == true && call_ends_with(s_long, "hello") == false, "w_fast_ends_with long")
check(call_ends_with(cft, "end") == true && call_ends_with(cft, "no") == false, "w_fast_ends_with fallback")

check(call_slice2(s_short, 1, 3) == "bcd" && call_slice2(s_long, 2, 5) == "hello", "w_fast_slice2 String")
sl_arr = call_slice2(arr, 1, 2)
check(sl_arr.size == 2 && sl_arr[0] == 20 && sl_arr[1] == 30, "w_fast_slice2 Array")
check(call_slice2(cft, 3, 4) == 34, "w_fast_slice2 fallback")

check(call_byte_at(s_short, 0) == 97 && call_byte_at(s_short, -1) == 101 && call_byte_at(s_short, 5) == nil && call_byte_at(s_short, -6) == nil, "w_fast_byte_at SSO-5")
check(call_byte_at(s_long, 2) == 104 && call_byte_at(s_long, -3) == 100 && call_byte_at(s_long, 99) == nil, "w_fast_byte_at long")
check(call_byte_at(cft, 5) == 905, "w_fast_byte_at fallback")

check(call_strip("  hi \t\n") == "hi" && call_strip(s_long) == "hello_tungsten_world" && call_strip("") == "", "w_fast_strip String")
check(call_strip(cft) == "custom_stripped", "w_fast_strip fallback")

check(call_index(s_short, "cd") == 2 && call_index(s_short, "zz") == nil, "w_fast_index String SSO-5")
check(call_index(s_long, "tungsten") == 8 && call_index(s_long, "nope") == nil, "w_fast_index String long")
check(call_index(arr, 30) == 2 && call_index(arr, 99) == nil, "w_fast_index Array")
check(call_index(cft, :hit) == 77 && call_index(cft, :miss) == nil, "w_fast_index fallback")

check(call_abs(-42) == 42 && call_abs(42) == 42 && call_abs(0) == 0, "w_fast_abs Int")
check(call_abs(-140737488355328) == 140737488355328, "w_fast_abs i48 min promotes to BigInt")
f_neg = -3.25 ## f64
f_pos = 3.25 ## f64
f_two = 2.5 ## f64
check(call_abs(f_neg) == f_pos && call_abs(f_two) == f_two, "w_fast_abs Float")
check(call_abs(-(10**25)) == 10**25, "w_fast_abs BigInt fallback")
check(call_abs(cft) == 999, "w_fast_abs custom fallback")

# ---- 5. Fixed-layout i128 / u128 / f64 / f32 WIRE constructors & direct emit ----

-> i128_ops(a, b) (i128 i128) i128
  x = a + b
  x -= 3
  x *= 2
  y = (x / 2) + (x % 7)
  z = (y & 0xFFFF) | ((a ^ b) >> 2)
  one128 = 1 ## i128
  z + (one128 << 5)

-> u128_ops(a, b) (u128 u128) u128
  q = (a / b) + (a % b)
  (q >> 1) + (q << 1)

-> float_ops(a, b) (f64 f64) f64
  acc = a + b
  acc -= (1.25 ## f64)
  acc *= (2.0 ## f64)
  acc /= (4.0 ## f64)
  acc

check(i128_ops(100 ## i128, 50 ## i128) > 0, "fixed-layout i128 ops")
check(u128_ops(1000 ## u128, 7 ## u128) == ((1000 / 7 + 1000 % 7) / 2) + ((1000 / 7 + 1000 % 7) * 2), "fixed-layout u128 ops")
check(float_ops(5.5 ## f64, 4.75 ## f64) == (4.5 ## f64), "fixed-layout f64 ops")

# ---- 6. Return-type inference soundness (yield / untyped branch / recursive SCC) ----

-> maybe_yield_or_str
  if block?
    yield 40
  else
    "none"

-> param_or_str(cond, val)
  if cond
    val
  else
    "fallback"

-> opt_str(cond)
  if cond
    "yes"

-> rec_fact(n) (i64)
  if n <= 1
    return 1
  n * rec_fact(n - 1)

-> bad_rec_mix(n, x)
  if n <= 0
    return "base"
  x

check("r=[maybe_yield_or_str() -> item + 2]|[maybe_yield_or_str()]" == "r=42|none", "return inference keeps yield branch unknown")
check("p=[param_or_str(true, 99)]|[param_or_str(false, 99)]" == "p=99|fallback", "return inference keeps untyped branch unknown")
check("o=[opt_str(false)]|[opt_str(true)]" == "o=|yes", "return inference marks missing-else if as nullable")
check(rec_fact(6) == 720, "recursive SCC return inference still proves i64")
check("b=[bad_rec_mix(1, 77)]|[bad_rec_mix(0, 77)]" == "b=77|base", "return inference does not drop untyped non-SCC branch")

if $ok
  << "PASS round4_lowering_wire_and_fast_builtins"
else
  << "FAILED " + $fail_count.to_s() + " checks"
  exit(1)
