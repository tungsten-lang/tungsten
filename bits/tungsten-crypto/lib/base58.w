# Base58Check address decoding — the legacy address format every 2013-era
# altcoin uses for P2PKH payouts.
#
# Same contract as address.w's bech32 decoder: this proves an address is
# well-formed and extracts the script the sender must pay to. Every check is
# a safety check — a coinbase paying a mistyped script is unspendable
# forever — so any failure returns nil and callers must treat nil as fatal.
#
# Layout of the decoded payload (25 bytes for the addresses we accept):
#
#   byte  0      version — the network's P2PKH prefix (0x00 Bitcoin,
#                0x6f eMark, 0x32 Mazacoin, ... — the coin registry knows)
#   bytes 1..20  HASH160 of the public key
#   bytes 21..24 checksum: first four bytes of sha256d(payload[0..20])
#
# Base58 is a big-integer encoding, so decoding is long multiplication over
# a byte buffer — no BigInt needed, the largest intermediate is 255*58+57.

B58_CHARSET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

-> b58_charval(c) (i64) i64
  i = 0 ## i64
  while i < 58
    if B58_CHARSET.bytes[i] == c
      return i
    i += 1
  -1

# Decode a Base58Check string into its 25-byte payload. Returns a hash with
# :version (the leading byte) and :hash160 (bytes 1..20 as hex), or nil if
# the string is not well-formed Base58, not 25 bytes decoded, or fails its
# checksum.
-> b58check_decode(addr, k)
  if addr == nil || addr.size < 26 || addr.size > 36
    return nil
  cs = addr.bytes.to_a
  n = addr.size
  # Big-endian accumulator: buf[0] is the most significant byte. 32 bytes is
  # seven more than any valid payload, so a genuine overflow (buf[0..6]
  # nonzero) can only mean the address is not a 25-byte-payload address.
  buf = i64[32]
  i = 0 ## i64
  while i < n
    v = b58_charval(cs[i])
    if v < 0
      return nil
    carry = v ## i64
    j = 31 ## i64
    while j >= 0
      x = buf[j] * 58 + carry
      buf[j] = x & 0xFF
      carry = x >> 8
      j -= 1
    if carry != 0
      return nil
    i += 1
  # The payload is the low 25 bytes; the 7 above them must be zero.
  i = 0
  while i < 7
    if buf[i] != 0
      return nil
    i += 1
  # Each leading '1' encodes one leading zero byte. Require the counts to
  # match so "1<addr>" and "<addr>" cannot both decode to the same payload.
  zeros = 0 ## i64
  i = 0
  while i < n && cs[i] == 49
    zeros += 1
    i += 1
  lead = 0 ## i64
  i = 7
  while i < 32 && buf[i] == 0
    lead += 1
    i += 1
  if lead >= 25
    lead = 24
  if zeros != lead
    return nil
  payload = i64[25]
  i = 0
  while i < 25
    payload[i] = buf[7 + i]
    i += 1
  # Checksum: first four bytes of sha256d over the version + hash160.
  body = i64[21]
  i = 0
  while i < 21
    body[i] = payload[i]
    i += 1
  d = sha256d_bytes(body, 21, k)
  w0 = d[0] ## i64
  if payload[21] != ((w0 >> 24) & 0xFF)
    return nil
  if payload[22] != ((w0 >> 16) & 0xFF)
    return nil
  if payload[23] != ((w0 >> 8) & 0xFF)
    return nil
  if payload[24] != (w0 & 0xFF)
    return nil
  h160 = i64[20]
  i = 0
  while i < 20
    h160[i] = payload[1 + i]
    i += 1
  {version: payload[0], hash160: btc_bytes_to_hex(h160, 20)}

# The P2PKH scriptPubKey for a Base58Check address, or nil. When
# `expected_version` is >= 0 the address must carry exactly that version
# byte — this is what stops a Bitcoin address from being mined into an eMark
# coinbase (the hash160 would be spendable on neither chain's tooling
# without heroics, and on the wrong chain by accident).
-> b58_p2pkh_script(addr, expected_version, k)
  info = b58check_decode(addr, k)
  if info == nil
    return nil
  if expected_version >= 0 && info[:version] != expected_version
    return nil
  "76a914" + info[:hash160] + "88ac"
