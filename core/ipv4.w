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

  -> with_prefix(prefix)
    ccall("w_ipv4_with_prefix", self, prefix)

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
    ccall("w_ipv4_octets", self)

  -> a
    ($value >> 36) & 0xFF

  -> b
    ($value >> 28) & 0xFF

  -> c
    ($value >> 20) & 0xFF

  -> d
    ($value >> 12) & 0xFF

  -> network
    ccall("w_ipv4_network", self)

  -> broadcast
    ccall("w_ipv4_broadcast", self)

  -> netmask
    ccall("w_ipv4_netmask", self)

  -> mask
    self.netmask

  -> include?(address)
    ccall("w_ipv4_in_cidr", address, self)

  -> contains?(address)
    self.include?(address)

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
