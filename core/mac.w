+ MAC
  -> .parse(text)
    ccall("w_mac_parse", text)

  -> to_s
    ccall("w_to_s", self)

  -> inspect
    self.to_s

  -> byte(index)
    ccall("w_mac_byte", self, index)

  -> [](index)
    self.byte(index)

  -> bytes
    ccall("w_mac_bytes", self)

  -> multicast?
    ccall("w_mac_multicast_p", self)

  -> unicast?
    ccall("w_mac_unicast_p", self)

  -> local?
    ccall("w_mac_local_p", self)

  -> universal?
    ccall("w_mac_universal_p", self)

  -> broadcast?
    ccall("w_mac_broadcast_p", self)
