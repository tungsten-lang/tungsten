# blade/quic — a QUIC v1 client (RFC 9000/9001) carrying HTTP/3 (RFC 9114) with QPACK (RFC 9204).
#
# Handshake: Initial (ClientHello in CRYPTO, padded to 1200) → server Initial + Handshake →
# client Finished in Handshake → 1-RTT. Requests: fetch() runs one to completion;
# start_request / stream_complete? / take_response let one thread (blade/netpool's H3Conn)
# keep many streams in flight. Request streams are split into STREAM frames that keep
# datagrams under the MTU; MAX_DATA credit is raised as data arrives; the server's
# MAX_STREAMS limit is respected.
# Packets are protected with AES-128-GCM and AES header protection; every packet
# the server sends is acknowledged promptly so its congestion window opens. Lost
# client flights are resent on a timer. Flow-control limits are advertised large
# (16 MiB) so the server never blocks on us.

-> qv_push(b, v)
  if v < 64
    b.push(v)
  elsif v < 16384
    b.push(0x40 | (v >> 8))
    b.push(v & 255)
  elsif v < 1073741824
    b.push(0x80 | (v >> 24))
    b.push((v >> 16) & 255)
    b.push((v >> 8) & 255)
    b.push(v & 255)
  else
    b.push(0xc0 | ((v >> 56) & 63))
    k = 48
    while k >= 0
      b.push((v >> k) & 255)
      k -= 8
  b

# [value, next offset]
-> qv_get(b, o)
  f = b[o]
  len = 1 << (f >> 6)
  v = f & 63
  k = 1
  while k < len
    v = (v << 8) + b[o + k]
    k += 1
  [v, o + len]

+ QKeys
  ro :key, :iv, :hp, :cs
  -> new(secret, @cs = 0x1301)
    e = ByteArray.new(0)
    klen = suite_key_len(@cs)
    @key = hkdf_label_h(@cs, secret, "quic key", e, klen)
    @iv = hkdf_label_h(@cs, secret, "quic iv", e, 12)
    hp_raw = hkdf_label_h(@cs, secret, "quic hp", e, klen)
    @hp = @cs == 0x1303 ? hp_raw : (@cs == 0x1302 ? aes256_expand(hp_raw) : aes128_expand(hp_raw))

  -> nonce(pn)
    n = bslice(@iv, 0, 12)
    i = 0
    while i < 8
      n[11 - i] = n[11 - i] ^ ((pn >> (8 * i)) & 255)
      i += 1
    n

  -> mask(sample)
    return chacha_hp_mask(@hp, sample) if @cs == 0x1303
    return aes256_block(@hp, sample) if @cs == 0x1302
    aes128_block(@hp, sample)

# Per packet-number-space state (Initial, Handshake, Application).
+ QSpace
  rw :tx, :rx, :next_pn, :largest, :recvd, :ack_due, :crypto_in, :crypto_off, :crypto_out_off, :hsbuf, :last_flight
  -> new
    @tx = nil
    @rx = nil
    @next_pn = 0
    @largest = -1
    @recvd = {}
    @ack_due = false
    @crypto_in = {}
    @crypto_off = 0
    @crypto_out_off = 0
    @hsbuf = ByteArray.new(0)
    @last_flight = nil

  # ACK frame for everything received, as ranges (largest first).
  -> ack_frame
    f = ByteArray.new(0)
    pns = @recvd.keys.sort.reverse
    return nil if pns.size == 0
    ranges = []
    hi = pns[0]
    lo = pns[0]
    k = 1
    while k < pns.size
      p = pns[k]
      if p == lo - 1
        lo = p
      else
        ranges.push([hi, lo])
        hi = p
        lo = p
      k += 1
    ranges.push([hi, lo])
    f.push(2)
    qv_push(f, ranges[0][0])
    qv_push(f, 0)
    qv_push(f, ranges.size - 1)
    qv_push(f, ranges[0][0] - ranges[0][1])
    k = 1
    while k < ranges.size
      gap = ranges[k - 1][1] - ranges[k][0] - 2
      qv_push(f, gap)
      qv_push(f, ranges[k][0] - ranges[k][1])
      k += 1
    f

