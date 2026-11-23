# Focused spec for closed-world direct-tag fast builtin dispatch:
# w_fast_idx_get ([]), w_fast_idx_set ([]=), w_fast_size (size), w_fast_push (push).
# Verifies polymorphic call sites across Array, TypedArray, Hash, String, Rope,
# Range, Symbol, and user classes, including negative indices, OOB, growth, and
# frozen-container errors.

failures = 0
-> check(cond, label)
  if !cond
    << "FAIL: " + label
    failures += 1

+ CustomBox
  ro :pushed
  ro :data
  -> new(v)
    @data = v
    @pushed = []
  -> [](k)
    "box:" + k.to_s() + ":" + @data.to_s()
  -> []=(k, v)
    @data = k.to_s() + "=" + v.to_s()
    v
  -> size
    99
  -> push(v)
    @pushed.push(v)
    self
  -> to_s
    "CustomBox(" + @data.to_s() + ")"

# Polymorphic helpers force dynamic call_method_i64 sites (receiver type erased).
-> poly_get(x, k)
  x[k]

-> poly_set(x, k, v)
  x[k] = v

-> poly_size(x)
  x.size()

-> poly_push(x, v)
  x.push(v)

-> poly_to_s(x)
  x.to_s()

# 1. Dynamic [] (w_fast_idx_get)
arr = [10, 20, 30]
check(poly_get(arr, 0) == 10, "array idx 0")
check(poly_get(arr, 2) == 30, "array idx 2")
check(poly_get(arr, -1) == 30, "array idx -1")
check(poly_get(arr, -3) == 10, "array idx -3")
check(poly_get(arr, 3) == nil, "array idx OOB +")
check(poly_get(arr, -4) == nil, "array idx OOB -")

ti = i64[3]
ti[0] = 100
ti[1] = 200
ti[2] = 300
check(poly_get(ti, 1) == 200, "i64[] idx 1")
check(poly_get(ti, -1) == 300, "i64[] idx -1")
check(poly_get(ti, 9) == nil, "i64[] idx OOB")

tf = f64[2]
tf[0] = 1.5
tf[1] = 2.5
check(poly_get(tf, 0) == 1.5, "f64[] idx 0")
check(poly_get(tf, -1) == 2.5, "f64[] idx -1")

h = {"alpha" => 1, "beta" => 2, 7 => "seven"}
k_alpha = "alpha"
k_missing = "gamma"
check(poly_get(h, k_alpha) == 1, "hash string key hit")
check(poly_get(h, 7) == "seven", "hash int key hit")
check(poly_get(h, k_missing) == nil, "hash miss")

s = "hello"
check(poly_get(s, 1) == "e", "string idx fallback")
check(poly_get(s, -1) == "o", "string neg idx fallback")

box = CustomBox.new("init")
check(poly_get(box, 42) == "box:42:init", "custom class [] fallback")

# 2. Dynamic []= (w_fast_idx_set)
check(poly_set(arr, 1, 25) == 25, "array set return")
check(arr[1] == 25, "array set stored")
check(poly_set(arr, -1, 35) == 35, "array neg set return")
check(arr[2] == 35, "array neg set stored")

check(poly_set(ti, 0, 111) == 111, "i64[] set return")
check(ti[0] == 111, "i64[] set stored")

check(poly_set(h, "delta", 4) == 4, "hash insert return")
check(h["delta"] == 4, "hash insert stored")
check(poly_set(h, k_alpha, 11) == 11, "hash overwrite return")
check(h["alpha"] == 11, "hash overwrite stored")

check(poly_set(box, "k", "v") == "v", "custom class []= return")
check(box.data() == "k=v", "custom class []= stored")

# Frozen Hash []= must still raise
fh = {"a" => 1}
fh.freeze()
raised = false
begin
  poly_set(fh, "b", 2)
rescue e
  raised = true
check(raised, "frozen hash []= raises")

# 3. Dynamic .size (w_fast_size)
check(poly_size([]) == 0, "empty array size")
check(poly_size(arr) == 3, "array size")
check(poly_size(ti) == 3, "i64[] size")
check(poly_size({}) == 0, "empty hash size")
check(poly_size(h) == 4, "hash size")
check(poly_size("") == 0, "empty string size")
check(poly_size("abc") == 3, "inline string size")
check(poly_size("hello world!") == 12, "heap/slab string size")
# Multi-byte UTF-8: String#size is byte length
check(poly_size("é") == 2, "utf8 string byte size")
# Rope string (repeated concat)
rope = "abcdefgh"
i = 0
while i < 8
  rope = rope + "12345678"
  i += 1
check(poly_size(rope) == 72, "rope string size")
check(poly_size(:hello) == 5, "symbol size fallback")
check(poly_size(box) == 99, "custom class size fallback")

# 4. Dynamic .push (w_fast_push)
grown = []
j = 0
while j < 40
  ret = poly_push(grown, j * 2)
  check(ret == grown, "array push returns self") if j == 0 || j == 39
  j += 1
check(poly_size(grown) == 40, "array push growth size")
check(poly_get(grown, 39) == 78, "array push last elem")

tpush = i64[0]
j = 0
while j < 20
  poly_push(tpush, j + 10)
  j += 1
check(poly_size(tpush) == 20, "i64[] push size")
check(poly_get(tpush, 19) == 29, "i64[] push last elem")

check(poly_push(box, "x") == box, "custom class push fallback")
check(box.pushed().size() == 1 && box.pushed()[0] == "x", "custom class push stored")

# 5. Dynamic .to_s (w_fast_to_s)
check(poly_to_s("hello") == "hello", "string to_s identity")
check(poly_to_s("") == "", "empty string to_s")
check(poly_to_s(0) == "0", "zero int to_s")
check(poly_to_s(-42) == "-42", "neg int to_s")
check(poly_to_s(:sym_key) == "sym_key", "symbol to_s")
sb = StringBuffer(16)
sb << "buf" << "!"
check(poly_to_s(sb) == "buf!", "strbuf to_s")
check(poly_to_s(rope) == rope, "rope to_s")
check(poly_to_s(nil) == "", "nil to_s")
check(poly_to_s(true) == "true", "true to_s")
check(poly_to_s(false) == "false", "false to_s")
big = 10 ** 30
check(poly_to_s(big) == "1000000000000000000000000000000", "bigint to_s")
check(poly_to_s(box) == "CustomBox(k=v)", "custom class to_s fallback")

if failures > 0
  exit(1)
<< "OK"
