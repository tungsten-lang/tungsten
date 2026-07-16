# IPv4 — packed IPv4 address with optional CIDR prefix.
+ IPv4
  -> .parse(text)
    ccall("w_ipv4_parse", text)

  -> .of(a, b, c, d, prefix = nil)
    ccall("w_ipv4_from_octets", a, b, c, d, prefix)

  -> .cidr(address, prefix)
    IPv4.parse(address).with_prefix(prefix)

  -> to_s
    ccall("w_to_s", self)

  -> inspect
    self.to_s

  # IPv4 is a packed WValue: the address occupies bits 43..12 and the
  # optional CIDR prefix occupies bits 11..6. `$value` exposes those raw bits
  # to compiled Tungsten, so these accessors lower to the same shifts and
  # masks as their former C implementations.
  -> to_i
    ($value >> 12) & 0xFFFFFFFF

  -> prefix
    p = (($value >> 6) & 0x3F) ## i64
    if p <= 32
      return p
    nil

  -> cidr?
    (($value >> 6) & 0x3F) <= 32

  -> with_prefix(prefix = nil)
    p = 63 ## i64
    if prefix != nil
      p = ccall_nobox("w_numeric_to_i64", prefix) ## i64
      if p < 0
        p = 63
      elsif p > 32 && p != 63
        raise "IPv4 prefix must be between 0 and 32"
    # Keep the packed IPv4 tag and address, but reset the six flag bits just
    # like the old C constructor. The low 12 bits are prefix + flags.
    wvalue_from_bits(($value & -4096) | (p << 6))

  -> octet(index)
    raw_index = ccall_nobox("w_numeric_to_i64", index) ## i64
    if raw_index < 0 || raw_index > 3
      return nil
    address = (($value >> 12) & 0xFFFFFFFF) ## i64
    (address >> ((3 - raw_index) * 8)) & 0xFF

  -> [](index)
    raw_index = ccall_nobox("w_numeric_to_i64", index) ## i64
    if raw_index < 0 || raw_index > 3
      return nil
    address = (($value >> 12) & 0xFFFFFFFF) ## i64
    (address >> ((3 - raw_index) * 8)) & 0xFF

  -> octets
    bits = $value ## i64
    [(bits >> 36) & 0xFF,
     (bits >> 28) & 0xFF,
     (bits >> 20) & 0xFF,
     (bits >> 12) & 0xFF]

  -> a
    ($value >> 36) & 0xFF

  -> b
    ($value >> 28) & 0xFF

  -> c
    ($value >> 20) & 0xFF

  -> d
    ($value >> 12) & 0xFF

  -> network
    p = (($value >> 6) & 0x3F) ## i64
    effective = 32 ## i64
    if p <= 32
      effective = p
    mask = 0 ## i64
    if effective >= 32
      mask = 0xFFFFFFFF
    elsif effective > 0
      mask = (0xFFFFFFFF << (32 - effective)) & 0xFFFFFFFF
    address = (($value >> 12) & 0xFFFFFFFF) ## i64
    tag = ($value & -35184372088832) ## i64
    wvalue_from_bits(tag | ((address & mask) << 12) | (p << 6))

  -> broadcast
    p = (($value >> 6) & 0x3F) ## i64
    effective = 32 ## i64
    if p <= 32
      effective = p
    mask = 0 ## i64
    if effective >= 32
      mask = 0xFFFFFFFF
    elsif effective > 0
      mask = (0xFFFFFFFF << (32 - effective)) & 0xFFFFFFFF
    address = (($value >> 12) & 0xFFFFFFFF) ## i64
    broadcast_address = (address | (mask ^ 0xFFFFFFFF)) ## i64
    tag = ($value & -35184372088832) ## i64
    wvalue_from_bits(tag | (broadcast_address << 12) | (p << 6))

  -> netmask
    p = (($value >> 6) & 0x3F) ## i64
    effective = 32 ## i64
    if p <= 32
      effective = p
    mask = 0 ## i64
    if effective >= 32
      mask = 0xFFFFFFFF
    elsif effective > 0
      mask = (0xFFFFFFFF << (32 - effective)) & 0xFFFFFFFF
    tag = ($value & -35184372088832) ## i64
    # Netmasks are plain IPv4 values, represented by the no-prefix sentinel.
    wvalue_from_bits(tag | (mask << 12) | (63 << 6))

  -> mask
    self.netmask

  -> include?(address)
    candidate = wvalue_bits(address)
    # Comparing tag+packed-subtype rejects non-IPv4 values without a runtime
    # type lookup. `$value` is necessarily IPv4 inside this method.
    if (candidate >> 45) != ($value >> 45)
      return false
    p = (($value >> 6) & 0x3F) ## i64
    effective = 32 ## i64
    if p <= 32
      effective = p
    mask = 0 ## i64
    if effective >= 32
      mask = 0xFFFFFFFF
    elsif effective > 0
      mask = (0xFFFFFFFF << (32 - effective)) & 0xFFFFFFFF
    cidr_address = (($value >> 12) & 0xFFFFFFFF) ## i64
    candidate_address = ((candidate >> 12) & 0xFFFFFFFF) ## i64
    (candidate_address & mask) == (cidr_address & mask)

  -> contains?(address)
    candidate = wvalue_bits(address)
    if (candidate >> 45) != ($value >> 45)
      return false
    p = (($value >> 6) & 0x3F) ## i64
    effective = 32 ## i64
    if p <= 32
      effective = p
    mask = 0 ## i64
    if effective >= 32
      mask = 0xFFFFFFFF
    elsif effective > 0
      mask = (0xFFFFFFFF << (32 - effective)) & 0xFFFFFFFF
    cidr_address = (($value >> 12) & 0xFFFFFFFF) ## i64
    candidate_address = ((candidate >> 12) & 0xFFFFFFFF) ## i64
    (candidate_address & mask) == (cidr_address & mask)

  -> private?
    address = (($value >> 12) & 0xFFFFFFFF) ## i64
    private_10 = (address & 0xFF000000) == 0x0A000000
    private_172 = (address & 0xFFF00000) == 0xAC100000
    private_192 = (address & 0xFFFF0000) == 0xC0A80000
    private_10 || private_172 || private_192

  -> loopback?
    ((($value >> 12) & 0xFFFFFFFF) & 0xFF000000) == 0x7F000000

  -> link_local?
    ((($value >> 12) & 0xFFFFFFFF) & 0xFFFF0000) == 0xA9FE0000

  -> multicast?
    ((($value >> 12) & 0xFFFFFFFF) & 0xF0000000) == 0xE0000000

  -> unspecified?
    (($value >> 12) & 0xFFFFFFFF) == 0

  -> broadcast?
    (($value >> 12) & 0xFFFFFFFF) == 0xFFFFFFFF

  -> reserved?
    ((($value >> 12) & 0xFFFFFFFF) & 0xF0000000) == 0xF0000000

  -> global?
    address = (($value >> 12) & 0xFFFFFFFF) ## i64
    private_10 = (address & 0xFF000000) == 0x0A000000
    private_172 = (address & 0xFFF00000) == 0xAC100000
    private_192 = (address & 0xFFFF0000) == 0xC0A80000
    private_address = private_10 || private_172 || private_192
    loopback_address = (address & 0xFF000000) == 0x7F000000
    link_local_address = (address & 0xFFFF0000) == 0xA9FE0000
    multicast_address = (address & 0xF0000000) == 0xE0000000
    unspecified_address = address == 0
    broadcast_address = address == 0xFFFFFFFF
    reserved_address = (address & 0xF0000000) == 0xF0000000
    special_address = private_address || loopback_address || link_local_address || multicast_address || unspecified_address || broadcast_address || reserved_address
    !special_address
