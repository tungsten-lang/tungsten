# IPv6 — heap-backed 128-bit IP address with optional CIDR prefix.
+ IPv6
  -> .parse(text)
    ccall("w_ipv6_parse", text)

  -> to_s
    ccall("w_to_s", self)

  -> inspect
    self.to_s

  -> prefix
    ccall("w_ipv6_prefix", self)

  -> cidr?
    ccall("w_ipv6_cidr_p", self)

  -> with_prefix(prefix)
    ccall("w_ipv6_with_prefix", self, prefix)

  -> byte(index)
    ccall("w_ipv6_byte", self, index)

  -> [](index)
    self.byte(index)

  -> bytes
    ccall("w_ipv6_bytes", self)

  -> network
    ccall("w_ipv6_network", self)

  -> include?(address)
    ccall("w_ipv6_in_cidr", address, self)

  -> contains?(address)
    self.include?(address)

  -> unspecified?
    ccall("w_ipv6_unspecified_p", self)

  -> loopback?
    ccall("w_ipv6_loopback_p", self)

  -> multicast?
    ccall("w_ipv6_multicast_p", self)

  -> link_local?
    ccall("w_ipv6_link_local_p", self)

  -> unique_local?
    ccall("w_ipv6_unique_local_p", self)

  -> private?
    self.unique_local?

  -> global?
    ccall("w_ipv6_global_p", self)
