# blade/tls — a TLS 1.3 client (RFC 8446).
#
# Tls13 is the handshake engine alone: it builds the ClientHello and consumes
# handshake messages, producing the traffic secrets. It knows nothing about the
# transport, so TlsConn (TLS records over TCP, for HTTP/1.1 and HTTP/2) and QUIC
# (CRYPTO frames, for HTTP/3) share it.
#
# Offered: TLS_AES_128_GCM_SHA256, X25519, and ECDSA/RSA-PSS/RSA-PKCS1
# signatures. The server's chain and CertificateVerify are checked by
# blade/x509.

TLS_EMPTY_HASH = [nil]

-> empty_hash
  TLS_EMPTY_HASH[0] = sha256(ByteArray.new(0)) if TLS_EMPTY_HASH[0] == nil
  TLS_EMPTY_HASH[0]

-> hs_msg(type, body)
  m = ByteArray.new(0)
  m.push(type)
  bpush24(m, body.size)
  bappend(m, body)

-> push_vec8(b, v)
  b.push(v.size)
  bappend(b, v)

-> push_vec16(b, v)
  bpush16(b, v.size)
  bappend(b, v)

-> push_ext(b, type, body)
  bpush16(b, type)
  bpush16(b, body.size)
  bappend(b, body)

-> tls12_prf(use384, secret, label, seed, len)
  ls = bcat(bytes_of(label), seed)
  a = ls
  out = ByteArray.new(0)
  while out.size < len
    a = use384 ? hmac384(secret, a) : hmac256(secret, a)
    blk = use384 ? hmac384(secret, bcat(a, ls)) : hmac256(secret, bcat(a, ls))
    bappend(out, blk)
  bslice(out, 0, len)

-> u64_be(n)
  b = ByteArray.new(8)
  i = 0
  while i < 8
    b[7 - i] = (n >> (8 * i)) & 255
    i += 1
  b

-> tls12_gcm_aad(seq, type, pt_len)
  a = u64_be(seq)
  a.push(type)
  bpush16(a, 0x0303)
  bpush16(a, pt_len)
  a

