# blade/h2 — HTTP/2 (RFC 9113) over TlsConn, with HPACK (RFC 7541).
#
# HPACK (decoder, and an encoder with a dynamic table), frames, and H2Session — a
# sequential one-request-at-a-time session kept for callers that want it. Blade's
# multiplexed connections (many streams in flight, a reader thread, flow-control credit,
# GOAWAY) are H2Conn in blade/netpool. The Huffman decoder and static tables are shared
# with QPACK.

# ---- Huffman (RFC 7541 Appendix B) ----

HUFF_TREE = [nil]

# A binary tree as flat arrays: node k has children l[k], r[k]; sym[k] >= 0 at leaves.
-> huff_tree
  if HUFF_TREE[0] == nil
    l = [-1]
    r = [-1]
    sym = [-1]
    s = 0
    while s < 257
      code = HUFF_CODE[s]
      len = HUFF_LEN[s]
      node = 0
      bit = len - 1
      while bit >= 0
        b = (code >> bit) & 1
        nxt = b == 0 ? l[node] : r[node]
        if nxt < 0
          l.push(-1)
          r.push(-1)
          sym.push(-1)
          nxt = l.size - 1
          if b == 0
            l[node] = nxt
          else
            r[node] = nxt
        node = nxt
        bit -= 1
      sym[node] = s
      s += 1
    HUFF_TREE[0] = [l, r, sym]
  HUFF_TREE[0]

-> huff_decode(b, off, len)
  t = huff_tree()
  l = t[0]
  r = t[1]
  sym = t[2]
  out = ByteArray.new(0)
  node = 0
  i = off
  e = off + len
  while i < e
    byte = b[i]
    bit = 7
    while bit >= 0
      node = ((byte >> bit) & 1) == 0 ? l[node] : r[node]
      raise "HPACK: bad Huffman code" if node < 0
      s = sym[node]
      if s >= 0
        raise "HPACK: EOS in string" if s == 256
        out.push(s)
        node = 0
      bit -= 1
    i += 1
  out

# HPACK/QPACK prefixed integer at b[o] with an n-bit prefix: [value, next offset].
-> hp_int(b, o, n)
  mask = (1 << n) - 1
  v = b[o] & mask
  o += 1
  return [v, o] if v < mask
  m = 0
  while true
    x = b[o]
    o += 1
    v = v + ((x & 127) << m)
    m += 7
    break if x < 128
  [v, o]

-> hp_push_int(out, first_bits, n, v)
  mask = (1 << n) - 1
  if v < mask
    out.push(first_bits | v)
    return out
  out.push(first_bits | mask)
  v = v - mask
  while v >= 128
    out.push((v & 127) + 128)
    v = v >> 7
  out.push(v)
  out

# A string literal at b[o] (H bit and a 7-bit length prefix): [string, next offset].
-> hp_string(b, o, n = 7)
  huff = (b[o] >> n) & 1
  r = hp_int(b, o, n)
  len = r[0]
  o = r[1]
  if huff == 1
    s = str_of(huff_decode(b, o, len))
  else
    s = str_of(bslice(b, o, len))
  [s, o + len]

-> hp_push_string(out, s)
  b = bytes_of(s)
  hp_push_int(out, 0, 7, b.size)
  bappend(out, b)


+ HpackDecoder
  -> new
    @dyn = []
    @size = 0
    @max = 4096

  -> entry(i)
    return HPACK_STATIC[i] if i >= 1 && i <= 61
    k = i - 62
    raise "HPACK: bad index " + i.to_s if k < 0 || k >= @dyn.size
    @dyn[k]

  -> add(name, value)
    @dyn.insert(0, [name, value])
    @size = @size + name.size + value.size + 32
    evict()

  # The peer's SETTINGS_HEADER_TABLE_SIZE below our 4096: stop using the dynamic table.
  -> limit(v)
    if v < 4096
      @max = 0
      @dyn = []
      @size = 0

  -> evict
    while @size > @max && @dyn.size > 0
      e = @dyn.pop
      @size = @size - e[0].size - e[1].size - 32

  # A header block → [[name, value], …].
  -> decode(b)
    out = []
    o = 0
    while o < b.size
      x = b[o]
      if x >= 128
        r = hp_int(b, o, 7)
        out.push(entry(r[0]))
        o = r[1]
      elsif x >= 64
        r = hp_int(b, o, 6)
        o = r[1]
        if r[0] == 0
          nr = hp_string(b, o)
          name = nr[0]
          o = nr[1]
        else
          name = entry(r[0])[0]
        vr = hp_string(b, o)
        o = vr[1]
        add(name, vr[0])
        out.push([name, vr[0]])
      elsif x >= 32
        r = hp_int(b, o, 5)
        @max = r[0]
        evict()
        o = r[1]
      else
        r = hp_int(b, o, 4)
        o = r[1]
        if r[0] == 0
          nr = hp_string(b, o)
          name = nr[0]
          o = nr[1]
        else
          name = entry(r[0])[0]
        vr = hp_string(b, o)
        o = vr[1]
        out.push([name, vr[0]])
    out

