+ UUID

  - data
    raw 16

  -> .parse(text)
    ccall("w_uuid_parse", text)

  -> .nil_uuid
    ccall("w_uuid_namespace_nil")

  -> .dns
    ccall("w_uuid_namespace_dns")

  -> .url
    ccall("w_uuid_namespace_url")

  -> .oid
    ccall("w_uuid_namespace_oid")

  -> .x500
    ccall("w_uuid_namespace_x500")

  -> .v1(options = nil)
    ccall("w_uuid_v1", options)

  -> .v2(options = nil)
    ccall("w_uuid_v2", options)

  -> .v3(namespace, name)
    ccall("w_uuid_v3", namespace, name)

  -> .v4
    ccall("w_uuid_v4")

  -> .random
    UUID.v4()

  -> .v5(namespace, name)
    ccall("w_uuid_v5", namespace, name)

  -> .v6
    ccall("w_uuid_v6")

  -> .v7
    ccall("w_uuid_v7")

  -> .v8(custom = nil)
    ccall("w_uuid_v8", custom)

  -> version
    case self.byte(6) >> 4
      1 => :v1
      2 => :v2
      3 => :v3
      4 => :v4
      5 => :v5
      6 => :v6
      7 => :v7
      8 => :v8
      => nil

  -> variant
    case self.byte(8) >> 4
    when 0..7
      :ncs
    when 8..11
      :rfc4122
    when 12..13
      :microsoft
    else
      :reserved

  -> byte(index)
    ccall("w_uuid_byte", self, index)

  -> bytes
    ccall("w_uuid_bytes", self)

  -> to_s
    ccall("w_uuid_to_s", self)