+ QStream
  rw :chunks, :segs, :len, :fin_at
  -> new
    @chunks = {}
    @segs = []
    @len = 0
    @fin_at = -1

  -> add(off, d, fin)
    @fin_at = off + d.size if fin
    @chunks[off] = d if off + d.size > @len
    progress = true
    while progress
      progress = false
      @chunks.keys.each ->(o)
        c = @chunks[o]
        if o <= @len
          if o + c.size > @len
            if o == @len
              @segs.push(c)
              @len += c.size
            else
              s = bslice(c, @len - o, o + c.size - @len)
              @segs.push(s)
              @len += s.size
          @chunks.delete(o)
          progress = true

  -> data
    bjoin(@segs, @len)

  -> complete?
    @fin_at >= 0 && @len >= @fin_at

+ H3Response
  rw :status, :headers, :body, :protocol
  -> new(@status, @headers, @body)
    @protocol = "h3"


QDEBUG = [Env.get("BLADE_QUIC_DEBUG") != nil]

+ QuicConn
  # ip: the address the caller already resolved (in its partition); resolving again here would
  # be a second live query in the unpartitioned cache.
  -> new(@host, @port, ticket = nil, ip = nil)
    ip = resolve4(@host) if ip == nil
    raise "QUIC: cannot resolve " + @host if ip == nil
    @udp = Udp.new(ip, @port)
    @dcid = brand(8)
    @odcid = @dcid
    @scid = brand(8)
    @spaces = [QSpace.new, QSpace.new, QSpace.new]
    init = hkdf_extract(unhex("38762cf7f55934b34d179ae6a4c80cadccbb7f0a"), @dcid)
    e = ByteArray.new(0)
    @spaces[0].tx = QKeys.new(hkdf_label(init, "client in", e, 32))
    @spaces[0].rx = QKeys.new(hkdf_label(init, "server in", e, 32))
    @tls = Tls13.new(@host, ["h3"], transport_params(), ticket)
    @fin_sent = false
    @control_sent = false
    @next_bidi = 0
    @requests = 0
    @udp_closed = false
    @resumed_handshake = false
    @got_server_cid = false
    @streams = {}
    @pending = []
    @closed = nil
    @hs_done = false
    # flow control and stream credit for long-lived, multiplexed connections
    @rx_stream_bytes = 0
    @max_data_sent = 16 * 1024 * 1024
    @peer_max_bidi = -1

  -> tls
    @tls

  -> transport_params
    p = ByteArray.new(0)
    big = 16 * 1024 * 1024
    [[0x01, 30000], [0x04, big], [0x05, big], [0x06, big], [0x07, big], [0x08, 16], [0x09, 16]].each ->(kv)
      v = ByteArray.new(0)
      qv_push(v, kv[1])
      qv_push(p, kv[0])
      qv_push(p, v.size)
      bappend(p, v)
    qv_push(p, 0x0f)
    qv_push(p, @scid.size)
    bappend(p, @scid)
    p

  # ---- sending ----

  -> crypto_frame(sp, data)
    s = @spaces[sp]
    f = ByteArray.new(0)
    f.push(6)
    qv_push(f, s.crypto_out_off)
    qv_push(f, data.size)
    bappend(f, data)
    s.crypto_out_off = s.crypto_out_off + data.size
    f

  # Protect one packet in space sp with this payload (frames).
  -> packet(sp, payload)
    s = @spaces[sp]
    pn = s.next_pn
    s.next_pn = pn + 1
    pnlen = 4
    pl = payload
    if pl.size < 4
      pl = bcat(pl, ByteArray.new(4 - pl.size))
    h = ByteArray.new(0)
    if sp == 2
      h.push(0x40 | (pnlen - 1))
      bappend(h, @dcid)
    else
      h.push(0xc0 | ((sp == 0 ? 0 : 2) << 4) | (pnlen - 1))
      bpush32(h, 1)
      h.push(@dcid.size)
      bappend(h, @dcid)
      h.push(@scid.size)
      bappend(h, @scid)
      h.push(0) if sp == 0
      ln = pnlen + pl.size + 16
      h.push(0x40 | (ln >> 8))
      h.push(ln & 255)
    pn_off = h.size
    bpush32(h, pn & 0xffffffff)
    ct = aead_seal(s.tx.cs, s.tx.key, s.tx.nonce(pn), pl, h)
    pkt = bcat(h, ct)
    sample = bslice(pkt, pn_off + 4, 16)
    m = s.tx.mask(sample)
    pkt[0] = pkt[0] ^ (m[0] & (sp == 2 ? 0x1f : 0x0f))
    i = 0
    while i < pnlen
      pkt[pn_off + i] = pkt[pn_off + i] ^ m[1 + i]
      i += 1
    pkt

  # Send packets as one datagram; one carrying an Initial is padded to 1200 bytes.
  -> send_datagram(pkts, initial)
    d = ByteArray.new(0)
    pkts.each ->(p) bappend(d, p)
    if initial && d.size < 1200
      # pad by extending the last Initial: rebuild is simpler as a trailing PADDING packet in Initial space
      d = nil
    @udp.send(d) if d != nil
    d

  -> send_initial(frames)
    # header: flags, version, DCID, SCID, token length, 2-byte length, 4-byte PN; then the 16-byte tag
    hlen = 1 + 4 + 1 + @dcid.size + 1 + @scid.size + 1 + 2 + 4
    pad = 1200 - hlen - 16 - frames.size
    pad = 0 if pad < 0
    pl = bcat(frames, ByteArray.new(pad))
    @udp.send(packet(0, pl))

  # ---- receiving ----

  -> decode_pn(truncated, pnlen, largest)
    expected = largest + 1
    win = 1 << (pnlen * 8)
    hwin = win / 2
    mask = win - 1
    cand = (expected - (expected & mask)) | truncated
    if cand <= expected - hwin && cand < (1 << 62) - win
      return cand + win
    if cand > expected + hwin && cand >= win
      return cand - win
    cand

  # Process one datagram; returns true if anything decrypted.
  -> receive(d)
    o = 0
    any = false
    while o < d.size
      first = d[o]
      start = o
      if (first & 0x80) != 0
        return any if o + 7 > d.size
        version = bget32(d, o + 1)
        return any if version != 1
        p = o + 5
        dl = d[p]
        p = p + 1 + dl
        sl = d[p]
        scid = bslice(d, p + 1, sl)
        p = p + 1 + sl
        type = (first >> 4) & 3
        sp = type == 0 ? 0 : (type == 2 ? 1 : -1)
        if type == 0
          r = qv_get(d, p)
          p = r[1] + r[0]
        r = qv_get(d, p)
        plen = r[0]
        pn_off = r[1]
        pkt_end = pn_off + plen
        o = pkt_end
        next if sp < 0
        if sp == 0 && !@got_server_cid
          @dcid = scid
          @got_server_cid = true
        long = true
      else
        sp = 2
        pn_off = o + 1 + @scid.size
        pkt_end = d.size
        o = pkt_end
        long = false
      s = @spaces[sp]
      if s.rx == nil
        @pending.push(bslice(d, start, pkt_end - start))
        next
      next if pn_off + 20 > d.size
      sample = bslice(d, pn_off + 4, 16)
      m = s.rx.mask(sample)
      f0 = d[start] ^ (m[0] & (long ? 0x0f : 0x1f))
      pnlen = (f0 & 3) + 1
      tr = 0
      i = 0
      while i < pnlen
        tr = (tr << 8) | (d[pn_off + i] ^ m[1 + i])
        i += 1
      pn = decode_pn(tr, pnlen, s.largest)
      hdr = bslice(d, start, pn_off + pnlen - start)
      hdr[0] = f0
      i = 0
      while i < pnlen
        hdr[pn_off - start + i] = (tr >> (8 * (pnlen - 1 - i))) & 255
        i += 1
      ct = bslice(d, pn_off + pnlen, pkt_end - pn_off - pnlen)
      pt = aead_open(s.rx.cs, s.rx.key, s.rx.nonce(pn), ct, hdr)
      next if pt == nil
      any = true
      s.largest = pn if pn > s.largest
      eliciting = frames(sp, pt)
      s.recvd[pn] = true
      s.ack_due = true if eliciting
    any

  # Handle the frames of one packet; returns whether it was ack-eliciting.
  -> frames(sp, b)
    o = 0
    el = false
    while o < b.size
      t = b[o]
      if t == 0
        o += 1
        next
      if t >= 0x40
        r = qv_get(b, o)
        t = r[0]
        o = r[1]
      else
        o += 1
      if t == 1
        el = true
      elsif t == 2 || t == 3
        r = qv_get(b, o)
        r = qv_get(b, r[1])
        r = qv_get(b, r[1])
        cnt = r[0]
        r = qv_get(b, r[1])
        o = r[1]
        k = 0
        while k < cnt
          r = qv_get(b, o)
          r = qv_get(b, r[1])
          o = r[1]
          k += 1
        if t == 3
          3.times ->(z)
            o = qv_get(b, o)[1]
      elsif t == 4
        r = qv_get(b, o)
        r = qv_get(b, r[1])
        r = qv_get(b, r[1])
        o = r[1]
        el = true
      elsif t == 5
        r = qv_get(b, o)
        r = qv_get(b, r[1])
        o = r[1]
        el = true
      elsif t == 6
        r = qv_get(b, o)
        off = r[0]
        r = qv_get(b, r[1])
        len = r[0]
        o = r[1]
        crypto_in(sp, off, bslice(b, o, len))
        o += len
        el = true
      elsif t == 7
        r = qv_get(b, o)
        o = r[1] + r[0]
        el = true
      elsif t >= 8 && t <= 15
        r = qv_get(b, o)
        sid = r[0]
        o = r[1]
        off = 0
        if (t & 4) != 0
          r = qv_get(b, o)
          off = r[0]
          o = r[1]
        if (t & 2) != 0
          r = qv_get(b, o)
          len = r[0]
          o = r[1]
        else
          len = b.size - o
        st = @streams[sid]
        if st == nil
          st = QStream.new
          @streams[sid] = st
        st.add(off, bslice(b, o, len), (t & 1) != 0)
        @rx_stream_bytes += len
        o += len
        el = true
      elsif t == 0x12
        # MAX_STREAMS (bidirectional): how many request streams the server lets us open
        r = qv_get(b, o)
        @peer_max_bidi = r[0] if r[0] > @peer_max_bidi
        o = r[1]
        el = true
      elsif t == 0x10 || t == 0x13 || t == 0x14 || t == 0x16 || t == 0x17 || t == 0x19
        o = qv_get(b, o)[1]
        el = true
      elsif t == 0x11 || t == 0x15
        r = qv_get(b, o)
        o = qv_get(b, r[1])[1]
        el = true
      elsif t == 0x18
        r = qv_get(b, o)
        r = qv_get(b, r[1])
        o = r[1]
        cl = b[o]
        o = o + 1 + cl + 16
        el = true
      elsif t == 0x1a
        resp = ByteArray.new(0)
        resp.push(0x1b)
        bappend(resp, bslice(b, o, 8))
        @udp.send(packet(2, resp)) if @spaces[2].tx != nil
        o += 8
        el = true
      elsif t == 0x1b
        o += 8
        el = true
      elsif t == 0x1c || t == 0x1d
        r = qv_get(b, o)
        code = r[0]
        o = r[1]
        if t == 0x1c
          o = qv_get(b, o)[1]
        r = qv_get(b, o)
        reason = str_of(bslice(b, r[1], r[0]))
        o = r[1] + r[0]
        @closed = "QUIC: connection closed by peer (code " + code.to_s + (reason.size > 0 ? ", " + reason : "") + ")"
      elsif t == 0x1e
        @hs_done = true
        el = true
      elsif t == 0x30 || t == 0x31
        if t == 0x31
          r = qv_get(b, o)
          o = r[1] + r[0]
        else
          o = b.size
        el = true
      else
        raise "QUIC: unknown frame type " + t.to_s
    el

  -> crypto_in(sp, off, data)
    s = @spaces[sp]
    s.crypto_in[off] = data if off + data.size > s.crypto_off
    progress = true
    while progress
      progress = false
      s.crypto_in.keys.each ->(k)
        c = s.crypto_in[k]
        if k <= s.crypto_off
          if k + c.size > s.crypto_off
            fresh = bslice(c, s.crypto_off - k, k + c.size - s.crypto_off)
            bappend(s.hsbuf, fresh)
            s.crypto_off = k + c.size
          s.crypto_in.delete(k)
          progress = true
    # complete handshake messages go to TLS
    while s.hsbuf.size >= 4 && s.hsbuf.size >= 4 + bget24(s.hsbuf, 1)
      ml = 4 + bget24(s.hsbuf, 1)
      msg = bslice(s.hsbuf, 0, ml)
      s.hsbuf = bslice(s.hsbuf, ml, s.hsbuf.size - ml)
      before = @tls.state
      fin = @tls.feed(msg)
      ch2 = @tls.take_hrr_ch2()
      if ch2 != nil
        send_initial(crypto_frame(0, ch2))
        next
      if before == :wait_sh
        @spaces[1].tx = QKeys.new(@tls.c_hs, @tls.cipher)
        @spaces[1].rx = QKeys.new(@tls.s_hs, @tls.cipher)
      if fin != nil
        @client_fin = fin
        @spaces[2].tx = QKeys.new(@tls.c_ap, @tls.cipher)
        @spaces[2].rx = QKeys.new(@tls.s_ap, @tls.cipher)

  -> flush_acks
    if @spaces[0].ack_due && @spaces[0].tx != nil
      f = @spaces[0].ack_frame
      send_initial(f) if f != nil
      @spaces[0].ack_due = false
    [1, 2].each ->(sp)
      s = @spaces[sp]
      if s.ack_due && s.tx != nil
        f = s.ack_frame
        @udp.send(packet(sp, f)) if f != nil
        s.ack_due = false

  # ---- HTTP/3 ----

  -> h3_request_frames(method, path, headers)
    blk = ByteArray.new(0)
    blk.push(0)
    blk.push(0)
    qp_field(blk, ":method", method)
    qp_field(blk, ":scheme", "https")
    qp_field(blk, ":path", path)
    qp_field(blk, ":authority", @host)
    headers.each ->(h) qp_field(blk, h[0].downcase, h[1])
    f = ByteArray.new(0)
    qv_push(f, 1)
    qv_push(f, blk.size)
    bappend(f, blk)
    f

  # One QPACK field line using the static table only.
  -> qp_field(out, name, value)
    nidx = -1
    i = 0
    while i < QPACK_STATIC.size
      e = QPACK_STATIC[i]
      if e[0] == name
        if e[1] == value
          hp_push_int(out, 0xc0, 6, i)
          return out
        nidx = i if nidx < 0
      i += 1
    if nidx >= 0
      hp_push_int(out, 0x50, 4, nidx)
    else
      nb = bytes_of(name)
      hp_push_int(out, 0x20, 3, nb.size)
      bappend(out, nb)
    hp_push_string(out, value)

  -> qpack_decode(b)
    out = []
    r = hp_int(b, 0, 8)
    raise "QPACK: dynamic table references are not supported" if r[0] != 0
    r = hp_int(b, r[1], 7)
    o = r[1]
    while o < b.size
      x = b[o]
      if x >= 128
        raise "QPACK: dynamic table reference" if (x & 0x40) == 0
        r = hp_int(b, o, 6)
        out.push(QPACK_STATIC[r[0]])
        o = r[1]
      elsif x >= 64
        raise "QPACK: dynamic table reference" if (x & 0x10) == 0
        r = hp_int(b, o, 4)
        name = QPACK_STATIC[r[0]][0]
        vr = hp_string(b, r[1])
        out.push([name, vr[0]])
        o = vr[1]
      elsif x >= 32
        huff = (x >> 3) & 1
        r = hp_int(b, o, 3)
        len = r[0]
        o = r[1]
        name = huff == 1 ? str_of(huff_decode(b, o, len)) : str_of(bslice(b, o, len))
        o += len
        vr = hp_string(b, o)
        out.push([name, vr[0]])
        o = vr[1]
      else
        raise "QPACK: post-base reference"
    out

  # ---- the connection: one handshake, then any number of requests ----

  ro :resumed_handshake, :requests

  # Receive and process whatever has arrived within ms; true if anything decrypted.
  -> pump(ms)
    d = @udp.recv(ms)
    got = false
    while d != nil
      got = true if receive(d)
      d = @udp.recv(0)
    if @pending.size > 0
      again = @pending
      @pending = []
      again.each ->(p) receive(p)
    got

  # Run the handshake to 1-RTT keys and send the client Finished. Raises on failure.
  -> handshake(timeout_ms = 15000)
    return true if @fin_sent
    ch = @tls.client_hello()
    send_initial(crypto_frame(0, ch))
    t0 = clock_ms()
    last = t0
    while !@fin_sent
      raise @closed if @closed != nil
      last = clock_ms() if pump(50)
      if @client_fin != nil
        pl = bcat(@spaces[1].ack_frame, crypto_frame(1, @client_fin))
        @spaces[1].ack_due = false
        @udp.send(packet(1, pl))
        @fin_sent = true
      flush_acks()
      if !@fin_sent && clock_ms() - last > 400
        @spaces[0].crypto_out_off = 0
        send_initial(crypto_frame(0, ch))
        last = clock_ms()
      raise "QUIC: handshake timed out" if clock_ms() - t0 > timeout_ms
    @resumed_handshake = @tls.resumed
    true

  -> alive?
    @closed == nil && !@udp_closed

  -> fetch(method, path, headers, body = nil, timeout_ms = 15000)
    handshake(timeout_ms)
    st0 = start_request(method, path, headers, body)
    sid = st0[0]
    f = st0[1]
    t0 = clock_ms()
    last_rx = t0
    last_tx = t0
    while true
      raise @closed if @closed != nil
      last_rx = clock_ms() if pump(50)
      flush_acks()
      st = @streams[sid]
      break if st != nil && st.complete?
      now = clock_ms()
      if now - last_rx > 400 && now - last_tx > 400
        # probe: resend the request if nothing came back for it, else ping for acks
        if @streams[sid] == nil
          resend(f)
        else
          ping = ByteArray.new(0)
          ping.push(1)
          @udp.send(packet(2, ping))
        last_tx = now
      raise "QUIC: timed out" if now - t0 > timeout_ms
      # nothing at all for the request in 4 s: let the caller fall back to TCP
      raise "QUIC: no response" if @streams[sid] == nil && now - t0 > 4000
    data = @streams[sid].data
    @streams.delete(sid)
    parse_h3(data)

  # ---- multiplexed use (blade/netpool's H3Conn drives these from one thread) ----

  # Streams the server allows us to open in total (its initial_max_streams_bidi, raised
  # by MAX_STREAMS); nil until known.
  -> peer_max_bidi
    if @peer_max_bidi < 0 && @tls.peer_params != nil
      pp = @tls.peer_params
      o = 0
      while o < pp.size
        r = qv_get(pp, o)
        id = r[0]
        r = qv_get(pp, r[1])
        ln = r[0]
        o = r[1]
        @peer_max_bidi = qv_get(pp, o)[0] if id == 0x08 && ln > 0
        o += ln
      @peer_max_bidi = 100 if @peer_max_bidi < 0
    @peer_max_bidi

  -> can_open?
    m = peer_max_bidi
    m == nil || @next_bidi / 4 < m

  -> closed_reason
    @closed

  # Send a request on a new stream (the handshake must be done) → [sid, frames];
  # the frames are kept so a probe can resend them.
  -> start_request(method, path, headers, body = nil)
    sid = @next_bidi
    @next_bidi += 4
    @requests += 1
    first = ByteArray.new(0)
    if !@control_sent
      # control stream (2): type 0x00, empty SETTINGS
      ctl = ByteArray.new(0)
      ctl.push(0)
      ctl.push(4)
      ctl.push(0)
      first.push(0x0a)
      qv_push(first, 2)
      qv_push(first, ctl.size)
      bappend(first, ctl)
      @control_sent = true
    req = h3_request_frames(method, path, headers)
    if body != nil
      qv_push(req, 0)
      qv_push(req, body.size)
      bappend(req, body)
    # The request stream goes out in STREAM frames that keep every datagram under ~1200
    # bytes: a larger one is dropped on most paths (a long URL plus cookies easily
    # exceeds the MTU), and resending it would never get through.
    payloads = []
    off = 0
    while off < req.size || off == 0
      n = req.size - off
      n = 1100 if n > 1100
      last = off + n >= req.size
      f = payloads.size == 0 ? first : ByteArray.new(0)
      f.push(0x08 | 0x04 | 0x02 | (last ? 1 : 0))
      qv_push(f, sid)
      qv_push(f, off)
      qv_push(f, n)
      bappend(f, bslice(req, off, n))
      payloads.push(f)
      off += n
      break if n == 0
    payloads.each ->(p) @udp.send(packet(2, p))
    [sid, payloads]

  -> resend(payloads)
    payloads.each ->(p) @udp.send(packet(2, p))

  -> ping
    p = ByteArray.new(0)
    p.push(1)
    @udp.send(packet(2, p))

  -> stream_started?(sid)
    @streams[sid] != nil

  -> stream_complete?(sid)
    st = @streams[sid]
    st != nil && st.complete?

  -> take_response(sid)
    data = @streams[sid].data
    @streams.delete(sid)
    parse_h3(data)

  -> forget_stream(sid)
    @streams.delete(sid)

  # Raise the connection's data limit (MAX_DATA) before the server reaches it.
  -> credit
    return nil if @spaces[2].tx == nil
    if @rx_stream_bytes > @max_data_sent - 8 * 1024 * 1024
      @max_data_sent = @rx_stream_bytes + 16 * 1024 * 1024
      f = ByteArray.new(0)
      f.push(0x10)
      qv_push(f, @max_data_sent)
      @udp.send(packet(2, f))
    nil

  # Tickets the server sent on this connection (for resuming the next one).
  -> take_tickets
    @tls.take_tickets

  -> close
    return nil if @udp_closed
    begin
      cc = ByteArray.new(0)
      cc.push(0x1d)
      qv_push(cc, 0x100)
      qv_push(cc, 0)
      @udp.send(packet(2, bcat(@spaces[2].ack_frame, cc))) if @spaces[2].tx != nil
    rescue e
      nil
    @udp.close
    @udp_closed = true

  -> parse_h3(b)
    o = 0
    status = 0
    headers = {}
    chunks = []
    blen = 0
    while o < b.size
      r = qv_get(b, o)
      t = r[0]
      r = qv_get(b, r[1])
      len = r[0]
      o = r[1]
      if t == 1
        qpack_decode(bslice(b, o, len)).each ->(h)
          if h[0] == ":status"
            status = h[1].to_i
          else
            k = h[0]
            headers[k] = headers.has_key?(k) ? headers[k] + (k == "set-cookie" ? "\n" : ", ") + h[1] : h[1]
      elsif t == 0
        if len > 0
          chunks.push(bslice(b, o, len))
          blen += len
      o += len
    H3Response.new(status, headers, bjoin(chunks, blen))