# Encode a request header list: literal without indexing, static name index where there is one.
-> hpack_encode(headers)
  out = ByteArray.new(0)
  headers.each ->(h)
    name = h[0]
    value = h[1]
    full = 0
    nidx = 0
    i = 1
    while i <= 61
      e = HPACK_STATIC[i]
      if e[0] == name
        nidx = i if nidx == 0
        if e[1] == value
          full = i
          break
      i += 1
    if full > 0
      hp_push_int(out, 128, 7, full)
    else
      hp_push_int(out, 0, 4, nidx)
      hp_push_string(out, name) if nidx == 0
      hp_push_string(out, value)
  out


# A per-connection encoder with a dynamic table: headers that repeat on every request
# (user-agent, accept-encoding, cookie, :authority …) are sent once with incremental
# indexing, then as a 1–2 byte index. Everything else is a literal without indexing.
HPACK_INDEXED_NAMES = [":authority", "user-agent", "accept", "accept-encoding", "accept-language", "cookie", "origin"]

+ HpackEncoder
  -> new(@max = 4096)
    @dyn = []
    @size = 0

  # The peer's SETTINGS_HEADER_TABLE_SIZE below our 4096: stop using the dynamic table.
  -> limit(v)
    if v < 4096
      @max = 0
      @dyn = []
      @size = 0

  -> evict
    while @size > @max && @dyn.size > 0
      e = @dyn.pop
      @size = @size - e[0].size - e[1].size - 32

  -> encode(headers)
    out = ByteArray.new(0)
    headers.each ->(h)
      name = h[0]
      value = h[1]
      full = 0
      nidx = 0
      i = 1
      while i <= 61
        e = HPACK_STATIC[i]
        if e[0] == name
          nidx = i if nidx == 0
          if e[1] == value
            full = i
            break
        i += 1
      if full == 0
        k = 0
        while k < @dyn.size
          d = @dyn[k]
          if d[0] == name && d[1] == value
            full = 62 + k
            break
          k += 1
      if full > 0
        hp_push_int(out, 128, 7, full)
      elsif @max > 0 && HPACK_INDEXED_NAMES.include?(name) && name.size + value.size + 32 <= @max / 2
        hp_push_int(out, 64, 6, nidx)
        hp_push_string(out, name) if nidx == 0
        hp_push_string(out, value)
        @dyn.insert(0, [name, value])
        @size = @size + name.size + value.size + 32
        evict()
      else
        hp_push_int(out, 0, 4, nidx)
        hp_push_string(out, name) if nidx == 0
        hp_push_string(out, value)
    out

# ---- frames ----

-> h2_frame(type, flags, stream, payload)
  f = ByteArray.new(0)
  bpush24(f, payload.size)
  f.push(type)
  f.push(flags)
  bpush32(f, stream)
  bappend(f, payload)

+ H2Response
  rw :status, :headers, :body, :protocol
  -> new(@status, @headers, @body)
    @protocol = "h2"

