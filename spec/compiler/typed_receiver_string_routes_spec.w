# Typed-receiver direct routes for the string-allocation hot path
# (lowering/method_call.w + ops.w + infer_type in lowering.w):
#   int-typed  .to_s()      → w_to_s          (skips the IC dispatcher)
#   :string    .size()      → __w_string_byte_length_fast (raw i64, read-only)
#   :string    .[](i)       → __w_string_idx_fast (raw index, pure SSO leaf)
#   :string + :string       → w_str_concat    (skips w_add's re-coercion)
#   .to_s() results infer :string; String#size infers :i64
# Pins the fast arms AND the soundness backstops: w_to_s dispatches on the
# runtime tag, so BigInt-promoted accumulators and stale facts still format
# exactly as the IC path did. Values verified against the interpreter.
#
# Run: `bin/tungsten -o /tmp/trs spec/compiler/typed_receiver_string_routes_spec.w && /tmp/trs`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- int-typed receiver to_s ---
i = 12345 ## i64
check("tos.machine_i64", i.to_s(), "12345")
z = 0 ## i64
check("tos.zero", z.to_s(), "0")
neg = 0 - 987654321 ## i64
check("tos.negative", neg.to_s(), "-987654321")
b = 140737488355327 ## i64
check("tos.i48_max", b.to_s(), "140737488355327")
nb = 0 - 140737488355328 ## i64
check("tos.i48_min", nb.to_s(), "-140737488355328")

# Boxed :int that overflow-promotes to BigInt mid-loop: the static :int fact
# survives, the runtime tag says bigint, w_to_s must format the bigint.
acc = 140737488355327
acc = acc * 65536
check("tos.bigint_promoted", acc.to_s(), "9223372036854710272")

# --- string size (bytes) across storage modes ---
tiny = "abc"
check("size.inline", tiny.size(), "3")
lit = "a-canonical-slab-literal"
check("size.slab", lit.size(), "24")
n7 = 1234567 ## i64
heap7 = n7.to_s()
check("size.heap_runtime", heap7.size(), "7")
check("size.utf8_bytes", "héllo".size(), "6")

# --- one-argument String#[] direct route (byte-indexed) ---
idx_src = "abcde"
idx = 2 ## i64
check("index.inline.machine", idx_src[idx], "c")
check("index.inline.first", idx_src[0], "a")
check("index.inline.last", idx_src[-1], "e")
check("index.inline.too_negative", idx_src[-6] == nil, "true")
check("index.inline.past_end", idx_src[5] == nil, "true")
check("index.inline.empty", ""[0] == nil, "true")
check("index.slab", "abcdef"[5], "f")
nul_idx = 1 ## i64
check("index.inline.embedded_nul_size", "a\0b"[nul_idx].size(), "1")
check("index.inline.embedded_nul", "a\0b"[nul_idx] == "\0", "true")

# --- string + string direct concat ---
pre = "n="
joined = pre + heap7.to_s()
check("plus.lit_heap", joined, "n=1234567")
check("plus.lit_heap_size", joined.size(), "9")
check("plus.eq_literal", joined == "n=1234567", "true")
two = "abc" + "def"
check("plus.inline_inline", two, "abcdef")

# Rope path: concat past 61 bytes builds a rope; size reads its cached total
# without flattening, and a further + must accept a rope LHS.
half = "0123456789012345678901234567890123456789"
big = half + half
check("plus.rope_size", big.size(), "80")
big2 = big + "!"
check("plus.rope_lhs", big2.size(), "81")
check("plus.rope_content_tail", big2.ends_with?("9!"), "true")

# --- inference chaining: to_s → :string feeds the size/concat routes ---
chk = 0 ## i64
k = 0 ## i64
while k < 100
  s = k.to_s()
  chk = chk ^ s.size()
  k = k + 1
check("chain.loop_xor_sizes", chk, "0")
check("chain.tos_plus", (41 + 1).to_s() + "!", "42!")

# --- hash subscript direct routes (:hash receiver → w_hash_get/w_hash_set) ---
h = {}
h["alpha"] = 1
h[:beta] = 2
h[42] = 3
h["alpha"] = 10
check("hash.string_key", h["alpha"], "10")
check("hash.symbol_key", h[:beta], "2")
check("hash.int_key", h[42], "3")
check("hash.missing_nil", h["nope"] == nil, "true")
check("hash.size_after", h.size(), "3")
hk = 0 ## i64
j = 0 ## i64
hloop = {}
while j < 64
  hloop["key" + j.to_s()] = j * 3
  j = j + 1
j = 0 ## i64
while j < 64
  hk = hk + hloop["key" + j.to_s()]
  j = j + 1
check("hash.loop_sum", hk, "6048")
# runtime-built key content-equals a literal-built key
rk = "al" + "pha"
check("hash.cross_builder_key", h[rk], "10")
