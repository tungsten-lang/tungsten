# studio/base — time base, canonical JSON, content hashes and the counter-based RNG.
#
# Time (TIMELINE.md §2): picture events are integer frames at a rational rate num/den, audio events integer
# samples at sr, authored offsets integer milliseconds. Conversions go through flicks (1/705,600,000 s), which are
# exact for every common frame and sample rate. One snapping rule turns an instant into a frame: round half up.

FLICKS = 705600000
HALF_FLICKS = 352800000

-> flicks_of_ms(ms)
  ms * 705600

-> samples_of_ms(ms, sr)
  ms * sr / 1000

-> flicks_of_samples(s, sr)
  s * (705600000 / sr)

# Round half up to the nearest frame: frame = floor((flicks * num + den * FLICKS / 2) / (den * FLICKS)).
-> snap_flicks(fl, num, den)
  a = fl * num + den * HALF_FLICKS
  b = den * FLICKS
  q = a / b
  q -= 1 if a % b != 0 && a < 0
  q

-> snap_ms(ms, num, den)
  snap_flicks(flicks_of_ms(ms), num, den)

# First instant of frame f, in flicks and in samples (exact: samples = f * sr * den / num).
-> flicks_of_frame(f, num, den)
  f * FLICKS * den / num

-> samples_of_frames(n, sr, num, den)
  n * sr * den / num

-> pad_int(n, w)
  s = n.to_s
  while s.size < w
    s = "0" + s
  s

# SMPTE ST 12-1 timecode of frame f (non-drop for integer rates; drop-frame for 30000/1001 and 60000/1001).
-> timecode(f, num, den)
  fps = (num + den / 2) / den
  drop = den == 1001 && (fps == 30 || fps == 60)
  n = f
  sep = ":"
  if drop
    sep = ";"
    d = fps / 15                 # frames dropped per minute: 2 at 29.97, 4 at 59.94
    per10 = fps * 600 - d * 9
    tens = n / per10
    rem = n % per10
    if rem > d
      n = n + d * 9 * tens + d * ((rem - d) / (fps * 60 - d))
    else
      n = n + d * 9 * tens
  ff = n % fps
  s = n / fps
  pad_int(s / 3600, 2) + ":" + pad_int((s / 60) % 60, 2) + ":" + pad_int(s % 60, 2) + sep + pad_int(ff, 2)

# "HH:MM:SS,mmm" (SubRip) from integer ms.
-> srt_time(ms)
  pad_int(ms / 3600000, 2) + ":" + pad_int((ms / 60000) % 60, 2) + ":" + pad_int((ms / 1000) % 60, 2) + "," + pad_int(ms % 1000, 3)

# "M:SS" or "H:MM:SS" for YouTube chapters.
-> chapter_time(sec)
  if sec >= 3600
    return (sec / 3600).to_s + ":" + pad_int((sec / 60) % 60, 2) + ":" + pad_int(sec % 60, 2)
  pad_int(sec / 60, 2) + ":" + pad_int(sec % 60, 2)

# Fixed six-decimal text of a float: the canonical form of a non-integer number in recipes.
-> fixed6(x)
  v = (x * ~1000000.0).round.to_i
  neg = v < 0
  v = 0 - v if neg
  s = (v / 1000000).to_s + "." + pad_int(v % 1000000, 6)
  s = "-" + s if neg
  s

# Canonical JSON (TIMELINE.md §3.3): sorted keys, no whitespace, integers as integers, other numbers as fixed
# 6-decimal strings. The recipe of an item is the SHA-256 of this text.
-> canon(v)
  if v == nil
    return "null"
  if v == true
    return "true"
  if v == false
    return "false"
  if v.is_a?(String)
    return JSON.encode_string(v)
  if v.is_a?(Symbol)
    return JSON.encode_string(v.to_s)
  if v.is_a?(Float)
    if v == v.round && v.abs < ~1000000000000.0
      return v.round.to_i.to_s
    return "\"" + fixed6(v) + "\""
  if v.is_a?(Integer)
    return v.to_s
  if v.is_a?(Array)
    parts = []
    v.each ->(x)
      parts.push(canon(x))
    return "\[" + parts.join(",") + "\]"
  if v.is_a?(Hash)
    ks = []
    v.keys.each ->(k)
      ks.push(k.to_s)
    ks = ks.sort
    parts = []
    ks.each ->(k)
      parts.push(JSON.encode_string(k) + ":" + canon(v[k]))
    return "{" + parts.join(",") + "}"
  if v.is_a?(Numeric)
    return canon(v.to_f)
  JSON.encode_string(v.to_s)

-> sha(text)
  Crypto.sha256(text)

-> hash_of(v)
  Crypto.sha256(canon(v))

# A 44-bit integer from a hex digest, for keying the RNG by a string id (kept under 2^47 so it never boxes
# as a BigInt).
-> hex60(h)
  n = 0
  i = 0
  while i < 11
    c = h.byte_at(i)
    d = c - 48
    d = c - 87 if c >= 97
    n = n * 16 + d
    i += 1
  n

