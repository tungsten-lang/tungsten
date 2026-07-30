# Hash lookups must probe by CONTENT, never identity, across string storage
# modes: a >=62-byte key crosses the rope/heap boundary, and literal keys
# resolve to the frozen slab while runtime-built equals live on the heap.
# Any identity shortcut (pointer compare, slab-only hash, stale interning)
# makes an equal-content-but-differently-built probe miss. The delete/
# reinsert cycle exercises tombstone reuse at the same key content.
#
# Run: `bin/tungsten compile spec/core/hash_identity_probe_spec.w --out /tmp/hip && /tmp/hip`

-> hip_check(name, got, want)
  if got.to_s == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want
    exit 1

h = {}

# --- runtime-built 62-byte key, probed via a differently-built equal ---
long_key = ""
ki = 0 ## i64
while ki < 62
  long_key = long_key + "k"
  ki = ki + 1
hip_check("hash.long_key_size", long_key.size, "62")
h[long_key] = 4242

probe = ""
pi = 0 ## i64
while pi < 31
  probe = probe + "kk"
  pi = pi + 1
hip_check("hash.probe_key_size", probe.size, "62")
hip_check("hash.long_built_vs_built", h[probe], "4242")

# --- literal insert, runtime-built probe (and the reverse) ---
h["literal-key-0123456789-0123456789-0123456789-0123456789-01234567"] = 77
lit_probe = "literal-key-"
li = 0 ## i64
while li < 4
  lit_probe = lit_probe + "0123456789-"
  li = li + 1
lit_probe = lit_probe + "01234567"
hip_check("hash.literal_vs_built", h[lit_probe], "77")
h[probe] = 555
hip_check("hash.built_vs_built_overwrite", h[long_key], "555")

# --- delete/reinsert cycle: 120 keys, delete the even half, reinsert ---
cycle = {}
n = 120 ## i64
i = 0 ## i64
while i < n
  cycle["cycle-key-padding-padding-[i]"] = i * 3
  i = i + 1
hip_check("hash.cycle_full_size", cycle.size, "120")

i = 0
while i < n
  cycle.delete("cycle-key-padding-padding-[i]")
  i = i + 2
hip_check("hash.cycle_half_size", cycle.size, "60")

# deleted keys must miss, surviving keys must still hit
hip_check("hash.cycle_deleted_misses", cycle["cycle-key-padding-padding-0"] == nil, "true")
hip_check("hash.cycle_survivor_hits", cycle["cycle-key-padding-padding-1"], "3")

i = 0
while i < n
  cycle["cycle-key-padding-padding-[i]"] = i * 7
  i = i + 2
hip_check("hash.cycle_reinserted_size", cycle.size, "120")

bad = 0 ## i64
i = 0
while i < n
  want = i % 2 == 0 ? i * 7 : i * 3
  if cycle["cycle-key-padding-padding-[i]"] != want
    bad = bad + 1
  i = i + 1
hip_check("hash.cycle_every_lookup", bad, "0")

<< "hash identity probe: ok"
