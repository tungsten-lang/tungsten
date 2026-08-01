# Bech32 / bech32m address decoding (BIP173, BIP350).
#
# Turns an address into the scriptPubKey a coinbase output needs, without a
# node and without any key material. This is pure decoding: it proves an
# address is well-formed and extracts the witness program the sender must
# pay to. It cannot tell you whether anyone holds the corresponding key.
#
# Every check here is a safety check. A coinbase paying to a malformed or
# mistyped script is unspendable forever, and the miner has no way to
# discover that after the fact — so a decode failure must be fatal upstream,
# never a fallback to "some default script".
#
# Layout: <hrp> "1" <data...> <6-char checksum>, where the first data
# character is the witness version and the rest is the 5-bit-packed program.

BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32_CONST = 1
BECH32M_CONST = 0x2bc830a3

-> bech32_charval(c) (i64) i64
  i = 0 ## i64
  while i < 32
    if BECH32_CHARSET.bytes[i] == c
      return i
    i += 1
  -1

# BIP173 checksum polynomial over GF(32).
-> bech32_polymod(values) (i64[]) i64
  chk = 1 ## i64
  n = values.size ## i64
  i = 0 ## i64
  while i < n
    top = chk >> 25
    chk = ((chk & 0x1ffffff) << 5) ^ values[i]
    b = 0 ## i64
    while b < 5
      if ((top >> b) & 1) != 0
        if b == 0
          chk = chk ^ 0x3b6a57b2
        elsif b == 1
          chk = chk ^ 0x26508e6d
        elsif b == 2
          chk = chk ^ 0x1ea119fa
        elsif b == 3
          chk = chk ^ 0x3d4233dd
        else
          chk = chk ^ 0x2a1462b3
      b += 1
    i += 1
  chk

# The human-readable part contributes its high bits, a separator, then its
# low bits — BIP173's hrp_expand.
-> bech32_hrp_expand(hrp)
  n = hrp.size
  out = i64[n * 2 + 1]
  bs = hrp.bytes
  i = 0 ## i64
  while i < n
    out[i] = bs[i] >> 5
    out[n + 1 + i] = bs[i] & 31
    i += 1
  out[n] = 0
  out

# Decode an address. Returns a hash with :hrp, :version, :program (byte
# array), :length, and :script (scriptPubKey hex) — or nil if ANY check
# fails. Callers must treat nil as fatal.
-> btc_address_decode(addr)
  if addr == nil || addr.size < 8 || addr.size > 90
    return nil
  # Mixed case is forbidden: it would make the checksum ambiguous.
  lower = addr.downcase
  upper = addr.upcase
  if addr != lower && addr != upper
    return nil
  a = lower
  # The separator is the LAST "1", since the hrp may contain one.
  sep = -1
  i = a.size - 1
  while i >= 0
    if a.slice(i, 1) == "1"
      sep = i
      i = -1
    else
      i -= 1
  if sep < 1 || sep + 7 > a.size
    return nil
  hrp = a.slice(0, sep)
  dpart = a.slice(sep + 1, a.size - sep - 1)
  # Decode the data characters into 5-bit values.
  dn = dpart.size
  data = i64[dn]
  dbytes = dpart.bytes
  i = 0
  while i < dn
    v = bech32_charval(dbytes[i])
    if v < 0
      return nil
    data[i] = v
    i += 1
  # Checksum over hrp_expand(hrp) ++ data.
  he = bech32_hrp_expand(hrp)
  comb = i64[he.size + dn]
  i = 0
  while i < he.size
    comb[i] = he[i]
    i += 1
  i = 0
  while i < dn
    comb[he.size + i] = data[i]
    i += 1
  chk = bech32_polymod(comb)
  encoding = 0
  if chk == BECH32_CONST
    encoding = 1
  elsif chk == BECH32M_CONST
    encoding = 2
  else
    return nil
  # Witness version is the first data value; the last 6 are the checksum.
  version = data[0]
  if version > 16
    return nil
  # BIP350: v0 must use bech32, v1+ must use bech32m. Accepting the wrong
  # pairing would let a typo'd address through.
  if version == 0 && encoding != 1
    return nil
  if version > 0 && encoding != 2
    return nil
  prog = bech32_convertbits(data, 1, dn - 6)
  if prog == nil
    return nil
  plen = prog.size
  if plen < 2 || plen > 40
    return nil
  # v0 is only defined for 20 bytes (P2WPKH) or 32 (P2WSH).
  if version == 0 && plen != 20 && plen != 32
    return nil
  opcode = 0 ## i64
  if version == 0
    opcode = 0x00
  else
    opcode = 0x50 + version
  script = btc_u8_hex(opcode) + btc_u8_hex(plen) + btc_bytes_to_hex(prog, plen)
  {hrp: hrp, version: version, program: prog, length: plen, script: script,
   encoding: encoding}

# Repack 5-bit groups [from, to) into bytes. Returns nil if the padding is
# not canonical — a non-zero remainder means the address is malformed.
-> bech32_convertbits(data, from_i, to_i)
  acc = 0 ## i64
  bits = 0 ## i64
  n = to_i - from_i ## i64
  out = i64[n + 1]
  count = 0 ## i64
  i = from_i ## i64
  while i < to_i
    acc = ((acc << 5) | data[i]) & 0xFFFFFFFF
    bits += 5
    while bits >= 8
      bits -= 8
      out[count] = (acc >> bits) & 0xFF
      count += 1
    i += 1
  # Leftover bits must be fewer than 5 and all zero.
  if bits >= 5
    return nil
  if ((acc << (8 - bits)) & 0xFF) != 0
    return nil
  res = i64[count + 1]
  i = 0
  while i < count
    res[i] = out[i]
    i += 1
  res.slice(0, count)

# The scriptPubKey for an address, or nil. This is the one callers need.
-> btc_address_to_script(addr)
  info = btc_address_decode(addr)
  if info == nil
    return nil
  info[:script]

# Which network an address belongs to: "mainnet", "testnet", "regtest", or
# nil for an unrecognized prefix. Mining a mainnet address on regtest (or
# the reverse) is a configuration error worth catching.
-> btc_address_network(addr)
  info = btc_address_decode(addr)
  if info == nil
    return nil
  h = info[:hrp]
  if h == "bc"
    return "mainnet"
  if h == "tb"
    return "testnet"
  if h == "bcrt"
    return "regtest"
  nil
