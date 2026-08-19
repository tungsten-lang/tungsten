# Bitcoin consensus primitives: headers, targets, merkle roots, transactions.
#
# Byte order is the perennial trap here, so it is stated once and obeyed
# everywhere below.
#
# A Bitcoin hash is a 32-byte string. The protocol interprets it as a
# LITTLE-endian 256-bit integer when comparing against the difficulty
# target, but block explorers print it big-endian — so the familiar
# "0000000000000000000..." leading zeros are the *tail* bytes of the actual
# hash string. Concretely, three representations coexist:
#
#   digest words   - what sha256.w returns: 8 words, big-endian, H0..H7 in
#                    the order FIPS defines. H7 holds the LAST four bytes.
#   internal bytes - the 32-byte string as it appears inside a serialized
#                    block header (prev_hash, merkle_root fields).
#   display hex    - internal bytes reversed, what you paste into an
#                    explorer and what bitcoind's JSON-RPC prints.
#
# Header integer fields (version, time, bits, nonce) serialize little-endian.
# The 32-byte hash fields serialize in internal order, i.e. reversed display.

use sha256

# ---- hex <-> bytes --------------------------------------------------------

-> btc_hex_nibble(c)
  if c >= 48 && c <= 57
    return c - 48
  if c >= 97 && c <= 102
    return c - 87
  if c >= 65 && c <= 70
    return c - 55
  -1

# Decode a hex string into a fresh i64[] of byte values.
-> btc_hex_to_bytes(hex)
  cs = hex.bytes.to_a
  n = cs.size / 2
  out = i64[n + 1]
  i = 0 ## i64
  while i < n
    hi = btc_hex_nibble(cs[i * 2])
    lo = btc_hex_nibble(cs[i * 2 + 1])
    out[i] = hi * 16 + lo
    i += 1
  out

-> btc_bytes_to_hex(bytes, n)
  digits = "0123456789abcdef"
  out = ""
  i = 0 ## i64
  while i < n
    b = bytes[i] ## i64
    out = out + digits.slice((b >> 4) & 0xF, 1)
    out = out + digits.slice(b & 0xF, 1)
    i += 1
  out

# Reverse a byte range in place — the display <-> internal conversion.
-> btc_reverse(bytes, n) (i64[] i64) i64
  i = 0 ## i64
  j = n - 1 ## i64
  while i < j
    t = bytes[i]
    bytes[i] = bytes[j]
    bytes[j] = t
    i += 1
    j -= 1
  0

# Display hex (explorer order) -> 32 internal bytes.
-> btc_hash_hex_to_internal(hex)
  b = btc_hex_to_bytes(hex)
  btc_reverse(b, 32)
  b

# ---- block header ---------------------------------------------------------

# Serialize an 80-byte block header.
#
#   version, time, bits, nonce  - integers, written little-endian
#   prev_hex, merkle_hex        - DISPLAY hex, reversed on the way in
#
# Returns i64[80] of byte values.
-> btc_header_bytes(version, prev_hex, merkle_hex, time, bits, nonce)
  h = i64[80]
  btc_put_u32_le(h, 0, version)
  prev = btc_hash_hex_to_internal(prev_hex)
  merkle = btc_hash_hex_to_internal(merkle_hex)
  i = 0 ## i64
  while i < 32
    h[4 + i] = prev[i]
    h[36 + i] = merkle[i]
    i += 1
  btc_put_u32_le(h, 68, time)
  btc_put_u32_le(h, 72, bits)
  btc_put_u32_le(h, 76, nonce)
  h

-> btc_put_u32_le(buf, off, v) (i64[] i64 i64) i64
  buf[off] = v & 0xFF
  buf[off + 1] = (v >> 8) & 0xFF
  buf[off + 2] = (v >> 16) & 0xFF
  buf[off + 3] = (v >> 24) & 0xFF
  0

# Double-SHA a serialized 80-byte header. Returns 8 digest words.
-> btc_header_hash(header, k)
  sha256d_bytes(header, 80, k)

