# blade/tls — a TLS 1.3 client (RFC 8446).
#
# Tls13 is the handshake engine alone: it builds the ClientHello and consumes
# handshake messages, producing the traffic secrets. It knows nothing about the
# transport, so TlsConn (TLS records over TCP, for HTTP/1.1 and HTTP/2) and QUIC
# (CRYPTO frames, for HTTP/3) share it.
#
# Offered: TLS_AES_128_GCM_SHA256 (0x1301), TLS_AES_256_GCM_SHA384 (0x1302),
# TLS_CHACHA20_POLY1305_SHA256 (0x1303), X25519MLKEM768 / X25519 / P-256 / P-384
# (with HelloRetryRequest), RFC 8701 GREASE, OCSP status_request (ext 5),
# signed_certificate_timestamp (ext 18), and RFC 8879 compress_certificate
# (ext 27: brotli + zlib). The server's chain and CertificateVerify are checked
# by blade/x509.

TLS_EMPTY_HASH = [nil, nil]

-> empty_hash
  TLS_EMPTY_HASH[0] = sha256(ByteArray.new(0)) if TLS_EMPTY_HASH[0] == nil
  TLS_EMPTY_HASH[0]

-> empty_hash_for(cs)
  if cs == 0x1302
    TLS_EMPTY_HASH[1] = sha384(ByteArray.new(0)) if TLS_EMPTY_HASH[1] == nil
    return TLS_EMPTY_HASH[1]
  empty_hash()

# RFC 8701 GREASE uint16 values: 0x0a0a, 0x1a1a, ..., 0xfafa.
-> tls_grease(b)
  n = b & 15
  (n << 12) | (n << 4) | 0x0a0a

# Generate a NIST curve (P-256 / P-384) keypair: [priv_be_bytes, uncompressed_pub_bytes].
-> tls_ec_keygen(group)
  oid = group == 0x0018 ? OID_P384 : OID_P256
  c = curve(oid)
  nb = c.bits / 8
  d = (be_to_int(brand(nb)) % (c.n - 1)) + 1
  one = 1 ## int
  pt = c.mul(d, [c.gx, c.gy, one])
  zi = pt[2].pow(c.p - 2, c.p)
  zi2 = (zi * zi) % c.p
  cx = (pt[0] * zi2) % c.p
  cx = cx + c.p if cx < 0
  cy = (pt[1] * zi2 * zi) % c.p
  cy = cy + c.p if cy < 0
  pub = ByteArray.new(0)
  pub.push(4)
  bappend(pub, int_to_be(cx, nb))
  bappend(pub, int_to_be(cy, nb))
  [int_to_be(d, nb), pub]

