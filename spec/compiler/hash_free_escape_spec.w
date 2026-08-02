# Hash free-insertion / escape analysis (ownership.w w_hash_new producer +
# the runtime w_value_free hash branch).
#
# Hash literals are recognized heap producers, so a `{}` whose every use is
# a whitelisted read gets a :free_value at scope exit. This spec pins BOTH
# halves of that contract, mirroring string_free_escape_spec:
#   * transient hashes MUST compute correctly across the free boundary —
#     a wrong free shows up as corrupted lookups once malloc recycles the
#     block, so the loops run long enough to reuse addresses many times;
#   * hashes that ESCAPE (returned, stored in an ivar/cvar/global/array,
#     captured by a closure, merged into another live hash, threaded
#     through a rescue-expression merge) must NOT be freed.
#
# Run: `bin/tungsten -o /tmp/hfe spec/compiler/hash_free_escape_spec.w && /tmp/hfe`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- freeable: transient hash read by whitelisted consumers only ---
# `h[k]` lowers to w_hash_get (non-retaining whitelist), so these hashes
# really are freed at scope exit — 3M of them hold ~2.3MB peak RSS where
# the pinned shape holds 484MB. A method call like h.size() would pin the
# receiver escaped and never exercise the free path; don't "simplify" to it.
-> probe_loop(n)
  i = 0 ## i64
  acc = 0 ## i64
  while i < n
    h = {}
    v = h["missing"]
    if v == nil
      acc = acc + 1
    i = i + 1
  acc
check("free.empty_literal_churn", probe_loop(200000), "200000")

# --- escape: stored into an ivar from a constructor (the historical UAF:
# :ivar_set_idx gep+store fast path freed the hash the object still held) ---
+ HashHolder
  -> new
    @index = {}
    @spare = {}
  -> put(k, v)
    @index[k] = v
  -> get(k)
    @index[k]
  -> spare_count
    @spare.size()

-> ctor_churn(n)
  i = 0 ## i64
  bad = 0 ## i64
  while i < n
    holder = HashHolder.new
    holder.put("k", i)
    if holder.get("k") != i || holder.spare_count() != 0
      bad = bad + 1
    i = i + 1
  bad
check("escape.ctor_ivar_hash", ctor_churn(50000), "0")

# --- escape: returned hash stays live in the caller ---
-> build_map(seed)
  m = {}
  m["a"] = seed
  m["b"] = seed * 2
  m
-> return_churn(n)
  i = 0 ## i64
  bad = 0 ## i64
  while i < n
    m = build_map(i)
    if m["a"] != i || m["b"] != i * 2
      bad = bad + 1
    i = i + 1
  bad
check("escape.returned_hash", return_churn(50000), "0")

# --- escape: pushed into a live array ---
-> array_store(n)
  keep = []
  i = 0 ## i64
  while i < n
    h = {}
    h["i"] = i
    keep.push(h)
    i = i + 1
  ok = 0 ## i64
  j = 0 ## i64
  while j < n
    if keep[j]["i"] == j
      ok = ok + 1
    j = j + 1
  ok
check("escape.array_stored_hash", array_store(2000), "2000")

# --- escape: captured by a closure ---
-> closure_capture
  h = {}
  h["x"] = 42
  reader = -> ()
    h["x"]
  reader.call()
check("escape.closure_captured_hash", closure_capture(), "42")

# --- escape: rescue-expression merge (:phi_i64 carrier) ---
-> rescue_merge(flag)
  m = begin
    if flag
      raise "boom"
    h = {}
    h["v"] = 1
    h
  rescue
    e = {}
    e["v"] = 2
    e
  m["v"]
check("escape.rescue_merge_then", rescue_merge(false), "1")
check("escape.rescue_merge_rescue", rescue_merge(true), "2")

# --- escape: stored in a toplevel global, mutated through the reference ---
registry = {}
-> global_store(reg, n)
  i = 0 ## i64
  while i < n
    reg["last"] = i
    i = i + 1
  reg["last"]
check("escape.global_hash", global_store(registry, 1000), "999")
check("escape.global_hash_live", registry["last"], "999")

<< "hash_free_escape_spec: all checks passed"