# ---- difficulty target ----------------------------------------------------

# Decode compact "nBits" into a 256-bit target, returned as 8 big-endian
# 32-bit words (word 0 = most significant).
#
# nBits is a floating-point-ish encoding: the top byte is a base-256
# exponent, the low three bytes a mantissa, and
#
#   target = mantissa * 256**(exponent - 3)
#
# so 0x1d00ffff means 0x00ffff * 256**26, the difficulty-1 target.
# Exponents <= 3 shift the mantissa RIGHT instead of left, which the
# position arithmetic below handles by skipping negative positions.
#
# Returns nil for an nBits Bitcoin Core would reject, so a caller cannot
# mine against a target the network will never accept. Two cases, matching
# CBigNum::SetCompact's fNegative / fOverflow flags:
#
#   negative  bit 0x00800000 of the mantissa set — the encoding is signed,
#             and a negative target is meaningless
#   overflow  a nonzero mantissa shifted past the top of 256 bits
-> btc_target_from_bits(bits)
  exponent = (bits >> 24) & 0xFF
  # Mantissa is 23 bits; bit 23 is the sign.
  mantissa = bits & 0x007FFFFF
  # A zero mantissa is neither negative nor overflowing however the other
  # bits are set — hence the guard.
  if mantissa != 0
    if (bits & 0x00800000) != 0
      return nil
    if exponent > 34
      return nil
    if mantissa > 0xFF && exponent > 33
      return nil
    if mantissa > 0xFFFF && exponent > 32
      return nil
  tb = i64[32]
  i = 0 ## i64
  while i < 32
    tb[i] = 0
    i += 1
  # Place the three mantissa bytes. Counting from the least significant end
  # (position 0 = byte 31), the mantissa occupies positions
  # exponent-3, exponent-2, exponent-1.
  bi = 0 ## i64
  while bi < 3
    pos = exponent - 3 + bi
    if pos >= 0 && pos < 32
      tb[31 - pos] = (mantissa >> (bi * 8)) & 0xFF
    bi += 1
  out = i64[8]
  i = 0
  while i < 8
    out[i] = (tb[i * 4] << 24) | (tb[i * 4 + 1] << 16) | (tb[i * 4 + 2] << 8) | tb[i * 4 + 3]
    i += 1
  out

# Byte-swap a 32-bit word.
-> btc_bswap32(x) (i64) i64
  ((x & 0xFF) << 24) | ((x & 0xFF00) << 8) | ((x >> 8) & 0xFF00) | ((x >> 24) & 0xFF)

# Is this digest <= target?
#
# The digest words are big-endian, but the number is the little-endian
# reading of the digest bytes, so the most significant 32 bits of the value
# are byteswap(H7) and the least significant are byteswap(H0). Walking
# i = 0..7 over byteswap(digest[7-i]) therefore walks the value from the
# top down, which is what a magnitude comparison wants.
-> btc_meets_target(digest, target) (i64[] i64[]) i64
  i = 0 ## i64
  while i < 8
    v = btc_bswap32(digest[7 - i])
    t = target[i] ## i64
    if v < t
      return 1
    if v > t
      return 0
    i += 1
  1

# ---- merkle root ----------------------------------------------------------