# Compute NIST ECDH shared secret x-coordinate (nb bytes) using zero-alloc pkfast limbs.
-> tls_ec_shared(group, priv_bytes, peer_pub)
  bits = group == 0x0018 ? 384 : 256
  nb = bits / 8
  raise "TLS: bad ECDHE key share length" if peer_pub.size != 1 + 2 * nb || peer_pub[0] != 4
  px = bslice(peer_pub, 1, nb)
  py = bslice(peer_pub, 1 + nb, nb)
  sh = pk_ec_mul_x(bits, priv_bytes, px, py)
  raise "TLS: invalid ECDHE peer public key" if sh == nil
  sh

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
  ro :ocsp_response, :sct_list, :cert_compressed, :hrr_ch2

  # ticket: a TlsTicket from an earlier connection to offer for resumption (PSK with (EC)DHE), or nil.
  -> new(@host, @alpn_offer, @quic_params = nil, @ticket = nil)
    @priv = brand(32)
    @pub = x25519_base_fast(@priv)
    @mlkem_ek = nil
    @mlkem_dk = nil
    @ec_priv = nil
    @ec_pub = nil
    @ec_group = 0
    @grease = brand(8)
    @session_id = @quic_params == nil ? brand(32) : ByteArray.new(0)
    @hrr_cookie = nil
    @hrr_group = 0
    @did_hrr = false
    @hrr_ch2 = nil
    @ocsp_response = nil
    @sct_list = nil
    @cert_compressed = 0
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
    @cipher = 0x1301
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

  -> take_hrr_ch2
    m = @hrr_ch2
    @hrr_ch2 = nil
    m

  -> client_hello
    body = ByteArray.new(0)
    bpush16(body, 0x0303)
    @client_random = brand(32) if @client_random == nil
    bappend(body, @client_random)
    if @quic_params == nil
      push_vec8(body, @session_id)
    else
      body.push(0)
    g_cs  = tls_grease(@grease[0])
    g_ext1 = tls_grease(@grease[1])
    g_ext2 = tls_grease((@grease[1] + 1) & 15)
    g_grp = tls_grease(@grease[2])
    g_ver = tls_grease(@grease[3])
    g_ks  = g_grp
    suites = ByteArray.new(0)
    bpush16(suites, g_cs)
    bpush16(suites, 0x1301)
    bpush16(suites, 0x1302)
    bpush16(suites, 0x1303)
    if @quic_params == nil
      bpush16(suites, 0xc02b)
      bpush16(suites, 0xc02f)
      bpush16(suites, 0xc02c)
      bpush16(suites, 0xc030)
    push_vec16(body, suites)
    body.push(1)
    body.push(0)
    ext = ByteArray.new(0)
    # leading GREASE extension (RFC 8701)
    push_ext(ext, g_ext1, ByteArray.new(0))
    # server_name (ext 0)
    sn = ByteArray.new(0)
    hb = bytes_of(@host)
    entry = ByteArray.new(0)
    entry.push(0)
    push_vec16(entry, hb)
    push_vec16(sn, entry)
    push_ext(ext, 0, sn)
    if @quic_params == nil
      # extended_master_secret (ext 23, RFC 7627)
      push_ext(ext, 23, ByteArray.new(0))
      # renegotiation_info (ext 65281, empty for initial handshake)
      ri = ByteArray.new(1)
      ri[0] = 0
      push_ext(ext, 0xff01, ri)
    # supported_groups (ext 10): GREASE, [X25519MLKEM768 over TCP], x25519, secp256r1, secp384r1
    g = ByteArray.new(0)
    if @quic_params == nil
      bpush16(g, 10)
      bpush16(g, g_grp)
      bpush16(g, 0x11ec)
      bpush16(g, 0x001d)
      bpush16(g, 0x0017)
      bpush16(g, 0x0018)
    else
      bpush16(g, 8)
      bpush16(g, g_grp)
      bpush16(g, 0x001d)
      bpush16(g, 0x0017)
      bpush16(g, 0x0018)
    push_ext(ext, 10, g)
    if @quic_params == nil
      # ec_point_formats (ext 11): uncompressed
      epf = ByteArray.new(0)
      epf.push(1)
      epf.push(0)
      push_ext(ext, 11, epf)
    # ALPN (ext 16)
    if @alpn_offer != nil && @alpn_offer.size > 0
      al = ByteArray.new(0)
      @alpn_offer.each ->(p) push_vec8(al, bytes_of(p))
      a2 = ByteArray.new(0)
      push_vec16(a2, al)
      push_ext(ext, 16, a2)
    # status_request (ext 5, RFC 6066 OCSP stapling)
    ocsp = ByteArray.new(5)
    ocsp[0] = 1
    push_ext(ext, 5, ocsp)
    # signed_certificate_timestamp (ext 18, RFC 6962 CT)
    push_ext(ext, 18, ByteArray.new(0))
    # signature_algorithms (ext 13)
    sa = ByteArray.new(0)
    algs = [0x0403, 0x0804, 0x0401, 0x0503, 0x0805, 0x0501, 0x0806, 0x0601]
    bpush16(sa, algs.size * 2)
    algs.each ->(a) bpush16(sa, a)
    push_ext(ext, 13, sa)
    # key_share (ext 51)
    ks_entries = ByteArray.new(0)
    if @hrr_group != 0
      # ClientHello2 after HelloRetryRequest MUST carry only the requested group
      if @hrr_group == 0x0017 || @hrr_group == 0x0018
        kp = tls_ec_keygen(@hrr_group)
        @ec_group = @hrr_group
        @ec_priv = kp[0]
        @ec_pub = kp[1]
        bpush16(ks_entries, @hrr_group)
        push_vec16(ks_entries, @ec_pub)
      elsif @hrr_group == 0x11ec
        mk = mlkem768_keygen()
        @mlkem_ek = mk[0]
        @mlkem_dk = mk[1]
        @priv = brand(32)
        @pub = x25519_base_fast(@priv)
        bpush16(ks_entries, 0x11ec)
        push_vec16(ks_entries, bcat(@mlkem_ek, @pub))
      else
        @priv = brand(32)
        @pub = x25519_base_fast(@priv)
        bpush16(ks_entries, 0x001d)
        push_vec16(ks_entries, @pub)
    else
      # GREASE key share (1-byte dummy key_exchange)
      bpush16(ks_entries, g_ks)
      push_vec16(ks_entries, ByteArray.new(1))
      if @quic_params == nil
        # Hybrid post-quantum X25519MLKEM768 + classical X25519 (saves HRR on both PQ and classical servers)
        if @mlkem_ek == nil
          mk = mlkem768_keygen()
          @mlkem_ek = mk[0]
          @mlkem_dk = mk[1]
        bpush16(ks_entries, 0x11ec)
        push_vec16(ks_entries, bcat(@mlkem_ek, @pub))
      bpush16(ks_entries, 0x001d)
      push_vec16(ks_entries, @pub)
    ks = ByteArray.new(0)
    push_vec16(ks, ks_entries)
    push_ext(ext, 51, ks)
    # psk_key_exchange_modes (ext 45: psk_dhe_ke = 1)
    pk = ByteArray.new(0)
    pk.push(1)
    pk.push(1)
    push_ext(ext, 45, pk)
    # supported_versions (ext 43): GREASE, TLS 1.3 (+ TLS 1.2 over TCP)
    sv = ByteArray.new(0)
    if @quic_params == nil
      sv.push(6)
      bpush16(sv, g_ver)
      bpush16(sv, 0x0304)
      bpush16(sv, 0x0303)
    else
      sv.push(4)
      bpush16(sv, g_ver)
      bpush16(sv, 0x0304)
    push_ext(ext, 43, sv)
    # cookie (ext 44) if echoed for HelloRetryRequest
    if @hrr_cookie != nil
      ck_ext = ByteArray.new(0)
      push_vec16(ck_ext, @hrr_cookie)
      push_ext(ext, 44, ck_ext)
    # compress_certificate (ext 27, RFC 8879): brotli (2), zlib (1)
    cc = ByteArray.new(0)
    cc.push(4)
    bpush16(cc, 2)
    bpush16(cc, 1)
    push_ext(ext, 27, cc)
    if @quic_params != nil
      push_ext(ext, 57, @quic_params)
    # trailing GREASE extension (1 zero byte, before pre_shared_key)
    push_ext(ext, g_ext2, ByteArray.new(1))
    # pre_shared_key (ext 41) MUST be the final extension
    tcs = 0x1301
    thlen = 32
    if @ticket != nil
      thlen = @ticket.psk.size == 48 ? 48 : 32
      tcs = thlen == 48 ? 0x1302 : 0x1301
      ids = ByteArray.new(0)
      id = ByteArray.new(0)
      push_vec16(id, @ticket.ticket)
      bpush32(id, @ticket.obfuscated_age)
      push_vec16(ids, id)
      binders = ByteArray.new(0)
      bpush16(binders, thlen + 1)
      binders.push(thlen)
      bappend(binders, ByteArray.new(thlen))
      pre = bcat(ids, binders)
      push_ext(ext, 41, pre)
    push_vec16(body, ext)
    m = hs_msg(1, body)
    if @ticket != nil
      @early = hkdf_extract_h(tcs, ByteArray.new(0), @ticket.psk)
      bk = derive_secret_h(tcs, @early, "res binder", empty_hash_for(tcs))
      fk = hkdf_label_h(tcs, bk, "finished", ByteArray.new(0), thlen)
      trunc = bcat(@transcript, bslice(m, 0, m.size - (thlen + 3)))
      binder = tls_hmac(tcs, fk, tls_hash(tcs, trunc))
      i = 0
      while i < thlen
        m[m.size - thlen + i] = binder[i]
        i += 1
    bappend(@transcript, m)
    @state = :wait_sh
    m

  -> th
    tls_hash(@cipher, @transcript)

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
      is_hrr = server_hello(body)
      if is_hrr
        # RFC 8446 §4.4.1: replace ClientHello1 with synthetic message_hash(254)
        ch1_hash = tls_hash(@cipher, @transcript)
        @transcript = hs_msg(254, ch1_hash)
        bappend(@transcript, msg)
        @hrr_ch2 = client_hello()
        return nil
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
    when 25
      # RFC 8879 §4: CompressedCertificate replaces Certificate (11); transcript hashes msg (compressed)
      raise "TLS: unexpected CompressedCertificate" if @state != :wait_cert
      compressed_certificate(body)
      bappend(@transcript, msg)
      @state = :wait_cv
      return nil
    when 22
      # RFC 6066 §8: TLS 1.2 CertificateStatus (OCSP response) before ServerKeyExchange
      raise "TLS: unexpected CertificateStatus" if !@tls12 || @state != :wait_ske12
      if body.size >= 4 && body[0] == 1
        olen = bget24(body, 1)
        @ocsp_response = bslice(body, 4, olen) if 4 + olen <= body.size
      bappend(@transcript, msg)
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
      hlen = suite_hash_len(@cipher)
      fk = hkdf_label_h(@cipher, @s_hs, "finished", ByteArray.new(0), hlen)
      want = tls_hmac(@cipher, fk, th())
      raise "TLS: server Finished does not verify" if !beq(want, body)
      bappend(@transcript, msg)
      app_secrets()
      ck = hkdf_label_h(@cipher, @c_hs, "finished", ByteArray.new(0), hlen)
      fin = hs_msg(20, tls_hmac(@cipher, ck, th()))
      bappend(@transcript, fin)
      @res_master = derive_secret_h(@cipher, @master, "res master", th())
      @verified = @ticket.verified if @resumed
      @state = :done
      return fin
    when 4
      new_session_ticket(body) if !@tls12 && @res_master != nil
      return nil
    when 24
      raise "TLS: unexpected KeyUpdate outside the application record layer"
    when 13
      raise "TLS: client certificates are not supported"
    raise "TLS: unexpected handshake message " + type.to_s

  -> valid_tls13_cipher?(cs)
    cs == 0x1301 || cs == 0x1302 || cs == 0x1303

  # Returns true when ServerHello is a HelloRetryRequest (caller updates transcript & sends CH2).
  -> server_hello(b)
    raise "TLS: short ServerHello" if b.size < 38
    legacy_ver = bget16(b, 0)
    rnd = bslice(b, 2, 32)
    hrr_magic = unhex("cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c")
    is_hrr = beq(rnd, hrr_magic)
    o = 34
    sid = b[o]
    o = o + 1 + sid
    @cipher = bget16(b, o)
    o += 3
    elen = o + 2 <= b.size ? bget16(b, o) : 0
    o += 2 if o + 2 <= b.size
    e_end = o + elen
    if is_hrr
      raise "TLS: duplicate HelloRetryRequest" if @did_hrr
      raise "TLS: unsupported cipher in HelloRetryRequest" if !valid_tls13_cipher?(@cipher)
      @did_hrr = true
      hrr_ver = 0
      req_group = 0
      while o + 4 <= e_end && o + 4 <= b.size
        et = bget16(b, o)
        el = bget16(b, o + 2)
        ed = bslice(b, o + 4, el)
        if et == 43 && el >= 2
          hrr_ver = bget16(ed, 0)
        elsif et == 44 && el >= 2
          clen = bget16(ed, 0)
          @hrr_cookie = bslice(ed, 2, clen)
        elsif et == 51 && el == 2
          req_group = bget16(ed, 0)
        o = o + 4 + el
      raise "TLS: HelloRetryRequest did not negotiate TLS 1.3" if hrr_ver != 0x0304
      if req_group != 0
        raise "TLS: unsupported HRR group 0x" + req_group.to_s(16) if req_group != 0x001d && req_group != 0x0017 && req_group != 0x0018 && req_group != 0x11ec
        @hrr_group = req_group
      return true
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
      elsif et == 18
        @sct_list = ed
      elsif et == 23
        @ems = true
      elsif et == 51
        @group = bget16(ed, 0)
        kl = bget16(ed, 2)
        peer = bslice(ed, 4, kl)
        if @group == 0x001d
          raise "TLS: bad X25519 key share" if kl != 32
          shared = x25519_fast(@priv, peer)
          raise "TLS: all-zero X25519 shared secret" if x25519_is_zero(shared)
        elsif @group == 0x11ec
          raise "TLS: bad X25519MLKEM768 key share" if kl != 1120 || @mlkem_dk == nil
          ct_pq = bslice(peer, 0, 1088)
          peer_x = bslice(peer, 1088, 32)
          ss_pq = mlkem768_decaps(@mlkem_dk, ct_pq)
          ss_x = x25519_fast(@priv, peer_x)
          raise "TLS: all-zero X25519 shared secret" if x25519_is_zero(ss_x)
          shared = bcat(ss_pq, ss_x)
        elsif (@group == 0x0017 || @group == 0x0018) && @ec_group == @group && @ec_priv != nil
          shared = tls_ec_shared(@group, @ec_priv, peer)
        else
          raise "TLS: unexpected server key_share group 0x" + @group.to_s(16)
      o = o + 4 + el
    if version != 0x0304 && @quic_params == nil && (legacy_ver == 0x0303 || version == 0x0303) && (@cipher == 0xc02b || @cipher == 0xc02f || @cipher == 0xc02c || @cipher == 0xc030)
      @tls12 = true
      @server_random = rnd
      return false
    raise "TLS: server chose cipher 0x" + @cipher.to_s(16) if !valid_tls13_cipher?(@cipher)
    raise "TLS: server did not negotiate TLS 1.3" if version != 0x0304
    raise "TLS: PSK hash mismatch" if @resumed && suite_hash_len(@cipher) != @ticket.psk.size
    raise "TLS: no key share" if shared == nil
    @shared = shared
    false

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
    elsif @group == 0x0017 || @group == 0x0018
      kp = tls_ec_keygen(@group)
      @t12_client_pub = kp[1]
      @t12_pms = tls_ec_shared(@group, kp[0], spub)
    else
      raise "TLS: unsupported ECDHE named curve " + @group.to_s

  -> handshake_secrets
    hlen = suite_hash_len(@cipher)
    zero = ByteArray.new(hlen)
    early = @resumed ? @early : hkdf_extract_h(@cipher, ByteArray.new(0), zero)
    derived = derive_secret_h(@cipher, early, "derived", empty_hash_for(@cipher))
    @hs_secret = hkdf_extract_h(@cipher, derived, @shared)
    h = th()
    @c_hs = derive_secret_h(@cipher, @hs_secret, "c hs traffic", h)
    @s_hs = derive_secret_h(@cipher, @hs_secret, "s hs traffic", h)

  -> app_secrets
    hlen = suite_hash_len(@cipher)
    derived = derive_secret_h(@cipher, @hs_secret, "derived", empty_hash_for(@cipher))
    master = hkdf_extract_h(@cipher, derived, ByteArray.new(hlen))
    @master = master
    h = th()
    @c_ap = derive_secret_h(@cipher, master, "c ap traffic", h)
    @s_ap = derive_secret_h(@cipher, master, "s ap traffic", h)

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
    psk = hkdf_label_h(@cipher, @res_master, "resumption", nonce, suite_hash_len(@cipher))
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

  -> compressed_certificate(b)
    raise "TLS: short CompressedCertificate" if b.size < 8
    alg = bget16(b, 0)
    uncomp_len = bget24(b, 2)
    comp_len = bget24(b, 5)
    raise "TLS: invalid CompressedCertificate length" if uncomp_len <= 0 || uncomp_len > 262144 || 8 + comp_len != b.size
    comp = bslice(b, 8, comp_len)
    raw = nil
    if alg == 2
      raw = Brotli.decompress(comp)
    elsif alg == 1
      raw = Gzip.inflate_zlib(comp, 0, uncomp_len, true)
    else
      raise "TLS: unsupported certificate compression algorithm " + alg.to_s
    raise "TLS: CompressedCertificate decompressed size mismatch" if raw == nil || raw.size != uncomp_len
    @cert_compressed = alg
    certificate(raw)

  -> certificate(b)
    ctx = b[0]
    o = 1 + ctx
    total = bget24(b, o)
    o += 3
    e = o + total
    idx = 0
    while o + 3 <= e
      cl = bget24(b, o)
      o += 3
      @certs.push(bslice(b, o, cl))
      o += cl
      xl = bget16(b, o)
      xo = o + 2
      xe = xo + xl
      if idx == 0
        while xo + 4 <= xe && xo + 4 <= b.size
          xt = bget16(b, xo)
          xlen = bget16(b, xo + 2)
          xd = bslice(b, xo + 4, xlen)
          if xt == 5 && xlen >= 4 && xd[0] == 1
            olen = bget24(xd, 1)
            @ocsp_response = bslice(xd, 4, olen) if 4 + olen <= xlen
          elsif xt == 18
            @sct_list = xd
          xo = xo + 4 + xlen
      o = xe
      idx += 1
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
    @write_lock = Mutex.new
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
    cs = @tls.cipher
    [hkdf_label_h(cs, secret, "key", ByteArray.new(0), suite_key_len(cs)), hkdf_label_h(cs, secret, "iv", ByteArray.new(0), 12)]

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
      ct = aead_seal(@tls.cipher, @wkey, nonce(@wiv, @wseq), inner, hdr)
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
      pt = aead_open(@tls.cipher, @rkey, nonce(@riv, @rseq), body, @rhdr)
      raise "TLS: record authentication failed" if pt == nil
      @rseq += 1
      k = pt.size - 1
      while k >= 0 && pt[k] == 0
        k -= 1
      raise "TLS: empty inner plaintext" if k < 0
      return [pt[k], bslice(pt, 0, k)]
    raise "TLS: expected encrypted record" if @rkey != nil && !@tls.tls12 && !(type == 20 && @tls.state != :done)
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
        ch2 = @tls.take_hrr_ch2()
        if ch2 != nil
          write_record(22, ch2)
          next
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
            @write_secret = @tls.c_ap
            k = keys(@write_secret)
            @wkey = k[0]
            @wiv = k[1]
            @wseq = 0
            @read_secret = @tls.s_ap
            k = keys(@read_secret)
            @rkey = k[0]
            @riv = k[1]
            @rseq = 0
    @alpn = @tls.alpn

  # NewSessionTicket (and KeyUpdate) arrive as handshake records after the handshake.
  -> post_handshake(b)
    bappend(@hsbuf, b)
    while @hsbuf.size >= 4 && @hsbuf.size >= 4 + bget24(@hsbuf, 1)
      ml = 4 + bget24(@hsbuf, 1)
      if @hsbuf[0] == 24
        raise "TLS: invalid KeyUpdate" if @tls.tls12 || ml != 5 || @hsbuf[4] > 1 || ml != @hsbuf.size
        cs = @tls.cipher
        hlen = suite_hash_len(cs)
        @read_secret = hkdf_label_h(cs, @read_secret, "traffic upd", ByteArray.new(0), hlen)
        k = keys(@read_secret)
        @rkey = k[0]
        @riv = k[1]
        @rseq = 0
        if @hsbuf[4] == 1
          @write_lock.lock
          begin
            write_record(22, hs_msg(24, ByteArray.new(1)))
            @write_secret = hkdf_label_h(cs, @write_secret, "traffic upd", ByteArray.new(0), hlen)
            k = keys(@write_secret)
            @wkey = k[0]
            @wiv = k[1]
            @wseq = 0
          ensure
            @write_lock.unlock
      else
        @tls.feed(bslice(@hsbuf, 0, ml))
      @hsbuf = bslice(@hsbuf, ml, @hsbuf.size - ml)

  -> write(data)
    o = 0
    while o < data.size
      n = data.size - o
      n = 16000 if n > 16000
      @write_lock.lock
      begin
        write_record(23, bslice(data, o, n))
      ensure
        @write_lock.unlock
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
        raise "TLS: interleaved post-handshake message" if @hsbuf.size > 0
        return r[1] if r[1].size > 0
      elsif t == 21
        @closed = true
        return nil
      elsif t == 22
        post_handshake(r[1])
    nil

  -> close
    @write_lock.lock
    begin
      a = ByteArray.new(2)
      a[0] = 1
      a[1] = 0
      write_record(21, a)
    rescue e
      nil
    ensure
      @write_lock.unlock
    if @fd >= 0
      fd = @fd
      @fd = -1
      ccall_nobox("w_socket_close_fd", fd ## i64)
    elsif @sock != nil
      @sock.close
    nil
