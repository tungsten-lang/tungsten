# Typed array free-insertion / escape analysis (ownership.w w_array_zeros,
# w_array_new_inline, w_array_new_filled, w_bytes_new, w_bool_array_new +
# non-retaining typed-array ops + w_check_array_ebits escape summary +
# w_value_free view guard & w_arr_park reuse).
#
# Pins both halves of the contract:
#   * Non-escaping typed arrays in loops (direct, slot-carried, passed to
#     read-only typed-array helpers, returned from fresh helpers) are freed on
#     every iteration without leaking or corrupting data across buffer reuse.
#   * Escaping typed arrays (returned, stored in array/ivar/global, captured by
#     closure, sliced via zero-copy view, passed to raw-pointer extraction)
#     stay live and intact.

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- freeable: local u8/i64/f64 typed arrays in a loop ---
# 2000 * 100 KB = 200 MB if leaked; stays flat and reuses parked buffer when freed.
-> u8_loop_churn(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    buf = u8[100000]
    buf[0] = (i & 255)
    buf[99999] = ((i * 3) & 255)
    total = total + buf[0] + buf[99999]
    i = i + 1
  total
check("free.u8_loop_churn", u8_loop_churn(2000), "502368")

-> f64_loop_churn(n)
  i = 0 ## i64
  total = 0.0
  while i < n
    arr = f64[1024]
    arr[0] = i.to_f()
    arr[1023] = 1.5
    total = total + arr[0] + arr[1023]
    i = i + 1
  total.to_i()
check("free.f64_loop_churn", f64_loop_churn(1000), "501000")

# --- freeable: slot-carried typed array overwritten in a loop ---
-> slot_churn(n)
  buf = u8[16]
  buf[0] = 5
  total = buf[0]
  i = 0 ## i64
  while i < n
    buf = u8[4096]
    buf[0] = (i & 127)
    buf[4095] = 1
    total = total + buf[0] + buf[4095]
    i = i + 1
  total
check("free.slot_carried_u8_churn", slot_churn(2000), "127085")

# --- freeable: passed to a read-only typed-array helper (w_check_array_ebits) ---
-> sum_endpoints(b) (u8[]) i64
  b[0] + b[b.size - 1]

-> helper_call_churn(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    b = u8[8192]
    b[0] = (i & 63)
    b[8191] = 2
    total = total + sum_endpoints(b)
    i = i + 1
  total
check("free.typed_param_helper_churn", helper_call_churn(2000), "66616")

# --- freeable: returned from a fresh-heap helper ---
-> make_filled_u8(n, v)
  b = u8[n]
  b[0] = v
  b[n - 1] = v + 1
  b

-> fresh_helper_churn(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    b = make_filled_u8(4096, (i & 31))
    total = total + b[0] + b[4095]
    i = i + 1
  total
check("free.fresh_helper_churn", fresh_helper_churn(2000), "63744")

# --- freeable: float typed-array literal (w_array_new_inline) ---
-> lit_f64_churn(n)
  i = 0 ## i64
  total = 0.0
  while i < n
    v = [1.0, 2.0, 3.0, 4.0] ## f64[]
    total = total + v.sum
    i = i + 1
  total.to_i()
check("free.f64_literal_churn", lit_f64_churn(5000), "50000")

# --- escape: returned typed array stays intact across subsequent churn ---
-> make_and_keep(tag)
  out = i64[64]
  out[0] = tag
  out[63] = tag * 10
  out

-> keep_returned_test
  kept = []
  i = 0 ## i64
  while i < 200
    a = make_and_keep(i)
    # churn same size to trigger w_arr_park / malloc reuse if a were wrongly freed
    tmp = i64[64]
    tmp[0] = 999999
    tmp[63] = 888888
    kept.push(a)
    i = i + 1
  ok = 0 ## i64
  j = 0 ## i64
  while j < 200
    if kept[j][0] == j && kept[j][63] == j * 10
      ok = ok + 1
    j = j + 1
  ok
check("escape.returned_and_array_stored", keep_returned_test(), "200")

# --- escape: zero-copy view keeps parent buffer alive ---
-> view_escape_test
  views = []
  i = 0 ## i64
  while i < 200
    parent = i64[64]
    parent[10] = i + 100
    parent[11] = i + 200
    v = parent[10..11]
    views.push(v)
    # churn same size to detect premature parent free
    tmp = i64[64]
    tmp[10] = -1
    tmp[11] = -2
    i = i + 1
  ok = 0 ## i64
  j = 0 ## i64
  while j < 200
    if views[j][0] == j + 100 && views[j][1] == j + 200
      ok = ok + 1
    j = j + 1
  ok
check("escape.zero_copy_view_parent", view_escape_test(), "200")

# --- escape: stored in ivar ---
+ BufBox
  -> new(tag)
    @buf = u8[64]
    @buf[0] = tag & 255
    @buf[63] = (tag * 2) & 255
  -> check_tag(tag)
    @buf[0] == (tag & 255) && @buf[63] == ((tag * 2) & 255)

-> ivar_escape_test
  boxes = []
  i = 0 ## i64
  while i < 100
    boxes.push(BufBox.new(i))
    tmp = u8[64]
    tmp[0] = 255
    tmp[63] = 255
    i = i + 1
  ok = 0 ## i64
  j = 0 ## i64
  while j < 100
    if boxes[j].check_tag(j)
      ok = ok + 1
    j = j + 1
  ok
check("escape.ivar_stored_typed_array", ivar_escape_test(), "100")

# --- escape: captured by closure ---
-> closure_escape_test
  b = i64[32]
  b[0] = 42
  b[31] = 99
  f = -> ()
    b[0] + b[31]
  # churn same size
  tmp = i64[32]
  tmp[0] = 0
  tmp[31] = 0
  f.call()
check("escape.closure_captured_typed_array", closure_escape_test(), "141")

# --- escape: rescue-expression merge ---
-> rescue_merge_ta(flag)
  b = begin
    if flag
      raise "boom"
    x = i64[16]
    x[0] = 11
    x
  rescue
    y = i64[16]
    y[0] = 22
    y
  tmp = i64[16]
  tmp[0] = 0
  b[0]
check("escape.rescue_merge_then", rescue_merge_ta(false), "11")
check("escape.rescue_merge_rescue", rescue_merge_ta(true), "22")

<< "typed_array_auto_free_spec: all checks passed"