-> id60(s)
  hex60(Crypto.sha256(s))

# ---------------------------------------------------------------------------------------------- counter RNG
# Every random number is a pure function of (episode seed, item id, item-local frame, purpose, index):
# SplitMix64 finalisers chained over the key. No generator state survives between draws, so any frame can be
# rendered by any worker in any order with identical bits (TIMELINE.md §1).

# SplitMix64 finalisers, written out inline: a typed call boxes its i64 result, and a boxed value of 2^47 or
# more is a heap BigInt, so every value that crosses a call here is folded to 47 bits first.
MASK47 = 140737488355327

-> rng_key(seed, item, frame, purpose) (i64 i64 i64 i64) i64
  x = purpose * 7919 + 1
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  x = frame ^ x
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  x = item ^ x
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  x = seed ^ x
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  (x >> 17) & 140737488355327

-> rng_bits(key, index) (i64 i64) i64
  x = index + 104729
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  x = key ^ x
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  (x >> 17) & 140737488355327

# Uniform in [0, 1) with 47 bits.
-> rng_u(key, index) (i64 i64) f64
  x = index + 104729
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  x = key ^ x
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x = x ^ ((x >> 31) & 8589934591)
  (((x >> 17) & 140737488355327) ## f64) * ~7.105427357601002e-15

# Fill buf[0..n) with standard normals (Box-Muller), the hash inlined in the loop.
-> rng_fill_normals(key, n, buf) (i64 i64 f32[]) i64
  i = 0
  while i < n
    x = i * 2 + 104729
    x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
    x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
    x = x ^ ((x >> 31) & 8589934591)
    x = key ^ x
    x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
    x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
    x = x ^ ((x >> 31) & 8589934591)
    u1 = (((x >> 17) & 140737488355327) ## f64) * ~7.105427357601002e-15
    y = i * 2 + 1 + 104729
    y = (y ^ ((y >> 30) & 17179869183)) * -4658895280553007687
    y = (y ^ ((y >> 27) & 137438953471)) * -7723592293110705685
    y = y ^ ((y >> 31) & 8589934591)
    y = key ^ y
    y = (y ^ ((y >> 30) & 17179869183)) * -4658895280553007687
    y = (y ^ ((y >> 27) & 137438953471)) * -7723592293110705685
    y = y ^ ((y >> 31) & 8589934591)
    u2 = (((y >> 17) & 140737488355327) ## f64) * ~7.105427357601002e-15
    if u1 < ~0.000000000001
      u1 = ~0.000000000001
    buf[i] = (Math.sqrt(~0.0 - ~2.0 * Math.log(u1)) * Math.cos(~6.283185307179586 * u2)) ## f32
    i += 1
  0

# Fill buf[0..n) with uniforms.
-> rng_fill_uniform(key, n, buf) (i64 i64 f64[]) i64
  i = 0
  while i < n
    x = i + 104729
    x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
    x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
    x = x ^ ((x >> 31) & 8589934591)
    x = key ^ x
    x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
    x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
    x = x ^ ((x >> 31) & 8589934591)
    buf[i] = (((x >> 17) & 140737488355327) ## f64) * ~7.105427357601002e-15
    i += 1
  0

# Standard normal (Box-Muller over two counter draws).
-> rng_n(key, index) (i64 i64) f64
  u1 = rng_u(key, index * 2)
  u2 = rng_u(key, index * 2 + 1)
  if u1 < ~1.0e-300
    u1 = ~1.0e-300
  Math.sqrt(~0.0 - ~2.0 * Math.log(u1)) * Math.cos(~6.283185307179586 * u2)

# purposes
P_JITTER = 1
P_GRAIN = 2
P_FLICKER = 3
P_PARTICLES = 4
P_RAIN = 5
P_FOG = 6
P_PAPER = 7
P_IR = 8

# ---------------------------------------------------------------------------------------------- small helpers

-> to_f(x)
  return ~0.0 if x == nil
  x.to_f

-> get(h, k, default)
  return default if h == nil
  v = h[k]
  return default if v == nil
  v

-> die(msg)
  << "studio: " + msg
  exit(2)

-> path_join(a, b)
  return b if b.starts_with?("/")
  return b if a == "" || a == nil
  return a + b if a.ends_with?("/")
  a + "/" + b

-> dir_of(p)
  i = p.size - 1
  while i >= 0 && p.byte_at(i) != 47
    i -= 1
  return "." if i < 0
  return "/" if i == 0
  p.slice(0, i)

-> base_of(p)
  i = p.size - 1
  while i >= 0 && p.byte_at(i) != 47
    i -= 1
  p.slice(i + 1, p.size - i - 1)

-> mkdir_p(d)
  OS.system("mkdir -p '" + d + "'")

-> shq(s)
  "'" + s.gsub("'", "'\\''") + "'"

# Write text atomically (tmp + rename).
-> write_text(path, text)
  tmp = path + ".tmp"
  File.write(tmp, text)
  File.rename(tmp, path)
  path
