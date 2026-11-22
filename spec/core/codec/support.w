# Shared helpers for spec/core/codec/*_spec.w: fixture loading, FNV-1a
# hashes of decoded output, and the PASS/FAIL check. The pinned hashes in the
# specs were taken from Blade's decoders before the move to core and must not
# change: every decoder here is bit-exact against its reference.

-> codec_fixture(name)
  File.read_bytes(__DIR__ + "/../../fixtures/codec/" + name)

CODEC_FAILS = [0]

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s
    CODEC_FAILS[0] += 1

-> codec_done
  if CODEC_FAILS[0] > 0
    << CODEC_FAILS[0].to_s + " failure(s)"
    exit 1

-> fnv8(a, n, h) (u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    h = ((h ^ a[i]) * 16777619) & 4294967295
    i += 1
  h

-> fnv16(a, n, h) (u16[] i64 i64) i64
  i = 0 ## i64
  while i < n
    v = a[i] ## i64
    h = ((h ^ (v & 255)) * 16777619) & 4294967295
    h = ((h ^ (v >> 8)) * 16777619) & 4294967295
    i += 1
  h

# Audio samples quantised to 2^-23 (exact for every decoder's f32 output).
-> fnvf(a, n, h) (f32[] i64 i64) i64
  i = 0 ## i64
  while i < n
    x = a[i] ## f64
    v = (x * 8388608.0).to_i ## i64
    h = ((h ^ (v & 65535)) * 16777619) & 4294967295
    h = ((h ^ ((v >> 16) & 65535)) * 16777619) & 4294967295
    i += 1
  h

FNV0 = 2166136261

-> fnv_plane(pl, h)
  return fnv16(pl, pl.size, h) if pl.class.to_s.index("16") != nil
  fnv8(pl, pl.size, h)
