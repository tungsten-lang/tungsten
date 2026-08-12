# URL — strict absolute-URL parsing and canonical reconstruction.
#
# Escaped bytes stay escaped; query/form decoding is a separate concern.
# Scheme and registered-name hosts are normalized to lowercase. Relative
# references belong in a future resolver API: parse always requires a scheme.

+ URL
  ro :scheme, :username, :password, :host, :port
  ro :path, :query, :fragment

  -> new(@scheme, @username, @password, @host, @port, @path, @query, @fragment)

  -> .parse(source)
    if source == nil || source.empty?
      raise "invalid URL: expected a non-empty absolute URL"
    URL.validate_source(source)

    colon = source.index(":")
    if colon == nil || colon == 0
      raise "invalid URL: missing scheme"
    scheme = source.slice(0, colon)
    if !URL.valid_scheme?(scheme)
      raise "invalid URL scheme: " + scheme
    scheme = scheme.downcase

    cursor = colon + 1
    username = nil
    password = nil
    host = nil
    port = nil
    authority = false

    if source.slice(cursor, 2) == "//"
      authority = true
      cursor += 2
      authority_end = URL.first_delimiter(source, cursor)
      parsed_authority = URL.parse_authority(
        source.slice(cursor, authority_end - cursor), scheme)
      username = parsed_authority[0]
      password = parsed_authority[1]
      host = parsed_authority[2]
      port = parsed_authority[3]
      cursor = authority_end

    fragment_mark = source.index("#", cursor)
    query_mark = source.index("?", cursor)
    if query_mark != nil && fragment_mark != nil && query_mark > fragment_mark
      query_mark = nil

    path_end = source.size
    if query_mark != nil && query_mark < path_end
      path_end = query_mark
    if fragment_mark != nil && fragment_mark < path_end
      path_end = fragment_mark
    path = source.slice(cursor, path_end - cursor)
    if authority && path != "" && !path.starts_with?("/")
      raise "invalid URL: authority path must start with '/'"
    if !URL.valid_component?(path, ":@/")
      raise "invalid URL: malformed path"

    query = nil
    if query_mark != nil
      query_end = fragment_mark == nil ? source.size : fragment_mark
      query = source.slice(query_mark + 1, query_end - query_mark - 1)
      if !URL.valid_component?(query, ":@/?")
        raise "invalid URL: malformed query"

    fragment = nil
    if fragment_mark != nil
      fragment = source.slice(fragment_mark + 1, source.size - fragment_mark - 1)
      if fragment.index("#") != nil
        raise "invalid URL: fragment contains an unescaped '#'"
      if !URL.valid_component?(fragment, ":@/?")
        raise "invalid URL: malformed fragment"

    URL.new(scheme, username, password, host, port, path, query, fragment)

  -> .try_parse(source)
    begin
      URL.parse(source)
    rescue error
      nil

  -> .validate_source(source)
    if source.index("\\") != nil
      raise "invalid URL: backslashes are not allowed"
    i = 0
    while i < source.size
      ch = source.slice(i, 1)
      if ch == " " || ch == "\t" || ch == "\r" || ch == "\n"
        raise "invalid URL: whitespace is not allowed"
      if ch == "%"
        if i + 2 >= source.size || URL.hex_value(source.slice(i + 1, 1)) == nil || URL.hex_value(source.slice(i + 2, 1)) == nil
          raise "invalid URL: malformed percent escape"
        i += 2
      i += 1
    true

  -> .valid_scheme?(scheme)
    return false if scheme.empty?
    first = scheme.slice(0, 1)
    return false if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".index(first) == nil
    i = 1
    while i < scheme.size
      ch = scheme.slice(i, 1)
      if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.".index(ch) == nil
        return false
      i += 1
    true

  -> .first_delimiter(source, offset)
    found = source.size
    slash = source.index("/", offset)
    question = source.index("?", offset)
    hash = source.index("#", offset)
    found = slash if slash != nil && slash < found
    found = question if question != nil && question < found
    found = hash if hash != nil && hash < found
    found

  -> .parse_authority(authority, scheme)
    username = nil
    password = nil
    host_port = authority
    at = authority.rindex("@")
    if at != nil
      userinfo = authority.slice(0, at)
      if userinfo.empty? || userinfo.index("@") != nil
        raise "invalid URL: malformed userinfo"
      if !URL.valid_component?(userinfo, ":")
        raise "invalid URL: malformed userinfo"
      separator = userinfo.index(":")
      if separator == nil
        username = userinfo
      else
        username = userinfo.slice(0, separator)
        password = userinfo.slice(separator + 1, userinfo.size - separator - 1)
      host_port = authority.slice(at + 1, authority.size - at - 1)

    host = nil
    port_text = nil
    if host_port.starts_with?("\[")
      closing = host_port.index("\]")
      if closing == nil
        raise "invalid URL: unterminated IPv6 host"
      host = host_port.slice(1, closing - 1)
      remainder = host_port.slice(closing + 1, host_port.size - closing - 1)
      if remainder != ""
        if !remainder.starts_with?(":")
          raise "invalid URL: unexpected text after IPv6 host"
        port_text = remainder.slice(1, remainder.size - 1)
      if !URL.valid_ipv6_literal?(host)
        raise "invalid URL: malformed IPv6 host"
    else
      separator = host_port.rindex(":")
      if separator != nil
        host_prefix = host_port.slice(0, separator)
        if host_prefix.index(":") != nil
          raise "invalid URL: IPv6 hosts must use brackets"
        host = host_prefix
        port_text = host_port.slice(separator + 1, host_port.size - separator - 1)
      else
        host = host_port
      if !URL.valid_registered_host?(host)
        raise "invalid URL: malformed host"
      host = host.downcase

    if host.empty? && scheme != "file"
      raise "invalid URL: authority requires a host"
    if scheme == "file" && (username != nil || password != nil || port_text != nil)
      raise "invalid file URL authority"

    port = nil
    if port_text != nil
      if port_text.empty?
        raise "invalid URL: empty port"
      i = 0
      while i < port_text.size
        if "0123456789".index(port_text.slice(i, 1)) == nil
          raise "invalid URL port: " + port_text
        i += 1
      port = port_text.to_i
      if port < 0 || port > 65535
        raise "invalid URL port: " + port_text
    [username, password, host, port]

  -> .valid_registered_host?(host)
    i = 0
    while i < host.size
      ch = host.slice(i, 1)
      if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=%".index(ch) == nil
        return false
      i += 1
    true

  -> .valid_ipv6_literal?(host)
    return false if host.empty?
    compression = host.index("::")
    if compression != nil
      return false if host.index("::", compression + 2) != nil
      return false if host.index(":::") != nil
      left = host.slice(0, compression)
      right = host.slice(compression + 2, host.size - compression - 2)
      left_count = URL.ipv6_group_count(left, false)
      right_count = URL.ipv6_group_count(right, true)
      return false if left_count < 0 || right_count < 0
      return left_count + right_count < 8
    URL.ipv6_group_count(host, true) == 8

  -> .ipv6_group_count(side, allow_ipv4_tail)
    return 0 if side.empty?
    parts = side.split(":")
    count = 0
    i = 0
    while i < parts.size
      group = parts[i]
      return -1 if group.empty?
      if allow_ipv4_tail && i == parts.size - 1 && group.index(".") != nil
        return -1 if !URL.valid_ipv4_tail?(group)
        count += 2
      else
        return -1 if group.size < 1 || group.size > 4
        j = 0
        while j < group.size
          return -1 if URL.hex_value(group.slice(j, 1)) == nil
          j += 1
        count += 1
      i += 1
    count

  -> .valid_ipv4_tail?(text)
    parts = text.split(".")
    return false if parts.size != 4
    i = 0
    while i < parts.size
      part = parts[i]
      return false if part.empty? || part.size > 3
      return false if part.size > 1 && part.slice(0, 1) == "0"
      j = 0
      while j < part.size
        return false if "0123456789".index(part.slice(j, 1)) == nil
        j += 1
      return false if part.to_i > 255
      i += 1
    true

  -> .valid_component?(text, extras)
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=" + extras
    i = 0
    while i < text.size
      ch = text.slice(i, 1)
      if ch == "%"
        i += 3
      else
        return false if allowed.index(ch) == nil
        i += 1
    true

  -> .hex_value(ch)
    "0123456789abcdef".index(ch.downcase)

  -> authority?
    @host != nil

  -> userinfo
    return nil if @username == nil
    return @username if @password == nil
    @username + ":" + @password

  -> default_port
    return 80 if @scheme == "http" || @scheme == "ws"
    return 443 if @scheme == "https" || @scheme == "wss"
    return 21 if @scheme == "ftp"
    nil

  -> effective_port
    @port == nil ? default_port() : @port

  -> origin
    return nil if @host == nil
    out = @scheme + "://" + host_for_output()
    if @port != nil && @port != default_port()
      out += ":" + @port.to_s
    out

  -> request_target
    target = @path.empty? ? "/" : @path
    if @query != nil
      target += "?" + @query
    target

  -> host_for_output
    if @host != nil && @host.index(":") != nil
      return "\[" + @host + "\]"
    @host

  -> to_s
    out = @scheme + ":"
    if @host != nil
      out += "//"
      if @username != nil
        out += @username
        if @password != nil
          out += ":" + @password
        out += "@"
      out += host_for_output()
      if @port != nil
        out += ":" + @port.to_s
    out += @path
    if @query != nil
      out += "?" + @query
    if @fragment != nil
      out += "#" + @fragment
    out

  -> inspect
    "URL(\"" + to_s() + "\")"
