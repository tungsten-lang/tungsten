# Forge::H2::StaticTable — HPACK static table (RFC 7541 Appendix A)
# Predefined header fields for HTTP/2 header compression

in Tungsten:Forge:H2

+ StaticTable
  ENTRIES = [
    [":authority", ""],
    [":method", "GET"],
    [":method", "POST"],
    [":path", "/"],
    [":path", "/index.html"],
    [":scheme", "http"],
    [":scheme", "https"],
    [":status", "200"],
    [":status", "204"],
    [":status", "206"],
    [":status", "304"],
    [":status", "400"],
    [":status", "404"],
    [":status", "500"],
    ["accept-charset", ""],
    ["accept-encoding", "gzip, deflate"],
    ["accept-language", ""],
    ["accept-ranges", ""],
    ["accept", ""],
    ["access-control-allow-origin", ""],
    ["age", ""],
    ["allow", ""],
    ["authorization", ""],
    ["cache-control", ""],
    ["content-disposition", ""],
    ["content-encoding", ""],
    ["content-language", ""],
    ["content-length", ""],
    ["content-location", ""],
    ["content-range", ""],
    ["content-type", ""],
    ["cookie", ""],
    ["date", ""],
    ["etag", ""],
    ["expect", ""],
    ["expires", ""],
    ["from", ""],
    ["host", ""],
    ["if-match", ""],
    ["if-modified-since", ""],
    ["if-none-match", ""],
    ["if-range", ""],
    ["if-unmodified-since", ""],
    ["last-modified", ""],
    ["link", ""],
    ["location", ""],
    ["max-forwards", ""],
    ["proxy-authenticate", ""],
    ["proxy-authorization", ""],
    ["range", ""],
    ["referer", ""],
    ["refresh", ""],
    ["retry-after", ""],
    ["server", ""],
    ["set-cookie", ""],
    ["strict-transport-security", ""],
    ["transfer-encoding", ""],
    ["user-agent", ""],
    ["vary", ""],
    ["via", ""],
    ["www-authenticate", ""]
  ]

  -> .entries
    ENTRIES

  -> .lookup(index)
    return nil if index < 1 || index > ENTRIES.size
    ENTRIES[index - 1]

  -> .find(name, value)
    name_match = nil

    ENTRIES.each_with_index -> (entry, i)
      if entry[0] == name
        if entry[1] == value
          return [i + 1, :full]
        name_match ||= i + 1

    return [name_match, :name] if name_match
    nil
