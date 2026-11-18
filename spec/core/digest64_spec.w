# Digest.*64 — native wyhash digests.
#
# Regression pinned here: core/digest.w declares `-> .bytes64/.file64/
# .string64` bodyless (abstract — the implementation is lowering's
# intrinsic special-case routing to __w_digest_*). The static
# direct-dispatch registry must NOT claim bodyless declarations, or the
# empty stub inlines and every call returns nil.
#
-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

check("string64 returns a value", Digest.string64("abc") != nil)
check("string64 deterministic", Digest.string64("abc") == Digest.string64("abc"))
check("string64 discriminates", Digest.string64("abc") != Digest.string64("abd"))
check("file64 reads a real file", Digest.file64("VERSION") != nil)
check("file64 matches string64 of contents", Digest.file64("VERSION") == Digest.string64(read_file("VERSION")))
check("file64 missing file is nil", Digest.file64("spec/no/such/file.txt") == nil)
check("bytes64 matches file64", Digest.bytes64(File.read_bytes("VERSION")) == Digest.file64("VERSION"))