+ Tls13
  ro :state, :alpn, :peer_params, :certs, :c_hs, :s_hs, :c_ap, :s_ap, :cipher, :verified, :group, :resumed, :new_tickets
  ro :tls12, :t12_c_key, :t12_s_key, :t12_c_iv, :t12_s_iv, :t12_cke

  # ticket: a TlsTicket from an earlier connection to offer for resumption (PSK with (EC)DHE), or nil.
  -> new(@host, @alpn_offer, @quic_params = nil, @ticket = nil)
    @priv = brand(32)
    @pub = x25519_base_fast(@priv)
    @transcript = ByteArray.new(0)
    @state = :start
    @alpn = nil
    @peer_params = nil
    @certs = []
    @c_hs = nil
    @s_hs = nil
    @c_ap = nil
    @s_ap = nil
    @hs_secret = nil
    @cipher = 0
    @verified = false
    @verify = true
    @group = 0
    @resumed = false
    @master = nil
    @res_master = nil
    @new_tickets = []
    @tls12 = false
    @client_random = nil
    @server_random = nil
    @ems = false
    @t12_pms = nil
    @t12_client_pub = nil
    @t12_c_key = nil
    @t12_s_key = nil
    @t12_c_iv = nil
    @t12_s_iv = nil
    @t12_cke = nil

  -> verify=(v)
    @verify = v

  -> client_hello
    body = ByteArray.new(0)
    bpush16(body, 0x0303)
    @client_random = brand(32)
    bappend(body, @client_random)
    if @quic_params == nil
      push_vec8(body, brand(32))
    else
      body.push(0)
    suites = ByteArray.new(0)
    bpush16(suites, 0x1301)
    if @quic_params == nil
      bpush16(suites, 0xc02b)
      bpush16(suites, 0xc02f)
      bpush16(suites, 0xc02c)
      bpush16(suites, 0xc030)
    push_vec16(body, suites)
    body.push(1)
    body.push(0)
    ext = ByteArray.new(0)
    # server_name
    sn = ByteArray.new(0)
    hb = bytes_of(@host)
    entry = ByteArray.new(0)
    entry.push(0)
    push_vec16(entry, hb)
    push_vec16(sn, entry)
    push_ext(ext, 0, sn)
    # supported_groups: x25519 (+ secp256r1 for TLS 1.2)
    g = ByteArray.new(0)
    if @quic_params == nil
      bpush16(g, 4)
      bpush16(g, 0x001d)
      bpush16(g, 0x0017)
    else
      bpush16(g, 2)
      bpush16(g, 0x001d)
    push_ext(ext, 10, g)
    if @quic_params == nil
      # ec_point_formats: uncompressed
      epf = ByteArray.new(0)
      epf.push(1)
      epf.push(0)
      push_ext(ext, 11, epf)
      # extended_master_secret (RFC 7627)
      push_ext(ext, 23, ByteArray.new(0))
    # signature_algorithms
    sa = ByteArray.new(0)
    algs = [0x0403, 0x0804, 0x0401, 0x0503, 0x0805, 0x0501, 0x0806, 0x0601]
    bpush16(sa, algs.size * 2)
    algs.each ->(a) bpush16(sa, a)
    push_ext(ext, 13, sa)
    # ALPN
    if @alpn_offer != nil && @alpn_offer.size > 0
      al = ByteArray.new(0)
      @alpn_offer.each ->(p) push_vec8(al, bytes_of(p))
      a2 = ByteArray.new(0)
      push_vec16(a2, al)
      push_ext(ext, 16, a2)
    # supported_versions: TLS 1.3 (+ TLS 1.2 over TCP)
    sv = ByteArray.new(0)
    if @quic_params == nil
      sv.push(4)
      bpush16(sv, 0x0304)
      bpush16(sv, 0x0303)
    else
      sv.push(2)
      bpush16(sv, 0x0304)
    push_ext(ext, 43, sv)
    # psk_key_exchange_modes (psk_dhe_ke): some servers want it present
    pk = ByteArray.new(0)
    pk.push(1)
    pk.push(1)
    push_ext(ext, 45, pk)
    # key_share: x25519
    ks = ByteArray.new(0)
    e = ByteArray.new(0)
    bpush16(e, 0x001d)
    push_vec16(e, @pub)
    push_vec16(ks, e)
    push_ext(ext, 51, ks)
    if @quic_params != nil
      push_ext(ext, 57, @quic_params)
    # pre_shared_key must be the last extension: identity + a binder over the truncated hello
    if @ticket != nil
      ids = ByteArray.new(0)
      id = ByteArray.new(0)
      push_vec16(id, @ticket.ticket)
      bpush32(id, @ticket.obfuscated_age)
      push_vec16(ids, id)
      binders = ByteArray.new(0)
      bpush16(binders, 33)
      binders.push(32)
      bappend(binders, ByteArray.new(32))
      pre = bcat(ids, binders)
      push_ext(ext, 41, pre)
    push_vec16(body, ext)
    m = hs_msg(1, body)
    if @ticket != nil
      @early = hkdf_extract(ByteArray.new(0), @ticket.psk)
      bk = derive_secret(@early, "res binder", empty_hash())
      fk = hkdf_label(bk, "finished", ByteArray.new(0), 32)
      binder = hmac256(fk, sha256(bslice(m, 0, m.size - 35)))
      i = 0
      while i < 32
        m[m.size - 32 + i] = binder[i]
        i += 1
    bappend(@transcript, m)
    @state = :wait_sh
    m

  -> th
    sha256(@transcript)

  -> th12
    t12_sha384?() ? sha384(@transcript) : sha256(@transcript)

  -> t12_sha384?
    @cipher == 0xc02c || @cipher == 0xc030

  # Consume one complete handshake message (with its 4-byte header). Returns a
  # client Finished message to send when the server's flight is complete, else nil.
  -> feed(msg)
    type = msg[0]
    body = bslice(msg, 4, msg.size - 4)
    case type
    when 2
      raise "TLS: unexpected ServerHello" if @state != :wait_sh
      server_hello(body)
      bappend(@transcript, msg)
      if @tls12
        @state = :wait_cert12
        return nil
      handshake_secrets()
      @state = :wait_ee
      return nil
    when 8
      raise "TLS: unexpected EncryptedExtensions" if @state != :wait_ee
      encrypted_extensions(body)
      bappend(@transcript, msg)
      # a resumed handshake has no Certificate / CertificateVerify: the PSK authenticates the server
      @state = @resumed ? :wait_fin : :wait_cert
      return nil
    when 11
      if @state == :wait_cert12
        certificate12(body)
        bappend(@transcript, msg)
        @state = :wait_ske12
        return nil
      raise "TLS: unexpected Certificate" if @state != :wait_cert
      certificate(body)
      bappend(@transcript, msg)
      @state = :wait_cv
      return nil
    when 12
      raise "TLS: unexpected ServerKeyExchange" if @state != :wait_ske12
      server_key_exchange12(body)
      bappend(@transcript, msg)
      @state = :wait_shd12
      return nil
    when 14
      raise "TLS: unexpected ServerHelloDone" if @state != :wait_shd12
      bappend(@transcript, msg)
      cke_body = ByteArray.new(0)
      push_vec8(cke_body, @t12_client_pub)
      @t12_cke = hs_msg(16, cke_body)
      bappend(@transcript, @t12_cke)
      use384 = t12_sha384?()
      if @ems
        @master = tls12_prf(use384, @t12_pms, "extended master secret", th12(), 48)
      else
        @master = tls12_prf(use384, @t12_pms, "master secret", bcat(@client_random, @server_random), 48)
      klen = use384 ? 32 : 16
      kb = tls12_prf(use384, @master, "key expansion", bcat(@server_random, @client_random), klen * 2 + 8)
      @t12_c_key = bslice(kb, 0, klen)
      @t12_s_key = bslice(kb, klen, klen)
      @t12_c_iv = bslice(kb, klen * 2, 4)
      @t12_s_iv = bslice(kb, klen * 2 + 4, 4)
      vd = tls12_prf(use384, @master, "client finished", th12(), 12)
      fin = hs_msg(20, vd)
      bappend(@transcript, fin)
      @state = :wait_fin12
      return fin
    when 15
      raise "TLS: unexpected CertificateVerify" if @state != :wait_cv
      certificate_verify(body)
      bappend(@transcript, msg)
      @state = :wait_fin
      return nil
    when 20
      if @state == :wait_fin12
        want = tls12_prf(t12_sha384?(), @master, "server finished", th12(), 12)
        raise "TLS: server Finished does not verify" if !beq(want, body)
        bappend(@transcript, msg)
        @state = :done
        return nil
      raise "TLS: unexpected Finished" if @state != :wait_fin
      fk = hkdf_label(@s_hs, "finished", ByteArray.new(0), 32)
      want = hmac256(fk, th())
      raise "TLS: server Finished does not verify" if !beq(want, body)
      bappend(@transcript, msg)
      app_secrets()
      ck = hkdf_label(@c_hs, "finished", ByteArray.new(0), 32)
      fin = hs_msg(20, hmac256(ck, th()))
      bappend(@transcript, fin)
      @res_master = derive_secret(@master, "res master", th())
      @verified = @ticket.verified if @resumed
      @state = :done
      return fin
    when 4
      new_session_ticket(body) if !@tls12 && @res_master != nil
      return nil
    when 24
      # KeyUpdate: not needed for the lifetime of a page fetch
      return nil
    when 13
      raise "TLS: client certificates are not supported"
    raise "TLS: unexpected handshake message " + type.to_s

  -> server_hello(b)
    raise "TLS: short ServerHello" if b.size < 38
    legacy_ver = bget16(b, 0)
    rnd = bslice(b, 2, 32)
    hrr = unhex("cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c")
    raise "TLS: HelloRetryRequest (server wants a group other than X25519)" if beq(rnd, hrr)
    o = 34
    sid = b[o]
    o = o + 1 + sid
    @cipher = bget16(b, o)
    o += 3
    elen = o + 2 <= b.size ? bget16(b, o) : 0
    o += 2 if o + 2 <= b.size
    e_end = o + elen
    shared = nil
    version = 0
    while o + 4 <= e_end && o + 4 <= b.size
      et = bget16(b, o)
      el = bget16(b, o + 2)
      ed = bslice(b, o + 4, el)
      if et == 43
        version = bget16(ed, 0)
      elsif et == 41
        @resumed = @ticket != nil && bget16(ed, 0) == 0
      elsif et == 16 && el > 3
        pl = ed[2]
        @alpn = str_of(bslice(ed, 3, pl))
      elsif et == 23
        @ems = true
      elsif et == 51
        @group = bget16(ed, 0)
        kl = bget16(ed, 2)
        raise "TLS: bad X25519 key share" if kl != 32 || @group != 0x001d
        peer = bslice(ed, 4, kl)
        shared = x25519_fast(@priv, peer)
        raise "TLS: all-zero X25519 shared secret" if x25519_is_zero(shared)
      o = o + 4 + el
    if version != 0x0304 && @quic_params == nil && (legacy_ver == 0x0303 || version == 0x0303) && (@cipher == 0xc02b || @cipher == 0xc02f || @cipher == 0xc02c || @cipher == 0xc030)
      @tls12 = true
      @server_random = rnd
      return nil
    raise "TLS: server chose cipher " + @cipher.to_s if @cipher != 0x1301
    raise "TLS: server did not negotiate TLS 1.3" if version != 0x0304
    raise "TLS: no key share" if shared == nil
    @shared = shared

  -> certificate12(b)
    raise "TLS: short TLS 1.2 Certificate" if b.size < 3
    total = bget24(b, 0)
    o = 3
    e = o + total
    while o + 3 <= e
      cl = bget24(b, o)
      o += 3
      @certs.push(bslice(b, o, cl))
      o += cl
    raise "TLS: empty certificate chain" if @certs.size == 0

  -> server_key_exchange12(b)
    raise "TLS: short ServerKeyExchange" if b.size < 8
    ct = b[0]
    raise "TLS: unsupported ECDHE curve type " + ct.to_s if ct != 3
    @group = bget16(b, 1)
    plen = b[3]
    raise "TLS: short ServerKeyExchange pubkey" if 4 + plen + 4 > b.size
    spub = bslice(b, 4, plen)
    params = bslice(b, 0, 4 + plen)
    alg = bget16(b, 4 + plen)
    slen = bget16(b, 6 + plen)
    sig = bslice(b, 8 + plen, slen)
    content = bcat(bcat(@client_random, @server_random), params)
    if @verify
      verify_server(@certs, @host, alg, sig, content)
      @verified = true
    if @group == 0x001d
      raise "TLS: bad X25519 server key" if plen != 32
      @t12_pms = x25519_fast(@priv, spub)
      raise "TLS: all-zero X25519 shared secret" if x25519_is_zero(@t12_pms)
      @t12_client_pub = @pub
    elsif @group == 0x0017
      raise "TLS: bad P-256 server key" if plen != 65 || spub[0] != 4
      c = curve(OID_P256)
      sx = be_to_int(bslice(spub, 1, 32))
      sy = be_to_int(bslice(spub, 33, 32))
      raise "TLS: P-256 server point not on curve" if !c.on_curve?(sx, sy)
      d = (be_to_int(brand(32)) % (c.n - 1)) + 1
      one = 1 ## int
      pt = c.mul(d, [c.gx, c.gy, one])
      zi = pt[2].pow(c.p - 2, c.p)
      zi2 = (zi * zi) % c.p
      cx = (pt[0] * zi2) % c.p
      cx = cx + c.p if cx < 0
      cy = (pt[1] * zi2 * zi) % c.p
      cy = cy + c.p if cy < 0
      cpub = ByteArray.new(0)
      cpub.push(4)
      bappend(cpub, int_to_be(cx, 32))
      bappend(cpub, int_to_be(cy, 32))
      @t12_client_pub = cpub
      sh_pt = c.mul(d, [sx, sy, one])
      shx = c.affine_x(sh_pt)
      raise "TLS: P-256 ECDHE point at infinity" if shx == nil
      shx = shx + c.p if shx < 0
      @t12_pms = int_to_be(shx, 32)
    else
      raise "TLS: unsupported ECDHE named curve " + @group.to_s

  -> handshake_secrets
    zero = ByteArray.new(32)
    early = @resumed ? @early : hkdf_extract(ByteArray.new(0), zero)
    derived = derive_secret(early, "derived", empty_hash())
    @hs_secret = hkdf_extract(derived, @shared)
    h = th()
    @c_hs = derive_secret(@hs_secret, "c hs traffic", h)
    @s_hs = derive_secret(@hs_secret, "s hs traffic", h)

  -> app_secrets
    derived = derive_secret(@hs_secret, "derived", empty_hash())
    master = hkdf_extract(derived, ByteArray.new(32))
    @master = master
    h = th()
    @c_ap = derive_secret(master, "c ap traffic", h)
    @s_ap = derive_secret(master, "s ap traffic", h)

  # Tickets received so far, removed from the connection (for the ticket store).
  -> take_tickets
    out = @new_tickets.map(->(x) x)
    while @new_tickets.size > 0
      @new_tickets.pop
    out

  # NewSessionTicket → a TlsTicket for resuming later (RFC 8446 §4.6.1).
  -> new_session_ticket(b)
    lifetime = bget32(b, 0)
    age_add = bget32(b, 4)
    nl = b[8]
    nonce = bslice(b, 9, nl)
    o = 9 + nl
    tl = bget16(b, o)
    ticket = bslice(b, o + 2, tl)
    o = o + 2 + tl
    max_early = 0
    el = bget16(b, o)
    e = o + 2 + el
    o += 2
    while o + 4 <= e
      et = bget16(b, o)
      ln = bget16(b, o + 2)
      max_early = bget32(b, o + 4) if et == 42 && ln == 4
      o = o + 4 + ln
    return nil if lifetime == 0
    psk = hkdf_label(@res_master, "resumption", nonce, 32)
    @new_tickets.push(TlsTicket.new(ticket, psk, age_add, lifetime, Instant.now.unix_ms, @alpn, @verified, max_early))

  -> encrypted_extensions(b)
    elen = bget16(b, 0)
    o = 2
    while o + 4 <= 2 + elen
      et = bget16(b, o)
      el = bget16(b, o + 2)
      ed = bslice(b, o + 4, el)
      if et == 16 && el > 3
        pl = ed[2]
        @alpn = str_of(bslice(ed, 3, pl))
      elsif et == 57
        @peer_params = ed
      o = o + 4 + el

  -> certificate(b)
    ctx = b[0]
    o = 1 + ctx
    total = bget24(b, o)
    o += 3
    e = o + total
    while o + 3 <= e
      cl = bget24(b, o)
      o += 3
      @certs.push(bslice(b, o, cl))
      o += cl
      xl = bget16(b, o)
      o = o + 2 + xl
    raise "TLS: empty certificate chain" if @certs.size == 0

  -> certificate_verify(b)
    alg = bget16(b, 0)
    sl = bget16(b, 2)
    sig = bslice(b, 4, sl)
    content = ByteArray.new(0)
    64.times ->(i) content.push(32)
    bappend(content, bytes_of("TLS 1.3, server CertificateVerify"))
    content.push(0)
    bappend(content, th())
    if @verify
      verify_server(@certs, @host, alg, sig, content)
      @verified = true


