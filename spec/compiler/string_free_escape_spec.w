# String free-insertion / escape analysis (ownership.w is_heap_producer +
# is_nonretaining_consumer, runtime w_int_to_s).
#
# Transient heap strings built in a loop are now freed at scope exit. This
# spec pins BOTH halves of that contract:
#   * values that MUST be freeable still compute correctly — a wrong free
#     shows up as corrupted content once malloc reuses the block, so every
#     loop below runs long enough to recycle addresses many times over;
#   * values that ESCAPE (returned, stored in a container/ivar/global,
#     captured by a closure, appended to a buffer) must NOT be freed.
# Storage modes matter: only mode-7 heap strings are freeable, so cases
# span inline (<=5 bytes), slab-range, and >61-byte rope results.
#
# Run: `bin/tungsten -o /tmp/sfe spec/compiler/string_free_escape_spec.w && /tmp/sfe`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

PAD = "-padding-to-push-this-string-into-heap-storage-range"

# --- freeable: transient read by whitelisted consumers only ---
-> sum_sizes(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    s = i.to_s() + PAD
    total = total + s.size()
    i = i + 1
  total
# 100000 strings: 51-byte pad + digit count (1..6) => 52..57 bytes each
check("free.sum_sizes", sum_sizes(100000), "5688890")

# Content must stay intact across the free boundary: compare each transient
# against a freshly built twin, so a premature free corrupts one of them.
-> content_stable(n)
  i = 0 ## i64
  bad = 0 ## i64
  while i < n
    a = i.to_s() + PAD
    b = i.to_s() + PAD
    if a != b
      bad = bad + 1
    i = i + 1
  bad
check("free.content_stable", content_stable(50000), "0")

# Transient as a hash LOOKUP key (w_hash_get is whitelisted as read-only).
-> lookup_loop(n)
  h = {}
  h["k7" + PAD] = 7
  h["k9" + PAD] = 9
  i = 0 ## i64
  acc = 0 ## i64
  while i < n
    probe = "k7" + PAD
    v = h[probe]
    if v != nil
      acc = acc + v
    i = i + 1
  acc
check("free.hash_lookup_key", lookup_loop(20000), "140000")

# Comparison-only consumers, plus index/count scans.
-> compare_loop(n)
  i = 0 ## i64
  hits = 0 ## i64
  while i < n
    s = i.to_s() + PAD
    if s.index("padding") != nil
      hits = hits + 1
    i = i + 1
  hits
check("free.index_scan", compare_loop(20000), "20000")

# --- inline / slab modes: w_value_free must no-op, not free garbage ---
-> tiny_loop(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    s = i.to_s()
    total = total + s.size()
    i = i + 1
  total
check("free.inline_mode_noop", tiny_loop(100), "190")

# Content that matches a program LITERAL resolves to the frozen slab, so the
# same site yields slab values here and heap values for non-literal content.
-> slab_hit_loop(n)
  i = 0 ## i64
  seen = 0 ## i64
  while i < n
    s = "prefix-" + i.to_s()
    if s == "prefix-3"
      seen = seen + 1
    i = i + 1
  seen
check("free.slab_literal_hit", slab_hit_loop(5000), "1")

# Rope results (>61 bytes) fall outside the freeable set entirely.
-> rope_loop(n)
  i = 0 ## i64
  total = 0 ## i64
  while i < n
    s = i.to_s() + PAD + PAD
    total = total + s.size()
    i = i + 1
  total
check("free.rope_sizes", rope_loop(10000), "1078890")

# --- must NOT be freed: escapes ---
-> make_str(i)
  i.to_s() + PAD
returned = make_str(42)
check("escape.returned", returned.size(), "54")
check("escape.returned_content", returned.starts_with?("42-padding"), "true")

-> collect(n)
  out = []
  i = 0 ## i64
  while i < n
    out.push(i.to_s() + PAD)
    i = i + 1
  out
arr = collect(2000)
check("escape.array_first", arr[0].size(), "53")
check("escape.array_last", arr[1999].size(), "56")
check("escape.array_content", arr[1999].starts_with?("1999-padding"), "true")

-> build_keys(n)
  h = {}
  i = 0 ## i64
  while i < n
    h[i.to_s() + PAD] = i
    i = i + 1
  h
kh = build_keys(2000)
check("escape.hash_key_survives", kh["1500" + PAD], "1500")
check("escape.hash_size", kh.size(), "2000")

+ Holder
  -> new(@label)
    self
  -> label
    @label
-> hold(i)
  Holder.new(i.to_s() + PAD)
holders = []
hi = 0 ## i64
while hi < 500
  holders.push(hold(hi))
  hi = hi + 1
check("escape.ivar_survives", holders[499].label.starts_with?("499-padding"), "true")

-> buffered(n)
  sb = StringBuffer(64)
  i = 0 ## i64
  while i < n
    sb << i.to_s()
    i = i + 1
  sb.to_s().size()
check("escape.strbuf_append", buffered(1000), "2890")

gathered = ""
gi = 0 ## i64
while gi < 500
  gathered = gathered + gi.to_s()
  gi = gi + 1
check("escape.accumulator", gathered.size(), "1390")