# An HTTP/2 connection kept open for several requests (one at a time). The HPACK
# decoder lives as long as the connection, as the protocol requires; stream ids
# go 1, 3, 5, …; a GOAWAY or an error marks the session dead so the pool drops it.
+ H2Session
  ro :conn, :dead, :requests

  -> new(@conn)
    @dec = HpackDecoder.new
    @sid = 1
    @buf = ByteArray.new(0)
    @pos = 0
    @dead = false
    @requests = 0
    win = 16 * 1024 * 1024
    out = bytes_of("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    st = ByteArray.new(0)
    # ENABLE_PUSH = 0, INITIAL_WINDOW_SIZE = 16 MiB
    bpush16(st, 2)
    bpush32(st, 0)
    bpush16(st, 4)
    bpush32(st, win)
    bappend(out, h2_frame(4, 0, 0, st))
    wu = ByteArray.new(0)
    bpush32(wu, win - 65535)
    bappend(out, h2_frame(8, 0, 0, wu))
    @conn.write(out)

  # The next whole frame: [type, flags, stream, payload]; nil when the connection ends.
  -> frame
    while @buf.size - @pos < 9 || @buf.size - @pos < 9 + bget24(@buf, @pos)
      d = @conn.read()
      return nil if d == nil
      if @pos > 0
        @buf = bslice(@buf, @pos, @buf.size - @pos)
        @pos = 0
      bappend(@buf, d)
    len = bget24(@buf, @pos)
    f = [@buf[@pos + 3], @buf[@pos + 4], bget32(@buf, @pos + 5) & 0x7fffffff, bslice(@buf, @pos + 9, len)]
    @pos = @pos + 9 + len
    f

  -> request(method, authority, path, headers, body = nil)
    raise "HTTP/2: session closed" if @dead
    sid = @sid
    @sid += 2
    @requests += 1
    hl = [[":method", method], [":scheme", "https"], [":authority", authority], [":path", path]]
    headers.each ->(h) hl.push([h[0].downcase, h[1]])
    out = ByteArray.new(0)
    flags = 4
    flags = flags | 1 if body == nil
    bappend(out, h2_frame(1, flags, sid, hpack_encode(hl)))
    if body != nil
      o = 0
      while o < body.size || o == 0
        n = body.size - o
        n = 16384 if n > 16384
        last = o + n >= body.size
        bappend(out, h2_frame(0, last ? 1 : 0, sid, bslice(body, o, n)))
        o += n
        break if n == 0
    @conn.write(out)
    hdr_block = ByteArray.new(0)
    status = 0
    resp_headers = {}
    data = ByteArray.new(0)
    done = false
    while !done
      f = frame()
      if f == nil
        @dead = true
        raise "HTTP/2: connection closed before the response ended"
      type = f[0]
      fl = f[1]
      fsid = f[2]
      payload = f[3]
      case type
      when 0
        if fsid == sid
          p = payload
          if (fl & 8) != 0
            padn = p[0]
            p = bslice(p, 1, p.size - 1 - padn)
          bappend(data, p)
          done = true if (fl & 1) != 0
      when 1, 9
        p = payload
        if type == 1
          padn = 0
          o = 0
          if (fl & 8) != 0
            padn = p[0]
            o = 1
          o += 5 if (fl & 32) != 0
          p = bslice(p, o, p.size - o - padn)
        bappend(hdr_block, p)
        if (fl & 4) != 0
          # every header block goes through the decoder (its table is shared), ours or not
          hs = @dec.decode(hdr_block)
          hdr_block = ByteArray.new(0)
          if fsid == sid
            hs.each ->(h)
              if h[0] == ":status"
                status = h[1].to_i
              else
                k = h[0]
                resp_headers[k] = resp_headers.has_key?(k) ? resp_headers[k] + (k == "set-cookie" ? "\n" : ", ") + h[1] : h[1]
            status = 0 if status >= 100 && status < 200
        done = true if fsid == sid && (fl & 1) != 0 && type == 1 && status != 0
      when 3
        raise "HTTP/2: stream reset (error " + bget32(payload, 0).to_s + ")" if fsid == sid
      when 4
        @conn.write(h2_frame(4, 1, 0, ByteArray.new(0))) if (fl & 1) == 0
      when 6
        @conn.write(h2_frame(6, 1, 0, payload)) if (fl & 1) == 0
      when 7
        @dead = true
        raise "HTTP/2: GOAWAY (error " + bget32(payload, 4).to_s + ")" if status == 0 || !done
    H2Response.new(status, resp_headers, data)

  -> close
    @dead = true
    @conn.close

# One request on a fresh connection (kept for callers that don't pool).
-> h2_request(conn, method, host, path, headers, body = nil)
  H2Session.new(conn).request(method, host, path, headers, body)