# ---- TLS over TCP: the record layer ----

+ TlsConn
  ro :alpn, :tls

  # addr: an IP address string to connect to (the host still names SNI and the certificate check).
  # sock: an already connected Socket or raw integer fd (>= 0) to use (blade/netpool connects with a deadline).
  -> new(@host, @port, alpn, verify = true, addr = nil, ticket = nil, sock = nil)
    @fd = -1
    @sock = nil
    if sock.is_a?(Integer) && sock >= 0
      @fd = sock
    elsif sock != nil
      @sock = sock
      @sock.set_timeout(20000)
    else
      target = addr == nil ? @host : addr
      dl = ccall_nobox("__w_deadline_ticks_after_ms", 8000 ## i64) ## i64
      fd = ccall_nobox("w_socket_connect_fd_until", target, @port ## i64, dl) ## i64
      raise "socket: connect failed" if fd < 0
      @fd = fd
    @tls = Tls13.new(@host, alpn, nil, ticket)
    @tls.verify = verify
    @rbuf = ByteArray.new(131072)
    @rpos = 0
    @rend = 0
    @rhdr = ByteArray.new(5)
    @hsbuf = ByteArray.new(0)
    @app = ByteArray.new(0)
    @rkey = nil
    @riv = nil
    @rseq = 0
    @wkey = nil
    @wiv = nil
    @wseq = 0
    @closed = false
    @alpn = nil
    handshake()

  -> keys(secret)
    [hkdf_label(secret, "key", ByteArray.new(0), 16), hkdf_label(secret, "iv", ByteArray.new(0), 12)]

  -> nonce(iv, seq)
    n = bslice(iv, 0, 12)
    i = 0
    while i < 8
      n[11 - i] = n[11 - i] ^ ((seq >> (8 * i)) & 255)
      i += 1
    n

  -> raw_write_all(rec)
    if @fd >= 0
      ptr = ccall_nobox("w_array_data_ptr", rec) ## i64
      len = rec.size ## i64
      dl = ccall_nobox("__w_deadline_ticks_after_ms", 20000 ## i64) ## i64
      w = ccall_nobox("w_socket_write_fd_until", @fd ## i64, ptr, len, dl) ## i64
      raise "TLS: write failed" if w < len
    else
      @sock.write_bytes(rec)
    nil

  -> write_record(type, payload)
    rec = ByteArray.new(0)
    if @wkey == nil
      rec.push(type)
      bpush16(rec, type == 22 && @tls.state == :wait_sh ? 0x0301 : 0x0303)
      bpush16(rec, payload.size)
      bappend(rec, payload)
    elsif @tls.tls12
      en = u64_be(@wseq)
      nonce = bcat(@wiv, en)
      aad = tls12_gcm_aad(@wseq, type, payload.size)
      ct = aes_gcm_seal(@wkey, nonce, payload, aad)
      @wseq += 1
      hdr = ByteArray.new(5)
      hdr[0] = type
      hdr[1] = 3
      hdr[2] = 3
      cl = en.size + ct.size
      hdr[3] = (cl >> 8) & 255
      hdr[4] = cl & 255
      rec = bcat(hdr, bcat(en, ct))
    else
      plen = payload.size
      inner = ByteArray.new(plen + 1)
      bmove(inner, 0, payload, 0, plen) if plen > 0
      inner[plen] = type
      hdr = ByteArray.new(5)
      hdr[0] = 23
      hdr[1] = 3
      hdr[2] = 3
      cl = inner.size + 16
      hdr[3] = (cl >> 8) & 255
      hdr[4] = cl & 255
      ct = aes_gcm_seal(@wkey, nonce(@wiv, @wseq), inner, hdr)
      @wseq += 1
      rec = bcat(hdr, ct)
    raw_write_all(rec)

  # Zero-copy sliding receive buffer: reads directly from TCP fd into @rbuf via
  # w_socket_read_fd_until (avoiding WString malloc, ASCII ciphertext scan, and double bmove).
  -> fill(n)
    while @rend - @rpos < n
      keep = @rend - @rpos
      if keep == 0
        @rpos = 0
        @rend = 0
      elsif @rpos > 0 && @rbuf.size - @rend < 16384
        bmove(@rbuf, 0, @rbuf, @rpos, keep)
        @rpos = 0
        @rend = keep
      if @rbuf.size - @rpos < n
        ncap = @rbuf.size * 2
        ncap = n + 32768 if ncap < n + 32768
        nb = ByteArray.new(ncap)
        bmove(nb, 0, @rbuf, @rpos, keep) if keep > 0
        @rbuf = nb
        @rpos = 0
        @rend = keep
      space = @rbuf.size - @rend
      if @fd >= 0
        base = ccall_nobox("w_array_data_ptr", @rbuf) ## i64
        dl = ccall_nobox("__w_deadline_ticks_after_ms", 20000 ## i64) ## i64
        got = ccall_nobox("w_socket_read_fd_until", @fd ## i64, base + (@rend ## i64), space ## i64, dl) ## i64
        raise "TLS: connection closed" if got <= 0
        @rend += got
      else
        chunk = @sock.read(space < 65536 ? space : 65536)
        raise "TLS: connection closed" if chunk == nil || chunk.size == 0
        cv = ccall("w_string_bytes_view", chunk) ## u8[]
        bmove(@rbuf, @rend, cv, 0, chunk.size)
        @rend += chunk.size
    true

  # One record: [content type, plaintext].
  -> read_record
    fill(5)
    type = @rbuf[@rpos]
    len = bget16(@rbuf, @rpos + 3)
    fill(5 + len)
    bmove(@rhdr, 0, @rbuf, @rpos, 5)
    body = bslice(@rbuf, @rpos + 5, len)
    @rpos = @rpos + 5 + len
    if @rpos == @rend
      @rpos = 0
      @rend = 0
    if @rkey != nil && @tls.tls12
      raise "TLS: short TLS 1.2 GCM record" if body.size < 24
      en = bslice(body, 0, 8)
      ct = bslice(body, 8, body.size - 8)
      aad = tls12_gcm_aad(@rseq, type, ct.size - 16)
      pt = aes_gcm_open(@rkey, bcat(@riv, en), ct, aad)
      raise "TLS: record authentication failed" if pt == nil
      @rseq += 1
      return [type, pt]
    if type == 23 && @rkey != nil
      pt = aes_gcm_open(@rkey, nonce(@riv, @rseq), body, @rhdr)
      raise "TLS: record authentication failed" if pt == nil
      @rseq += 1
      k = pt.size - 1
      while k >= 0 && pt[k] == 0
        k -= 1
      raise "TLS: empty inner plaintext" if k < 0
      return [pt[k], bslice(pt, 0, k)]
    [type, body]

  -> handshake
    write_record(22, @tls.client_hello())
    while @tls.state != :done
      r = read_record()
      t = r[0]
      if t == 21
        raise "TLS alert " + r[1][1].to_s
      if t == 20
        if @tls.tls12 && @tls.state == :wait_fin12
          @rkey = @tls.t12_s_key
          @riv = @tls.t12_s_iv
          @rseq = 0
        next
      raise "TLS: unexpected record type " + t.to_s if t != 22
      bappend(@hsbuf, r[1])
      while @hsbuf.size >= 4 && @hsbuf.size >= 4 + bget24(@hsbuf, 1)
        ml = 4 + bget24(@hsbuf, 1)
        msg = bslice(@hsbuf, 0, ml)
        @hsbuf = bslice(@hsbuf, ml, @hsbuf.size - ml)
        before = @tls.state
        fin = @tls.feed(msg)
        if before == :wait_sh && !@tls.tls12
          k = keys(@tls.s_hs)
          @rkey = k[0]
          @riv = k[1]
          @rseq = 0
        if fin != nil
          if @tls.tls12
            write_record(22, @tls.t12_cke)
            ccs = ByteArray.new(1)
            ccs[0] = 1
            write_record(20, ccs)
            @wkey = @tls.t12_c_key
            @wiv = @tls.t12_c_iv
            @wseq = 0
            write_record(22, fin)
          else
            k = keys(@tls.c_hs)
            @wkey = k[0]
            @wiv = k[1]
            @wseq = 0
            write_record(22, fin)
            k = keys(@tls.c_ap)
            @wkey = k[0]
            @wiv = k[1]
            @wseq = 0
            k = keys(@tls.s_ap)
            @rkey = k[0]
            @riv = k[1]
            @rseq = 0
    @alpn = @tls.alpn

  # NewSessionTicket (and KeyUpdate) arrive as handshake records after the handshake.
  -> post_handshake(b)
    bappend(@hsbuf, b)
    while @hsbuf.size >= 4 && @hsbuf.size >= 4 + bget24(@hsbuf, 1)
      ml = 4 + bget24(@hsbuf, 1)
      @tls.feed(bslice(@hsbuf, 0, ml))
      @hsbuf = bslice(@hsbuf, ml, @hsbuf.size - ml)

  -> write(data)
    o = 0
    while o < data.size
      n = data.size - o
      n = 16000 if n > 16000
      write_record(23, bslice(data, o, n))
      o += n

  # Application bytes as they arrive; nil at close.
  -> read
    while true
      return nil if @closed
      begin
        r = read_record()
      rescue e
        raise e if e.to_s.index("closed") == nil
        @closed = true
        return nil
      t = r[0]
      if t == 23
        return r[1] if r[1].size > 0
      elsif t == 21
        @closed = true
        return nil
      elsif t == 22
        post_handshake(r[1])
    nil

  -> close
    begin
      a = ByteArray.new(2)
      a[0] = 1
      a[1] = 0
      write_record(21, a)
    rescue e
      nil
    if @fd >= 0
      fd = @fd
      @fd = -1
      ccall_nobox("w_socket_close_fd", fd ## i64)
    elsif @sock != nil
      @sock.close
    nil
