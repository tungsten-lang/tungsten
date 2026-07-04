+ CIDR
  -> .parse(text)
    if text.include?(":")
      return IPv6.parse(text)
    IPv4.parse(text)

  -> .v4(text)
    IPv4.parse(text)

  -> .v6(text)
    IPv6.parse(text)

  -> include?(address)
    ccall("w_ip_in_cidr", address, self)

  -> contains?(address)
    self.include?(address)
