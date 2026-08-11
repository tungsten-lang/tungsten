# Compact function symbols must extend a shared prefix instead of aliasing two
# distinct full content hashes. Run interpreted and compiled: the regression
# originally reproduced only in compiled Hash lookup during a large program.

use ../lib/content_hash

groups = {
  "b5474ff6aaaaaaaa": ["left"],
  "b5474ff6bbbbbbbb": ["right"]
}
symbols = build_hash_symbols(groups, 8)
left = hash_symbol_get(symbols, "b5474ff6aaaaaaaa")
right = hash_symbol_get(symbols, "b5474ff6bbbbbbbb")

if left == nil || right == nil
  raise "compact symbol missing"
if left == right
  raise "compact symbol prefix collision"

# The compaction rename map contains many symbols where one name prefixes
# another. A miss for the longer key must not return the shorter key's value.
rename_map = {"__w_Tensor_S_zeros": "__wy_b5474ff6"}
if "__w_Tensor_S_zeros" == "__w_Tensor_S_zeros_unit"
  raise "string-prefix equality false match"
if rename_map["__w_Tensor_S_zeros_unit"] != nil
  raise "hash string-prefix false match"

# A compiled compiler takes hashing.w's native fast path. Pin it against the
# portable implementation at every wyhash size boundary so stage 0 and later
# stages cannot silently assign different content addresses.
if runtime_identity() == "compiled-runtime"
  hash_inputs = [
    "", "a", "abc", "abcd", "abcdefghijklmno", "abcdefghijklmnop",
    "abcdefghijklmnopq",
    "012345678901234567890123456789012345678901234567",
    "0123456789012345678901234567890123456789012345678"
  ]
  i = 0
  while i < hash_inputs.size()
    portable = wyhash64_string(hash_inputs[i])
    native = digest_string64(hash_inputs[i])
    if portable != native
      raise "native wyhash mismatch at input " + i.to_s()
    i += 1

<< "content-hash-symbol-collision: ok"
