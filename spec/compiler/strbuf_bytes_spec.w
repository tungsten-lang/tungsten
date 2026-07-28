# StringBuffer is byte-exact (runtime w_strbuf_append / w_strbuf_to_s).
#
# Both functions used to route through a C-string boundary: append recovered
# its length with strlen(as_str(...)) and to_s rebuilt via w_string(data).
# That rescanned every chunk (and the whole buffer) to recompute lengths the
# WValue and sb->size already carry, and it truncated at an embedded NUL --
# while String#+, String#<< and String#size are all byte-exact. StringBuffer
# now agrees with them.
#
# Run: `bin/tungsten -o /tmp/sbb spec/compiler/strbuf_bytes_spec.w && /tmp/sbb`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- ordinary appends across every source storage mode ---
sb = StringBuffer(8)
sb << "ab"
sb << "a-slab-range-literal-well-over-five-bytes"
sb << 12
check("strbuf.mixed_modes", sb.to_s().size(), "45")
check("strbuf.mixed_content_head", sb.to_s().starts_with?("aba-slab"), "true")
check("strbuf.mixed_content_tail", sb.to_s().ends_with?("bytes12"), "true")

# Growth past the initial capacity, many times over.
grow = StringBuffer(4)
gi = 0 ## i64
while gi < 5000
  grow << "0123456789"
  gi = gi + 1
check("strbuf.growth_size", grow.to_s().size(), "50000")

# A runtime-built (mode-7 heap) suffix, not just literals.
heapsb = StringBuffer(16)
hs = 1234567.to_s() + "-runtime-built-heap-string-suffix"
heapsb << hs
check("strbuf.heap_suffix", heapsb.to_s().size(), "40")

# --- byte exactness: embedded NUL survives append AND to_s ---
nul = "a\0b"
check("strbuf.string_size_counts_nul", nul.size(), "3")
nsb = StringBuffer(16)
nsb << nul
nsb << "|end"
check("strbuf.append_keeps_nul", nsb.to_s().size(), "7")
# String#+ and String#<< agree — StringBuffer must not be the outlier
check("strbuf.matches_string_plus", (nul + "|end").size(), "7")
empty = StringBuffer(8)
check("strbuf.empty_to_s", empty.to_s().size(), "0")