# Merkle root over a list of txids given as DISPLAY hex strings (the order
# bitcoind's getblocktemplate reports them). Returns display hex.
#
# Bitcoin hashes pairs of 32-byte internal-order hashes with double-SHA and,
# when a level has an odd count, duplicates the final hash rather than
# promoting it. That duplication is the source of CVE-2012-2459; it is
# consensus behaviour, so it is reproduced faithfully.
-> btc_merkle_root(txid_hexes, k)
  n = txid_hexes.size
  if n == 0
    return "0000000000000000000000000000000000000000000000000000000000000000"
  # Level buffer: n hashes of 32 internal-order bytes, flattened.
  level = i64[n * 32 + 32]
  i = 0 ## i64
  while i < n
    ib = btc_hash_hex_to_internal(txid_hexes[i])
    j = 0 ## i64
    while j < 32
      level[i * 32 + j] = ib[j]
      j += 1
    i += 1
  count = n ## i64
  pair = i64[64]
  while count > 1
    # Duplicate the tail when the count is odd.
    if (count & 1) == 1
      j = 0
      while j < 32
        level[count * 32 + j] = level[(count - 1) * 32 + j]
        j += 1
      count += 1
    out = 0 ## i64
    p = 0 ## i64
    while p < count
      j = 0
      while j < 64
        pair[j] = level[p * 32 + j]
        j += 1
      d = sha256d_bytes(pair, 64, k)
      # Write the digest back as internal bytes.
      wi = 0 ## i64
      while wi < 8
        word = d[wi] ## i64
        level[out * 32 + wi * 4] = (word >> 24) & 0xFF
        level[out * 32 + wi * 4 + 1] = (word >> 16) & 0xFF
        level[out * 32 + wi * 4 + 2] = (word >> 8) & 0xFF
        level[out * 32 + wi * 4 + 3] = word & 0xFF
        wi += 1
      out += 1
      p += 2
    count = out
  root = i64[32]
  i = 0
  while i < 32
    root[i] = level[i]
    i += 1
  btc_reverse(root, 32)
  btc_bytes_to_hex(root, 32)

# ---- serialization helpers for transactions -------------------------------

# Bitcoin's variable-length integer.
-> btc_varint_hex(n)
  if n < 0xFD
    return btc_u8_hex(n)
  if n <= 0xFFFF
    return "fd" + btc_u16_le_hex(n)
  if n <= 0xFFFFFFFF
    return "fe" + btc_u32_le_hex(n)
  "ff" + btc_u64_le_hex(n)

-> btc_u8_hex(v)
  digits = "0123456789abcdef"
  digits.slice((v >> 4) & 0xF, 1) + digits.slice(v & 0xF, 1)

-> btc_u16_le_hex(v)
  btc_u8_hex(v & 0xFF) + btc_u8_hex((v >> 8) & 0xFF)

-> btc_u32_le_hex(v)
  btc_u16_le_hex(v & 0xFFFF) + btc_u16_le_hex((v >> 16) & 0xFFFF)

-> btc_u64_le_hex(v)
  btc_u32_le_hex(v & 0xFFFFFFFF) + btc_u32_le_hex((v >> 32) & 0xFFFFFFFF)

# Minimally-encoded signed script number, as BIP34 requires for the height.
#
# Only non-negative values are encodable here. A block height is never
# negative, and returning a silently-wrong encoding for one would put a
# malformed push in the coinbase scriptSig, so it raises instead.
-> btc_script_num_hex(n)
  if n < 0
    raise "btc_script_num_hex: negative values are not supported (got [n])"
  if n == 0
    return ""
  out = ""
  v = n ## i64
  while v > 0
    out = out + btc_u8_hex(v & 0xFF)
    v = v >> 8
  # If the top byte has its sign bit set, append a zero byte so the value
  # is not read as negative.
  last = n ## i64
  shift = 0 ## i64
  while (last >> (shift + 8)) > 0
    shift += 8
  if ((last >> shift) & 0x80) != 0
    out = out + "00"
  out

# Push a byte string (given as hex) with the correct opcode prefix.
-> btc_push_hex(data_hex)
  n = data_hex.size / 2
  if n == 0
    return "00"
  if n <= 75
    return btc_u8_hex(n) + data_hex
  if n <= 255
    return "4c" + btc_u8_hex(n) + data_hex
  "4d" + btc_u16_le_hex(n) + data_hex

# Txid of a raw transaction given as hex: double-SHA, displayed reversed.
-> btc_txid(raw_hex, k)
  b = btc_hex_to_bytes(raw_hex)
  n = raw_hex.size / 2
  sha256_hex_le(sha256d_bytes(b, n, k))
