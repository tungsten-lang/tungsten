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

  -> to_i
    ccall("w_ipv4_to_i", self)

  -> prefix
    ccall("w_ipv4_prefix", self)

  -> cidr?
    ccall("w_ipv4_cidr_p", self)

  -> with_prefix(prefix)
    ccall("w_ipv4_with_prefix", self, prefix)

  -> octet(index)
    ccall("w_ipv4_octet", self, index)

  -> [](index)
    self.octet(index)

  -> octets
    ccall("w_ipv4_octets", self)

  -> a
    self.octet(0)

  -> b
    self.octet(1)

  -> c
    self.octet(2)

  -> d
    self.octet(3)

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
    ccall("w_ipv4_private_p", self)

  -> loopback?
    ccall("w_ipv4_loopback_p", self)

  -> link_local?
    ccall("w_ipv4_link_local_p", self)

  -> multicast?
    ccall("w_ipv4_multicast_p", self)

  -> unspecified?
    ccall("w_ipv4_unspecified_p", self)

  -> broadcast?
    ccall("w_ipv4_broadcast_p", self)

  -> reserved?
    ccall("w_ipv4_reserved_p", self)

  -> global?
    ccall("w_ipv4_global_p", self)
