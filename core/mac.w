# MAC — heap-backed 48-bit link-layer address with native byte predicates.
+ MAC
  # MAC and IPv6 share the exact WNetAddr storage layout. The leading runtime
  # type discriminator is implicit for both generic-bucket classes.
  - data (WNetAddr)
      u8     len
      u8     prefix
      u8     _pad
      u8[16] bytes
      u8[12] _pad2

  -> .parse(text)
    ccall("w_mac_parse", text)

  -> to_s
    ccall("w_to_s", self)

  -> inspect
    self.to_s

  -> byte(index)
    raw_index = ccall_nobox("w_numeric_to_i64", index) ## i64
    if raw_index < 0 || raw_index > 5
      return nil
    return $bytes[raw_index]

  -> [](index)
    self.byte(index)

  -> bytes
    out = []
    i = 0
    while i < 6
      out.push($bytes[i])
      i += 1
    out

  -> multicast?
    ($bytes[0] & 0x01) != 0

  -> unicast?
    ($bytes[0] & 0x01) == 0

  -> local?
    ($bytes[0] & 0x02) != 0

  -> universal?
    ($bytes[0] & 0x02) == 0

  -> broadcast?
    i = 0
    while i < 6
      if $bytes[i] != 0xFF
        return false
      i += 1
    true
