# blade/x509 — server certificate verification for TLS 1.3.
#
#   verify_server(certs, host, alg, sig, content)
#     certs: the server's chain (DER), leaf first. Checks the leaf names host
#     (subjectAltName, one-label wildcards), every certificate is within its
#     validity period, each is signed by the next (or by a trusted root), the
#     chain ends at a root in the macOS system store, and the CertificateVerify
#     signature over content was made by the leaf's key. Raises on any failure.
#
# DER parsing and the padding checks are here; the public-key arithmetic (ECDSA
# P-256/P-384, RSA PKCS#1 v1.5 / PSS) is blade/pkfast on raw u64 limbs. Keys stay
# as their big-endian bytes: no BigInt is made on the handshake path (Tungsten has
# no GC, and the old Integer maths retained ~100 MB per handshake). The trust
# anchors are read once from /System/Library/Keychains/SystemRootCertificates.keychain.

use core/crypto/pkfast

# ---- DER ----

# The TLV at b[o]: [tag, value offset, value length, end offset].
-> der(b, o)
  tag = b[o]
  l = b[o + 1]
  p = o + 2
  if l >= 128
    nb = l & 127
    l = 0
    k = 0
    while k < nb
      l = (l << 8) + b[p + k]
      k += 1
    p = p + nb
  [tag, p, l, p + l, o]

# Children of the constructed value at TLV t.
-> der_kids(b, t)
  out = []
  o = t[1]
  while o < t[3]
    c = der(b, o)
    out.push(c)
    o = c[3]
  out

-> der_bytes(b, t)
  bslice(b, t[1], t[2])

-> der_int(b, t)
  be_to_int(der_bytes(b, t))

OID_EC = "2a8648ce3d0201"
OID_P256 = "2a8648ce3d030107"
OID_P384 = "2b81040022"
OID_RSA = "2a864886f70d010101"
OID_ECDSA_SHA256 = "2a8648ce3d040302"
OID_ECDSA_SHA384 = "2a8648ce3d040303"
OID_ECDSA_SHA512 = "2a8648ce3d040304"
OID_RSA_SHA256 = "2a864886f70d01010b"
OID_RSA_SHA384 = "2a864886f70d01010c"
OID_RSA_SHA512 = "2a864886f70d01010d"
OID_SAN = "551d11"
OID_BASIC = "551d13"

+ Cert
  rw :raw, :tbs, :sig_alg, :sig, :issuer, :subject, :not_before, :not_after, :key_type, :curve, :ec_xb, :ec_yb, :rsa_nb, :rsa_eb, :names, :ca

  -> new(@raw)
    b = @raw
    top = der(b, 0)
    k = der_kids(b, top)
    @tbs = bslice(b, k[0][4], k[0][3] - k[0][4])
    @sig_alg = bhex(der_bytes(b, der_kids(b, k[1])[0]))
    sb = der_bytes(b, k[2])
    @sig = bslice(sb, 1, sb.size - 1)
    @names = []
    @ca = false
    @curve = nil
    @ec_xb = nil
    @ec_yb = nil
    @rsa_nb = nil
    @rsa_eb = nil
    t = der_kids(b, k[0])
    i = 0
    i = 1 if t[0][0] == 0xa0
    @issuer = whole(b, t[i + 2])
    v = der_kids(b, t[i + 3])
    @not_before = asn_time(b, v[0])
    @not_after = asn_time(b, v[1])
    @subject = whole(b, t[i + 4])
    spki = der_kids(b, t[i + 5])
    alg = der_kids(b, spki[0])
    kt = bhex(der_bytes(b, alg[0]))
    pk = der_bytes(b, spki[1])
    pk = bslice(pk, 1, pk.size - 1)
    if kt == OID_EC
      @key_type = :ec
      @curve = bhex(der_bytes(b, alg[1]))
      n = (pk.size - 1) / 2
      @ec_xb = bslice(pk, 1, n)
      @ec_yb = bslice(pk, 1 + n, n)
    elsif kt == OID_RSA
      @key_type = :rsa
      rk = der_kids(pk, der(pk, 0))
      @rsa_nb = der_bytes(pk, rk[0])
      @rsa_eb = der_bytes(pk, rk[1])
    else
      @key_type = :other
    j = i + 6
    while j < t.size
      if t[j][0] == 0xa3
        exts = der_kids(b, der(b, t[j][1]))
        exts.each ->(e)
          ek = der_kids(b, e)
          oid = bhex(der_bytes(b, ek[0]))
          val = ek.last
          if oid == OID_SAN
            vb = der_bytes(b, val)
            der_kids(vb, der(vb, 0)).each ->(g)
              @names.push(str_of(der_bytes(vb, g)).downcase) if g[0] == 0x82
              if g[0] == 0x87 && g[2] == 4
                ip = der_bytes(vb, g)
                @names.push(ip[0].to_s + "." + ip[1].to_s + "." + ip[2].to_s + "." + ip[3].to_s)
          elsif oid == OID_BASIC
            vb = der_bytes(b, val)
            kids = der_kids(vb, der(vb, 0))
            @ca = kids.size > 0 && kids[0][0] == 1 && vb[kids[0][1]] != 0
      j += 1

  # Integer views of the key, for display and SubtleCrypto (never on the handshake path).
  -> ec_x
    @ec_xb == nil ? nil : be_to_int(@ec_xb)

  -> ec_y
    @ec_yb == nil ? nil : be_to_int(@ec_yb)

  -> rsa_n
    @rsa_nb == nil ? nil : be_to_int(@rsa_nb)

  -> rsa_e
    @rsa_eb == nil ? nil : be_to_int(@rsa_eb)

  -> whole(b, t)
    bslice(b, t[4], t[3] - t[4])

  # "YYYYMMDDHHMMSS"
  -> asn_time(b, t)
    s = str_of(der_bytes(b, t))
    if t[0] == 0x17
      yy = s.slice(0, 2).to_i
      s = (yy < 50 ? "20" : "19") + s
    s.slice(0, 14)

  -> names_host?(host)
    h = host.downcase
    @names.each ->(n)
      return true if n == h
      if n.starts_with?("*.")
        dot = h.index(".")
        return true if dot != nil && dot > 0 && h.slice(dot, h.size - dot) == n.slice(1, n.size - 1)
    false


# ---- time ----

# The current UTC time as "YYYYMMDDHHMMSS" (civil-from-days, from the Unix epoch).
-> utc_stamp
  ms = Instant.now.unix_ms
  secs = ms / 1000
  days = secs / 86400
  rem = secs - days * 86400
  z = days + 719468
  era = (z >= 0 ? z : z - 146096) / 146097
  doe = z - era * 146097
  yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  y = yoe + era * 400
  doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  mp = (5 * doy + 2) / 153
  d = doy - (153 * mp + 2) / 5 + 1
  m = mp < 10 ? mp + 3 : mp - 9
  y += 1 if m <= 2
  hh = rem / 3600
  mm = (rem / 60) % 60
  ss = rem % 60
  y.to_s + two(m) + two(d) + two(hh) + two(mm) + two(ss)

-> two(n)
  n < 10 ? "0" + n.to_s : n.to_s


# ---- elliptic curves (short Weierstrass, a = -3) in Jacobian coordinates ----

+ EcCurve
  ro :p, :b, :gx, :gy, :n, :bits
  -> new(ph, bh, gxh, gyh, nh, @bits)
    @p = be_to_int(unhex(ph))
    @b = be_to_int(unhex(bh))
    @gx = be_to_int(unhex(gxh))
    @gy = be_to_int(unhex(gyh))
    @n = be_to_int(unhex(nh))

  -> on_curve?(x, y)
    p = @p
    (y * y - (x * x * x - 3 * x + @b)) % p == 0

  # Jacobian point [X, Y, Z]; Z == 0 is infinity.
  -> dbl(pt)
    p = @p
    x = pt[0]
    y = pt[1]
    z = pt[2]
    return pt if z == 0 || y == 0
    yy = (y * y) % p
    s = (4 * x * yy) % p
    zz = (z * z) % p
    m = (3 * (x - zz) * (x + zz)) % p
    x3 = (m * m - 2 * s) % p
    y3 = (m * (s - x3) - 8 * yy * yy) % p
    z3 = (2 * y * z) % p
    [x3 % p, y3 % p, z3 % p]

  -> add(a, c)
    return c if a[2] == 0
    return a if c[2] == 0
    p = @p
    z1z1 = (a[2] * a[2]) % p
    z2z2 = (c[2] * c[2]) % p
    u1 = (a[0] * z2z2) % p
    u2 = (c[0] * z1z1) % p
    s1 = (a[1] * c[2] * z2z2) % p
    s2 = (c[1] * a[2] * z1z1) % p
    if u1 == u2
      return s1 == s2 ? dbl(a) : [0 ## int, 1 ## int, 0 ## int]
    h = (u2 - u1) % p
    r = (s2 - s1) % p
    hh = (h * h) % p
    hhh = (h * hh) % p
    v = (u1 * hh) % p
    x3 = (r * r - hhh - 2 * v) % p
    y3 = (r * (v - x3) - s1 * hhh) % p
    z3 = (a[2] * c[2] * h) % p
    [x3 % p, y3 % p, z3 % p]

  -> mul(k, pt)
    acc = [0 ## int, 1 ## int, 0 ## int]
    i = k.bit_length - 1
    while i >= 0
      acc = dbl(acc)
      acc = add(acc, pt) if ((k >> i) & 1) == 1
      i -= 1
    acc

  -> affine_x(pt)
    return nil if pt[2] == 0
    zi = pt[2].pow(@p - 2, @p)
    (pt[0] * zi * zi) % @p

  # ECDSA verification of (r, s) over hash bytes h with public key (qx, qy), all Integers
  # (SubtleCrypto). The arithmetic runs on blade/pkfast limbs.
  -> verify(h, r, s, qx, qy)
    n = @n
    return false if r <= 0 || r >= n || s <= 0 || s >= n
    l = @bits / 8
    pk_ecdsa_verify(@bits, h, int_to_be(r, l), int_to_be(s, l), int_to_be(qx, l), int_to_be(qy, l))

  # The Integer reference implementation (kept for tests).
  -> verify_slow(h, r, s, qx, qy)
    n = @n
    return false if r <= 0 || r >= n || s <= 0 || s >= n
    return false if !on_curve?(qx, qy)
    e = be_to_int(h)
    hb = h.size * 8
    e = e >> (hb - @bits) if hb > @bits
    w = s.pow(n - 2, n)
    u1 = (e * w) % n
    u2 = (r * w) % n
    one = 1 ## int
    pt = add(mul(u1, [@gx, @gy, one]), mul(u2, [qx, qy, one]))
    x = affine_x(pt)
    return false if x == nil
    x % n == r

CURVES = {}

-> curve(oid)
  if CURVES.size == 0
    CURVES[OID_P256] = EcCurve.new("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff",
      "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b",
      "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296",
      "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5",
      "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 256)
    CURVES[OID_P384] = EcCurve.new("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff",
      "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef",
      "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7",
      "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f",
      "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973", 384)
  CURVES[oid]

# DER ECDSA-Sig-Value → [r bytes, s bytes] (big-endian, possibly with a leading 0).
-> ecdsa_sig(sig)
  t = der(sig, 0)
  k = der_kids(sig, t)
  [der_bytes(sig, k[0]), der_bytes(sig, k[1])]

-> curve_bits(oid)
  return 256 if oid == OID_P256
  return 384 if oid == OID_P384
  0

# ECDSA with a certificate's EC key: hash bytes, DER signature.
-> cert_ecdsa_ok?(c, hash, sig)
  bits = curve_bits(c.curve)
  return false if bits == 0 || c.ec_xb == nil
  rs = ecdsa_sig(sig)
  pk_ecdsa_verify(bits, hash, rs[0], rs[1], c.ec_xb, c.ec_yb)


# ---- RSA ----

-> hash_of(name, data)
  case name
  when "sha256"
    return Crypto.sha256_bytes(data)
  when "sha384"
    return Crypto.sha384_bytes(data)
  when "sha512"
    return Crypto.sha512_bytes(data)
  raise "x509: unknown hash " + name

DIGEST_INFO = {"sha256" => "3031300d060960864801650304020105000420", "sha384" => "3041300d060960864801650304020205000430",
  "sha512" => "3051300d060960864801650304020305000440"}

# n, e: big-endian modulus and exponent bytes. sig^e mod n, or nil when sig >= n.
-> rsa_em(n, e, sig)
  pk_rsa_public(n, e, sig)

# Bit length of a big-endian byte string.
-> bytes_bit_length(b)
  i = 0
  while i < b.size && b[i] == 0
    i += 1
  return 0 if i == b.size
  v = b[i]
  nb = 0
  while v > 0
    v = v >> 1
    nb += 1
  (b.size - i - 1) * 8 + nb

-> rsa_pkcs1_verify(n, e, hname, data, sig)
  em = rsa_em(n, e, sig)
  return false if em == nil
  t = bcat(unhex(DIGEST_INFO[hname]), hash_of(hname, data))
  k = em.size
  return false if k < t.size + 11
  return false if em[0] != 0 || em[1] != 1
  i = 2
  while i < k - t.size - 1
    return false if em[i] != 255
    i += 1
  return false if em[k - t.size - 1] != 0
  beq(bslice(em, k - t.size, t.size), t)

-> mgf1(hname, seed, len)
  out = ByteArray.new(0)
  c = 0
  while out.size < len
    cb = ByteArray.new(0)
    bpush32(cb, c)
    bappend(out, hash_of(hname, bcat(seed, cb)))
    c += 1
  bslice(out, 0, len)

-> rsa_pss_verify(n, e, hname, data, sig)
  em_full = rsa_em(n, e, sig)
  return false if em_full == nil
  mod_bits = bytes_bit_length(n)
  em_bits = mod_bits - 1
  em_len = (em_bits + 7) / 8
  em = bslice(em_full, em_full.size - em_len, em_len)
  mh = hash_of(hname, data)
  hlen = mh.size
  return false if em_len < 2 * hlen + 2 || em[em_len - 1] != 0xbc
  masked = bslice(em, 0, em_len - hlen - 1)
  h = bslice(em, em_len - hlen - 1, hlen)
  db = mgf1(hname, h, masked.size)
  i = 0
  while i < db.size
    db[i] = db[i] ^ masked[i]
    i += 1
  top = 8 * em_len - em_bits
  db[0] = db[0] & (255 >> top)
  ps = em_len - 2 * hlen - 2
  i = 0
  while i < ps
    return false if db[i] != 0
    i += 1
  return false if db[ps] != 1
  salt = bslice(db, ps + 1, hlen)
  mp = bcat(ByteArray.new(8), bcat(mh, salt))
  beq(hash_of(hname, mp), h)


# ---- verifying with a certificate's key ----

-> cert_sig_ok?(issuer, sig_alg, tbs, sig)
  case sig_alg
  when OID_ECDSA_SHA256, OID_ECDSA_SHA384, OID_ECDSA_SHA512
    return false if issuer.key_type != :ec
    hn = sig_alg == OID_ECDSA_SHA256 ? "sha256" : (sig_alg == OID_ECDSA_SHA384 ? "sha384" : "sha512")
    return cert_ecdsa_ok?(issuer, hash_of(hn, tbs), sig)
  when OID_RSA_SHA256, OID_RSA_SHA384, OID_RSA_SHA512
    return false if issuer.key_type != :rsa
    hn = sig_alg == OID_RSA_SHA256 ? "sha256" : (sig_alg == OID_RSA_SHA384 ? "sha384" : "sha512")
    return rsa_pkcs1_verify(issuer.rsa_nb, issuer.rsa_eb, hn, tbs, sig)
  false


# ---- trust anchors ----

ROOTS = [nil]
ROOTS_WARM = [false]
ROOTS_LOCK = Mutex.new

# Parsed once per process; the lock keeps concurrent first handshakes (preconnects)
# from each parsing the whole keychain.
-> trust_roots
  return ROOTS[0] if ROOTS[0] != nil
  ROOTS_LOCK.lock
  begin
    load_trust_roots() if ROOTS[0] == nil
  rescue err
    ROOTS_LOCK.unlock
    raise err
  ROOTS_LOCK.unlock
  ROOTS[0]

SYSTEM_ROOTS_KEYCHAIN = "/System/Library/Keychains/SystemRootCertificates.keychain"

# The system roots as PEM. Asking `security` costs ~0.75 s (and the first handshake waits on
# it), so the answer is cached in ~/Library/Caches/Blade, keyed by the keychain file's mtime
# and size: an OS update that changes the roots changes the key.
-> trust_roots_pem
  kc = SYSTEM_ROOTS_KEYCHAIN
  tag = File.exist?(kc) ? File.mtime_ns(kc).to_s + "-" + File.size(kc).to_s : "none"
  base = Env.get("HOME", "/tmp") + "/Library/Caches/Blade"
  path = base + "/trust-roots-" + tag + ".pem"
  begin
    if File.exist?(path)
      s = File.read(path)
      return s if s != nil && s.index("-----BEGIN CERTIFICATE-----") != nil
  rescue err
    nil
  pem = OS.capture("/usr/bin/security find-certificate -a -p " + kc)
  pem = "" if pem == nil
  if pem.index("-----BEGIN CERTIFICATE-----") != nil
    begin
      File.mkdir_p(base) if !Dir.exist?(base)
      File.write(path + ".tmp", pem)
      File.rename(path + ".tmp", path)
    rescue err
      nil
  pem

-> load_trust_roots
  if ROOTS[0] == nil
    by_subject = {}
    pem = trust_roots_pem()
    i = 0
    while true
      a = pem.index("-----BEGIN CERTIFICATE-----", i)
      break if a == nil
      e = pem.index("-----END CERTIFICATE-----", a)
      break if e == nil
      body = pem.slice(a + 27, e - a - 27).sub("\n", "")
      b64 = StringBuffer()
      k = 0
      while k < body.size
        c = body.byte_at(k)
        b64.append(body.slice(k, 1)) if c != 10 && c != 13 && c != 32
        k += 1
      begin
        d = Base64.decode(b64.to_s)
        d = bytes_of(d) if d.is_a?(String)
        c = Cert.new(d)
        key = bhex(c.subject)
        by_subject[key] = [] if !by_subject.has_key?(key)
        by_subject[key].push(c)
      rescue err
        nil
      i = e + 25
    ROOTS[0] = by_subject
  ROOTS[0]


-> verify_server(certs, host, alg, sig, content)
  chain = certs.map(->(d) Cert.new(d))
  leaf = chain[0]
  raise "certificate is not valid for " + host if !leaf.names_host?(host)
  now = utc_stamp()
  chain.each ->(c)
    raise "certificate has expired or is not yet valid" if now < c.not_before || now > c.not_after
  roots = trust_roots()
  raise "no system trust roots available" if roots.size == 0
  # walk up: each certificate must be signed by the next one or by a trusted root
  k = 0
  trusted = false
  while k < chain.size && !trusted
    c = chain[k]
    anchors = roots[bhex(c.issuer)]
    if anchors != nil
      anchors.each ->(r)
        if cert_sig_ok?(r, c.sig_alg, c.tbs, c.sig)
          trusted = true
          break
    break if trusted
    raise "certificate chain is incomplete (no issuer for certificate " + k.to_s + ")" if k + 1 >= chain.size
    nxt = chain[k + 1]
    raise "certificate chain is out of order" if !beq(nxt.subject, c.issuer)
    raise "intermediate certificate is not a CA" if !nxt.ca
    raise "certificate signature does not verify" if !cert_sig_ok?(nxt, c.sig_alg, c.tbs, c.sig)
    k += 1
  raise "certificate chain does not end at a trusted root" if !trusted
  # CertificateVerify: the leaf's key signed the handshake transcript
  ok = false
  case alg
  when 0x0403, 0x0503, 0x0603
    raise "CertificateVerify: key is not EC" if leaf.key_type != :ec
    raise "CertificateVerify: unsupported curve" if curve_bits(leaf.curve) == 0
    hn = alg == 0x0403 ? "sha256" : (alg == 0x0503 ? "sha384" : "sha512")
    ok = cert_ecdsa_ok?(leaf, hash_of(hn, content), sig)
  when 0x0804, 0x0805, 0x0806
    raise "CertificateVerify: key is not RSA" if leaf.key_type != :rsa
    hn = alg == 0x0804 ? "sha256" : (alg == 0x0805 ? "sha384" : "sha512")
    ok = rsa_pss_verify(leaf.rsa_nb, leaf.rsa_eb, hn, content, sig)
  when 0x0401, 0x0501, 0x0601
    raise "CertificateVerify: key is not RSA" if leaf.key_type != :rsa
    hn = alg == 0x0401 ? "sha256" : (alg == 0x0501 ? "sha384" : "sha512")
    ok = rsa_pkcs1_verify(leaf.rsa_nb, leaf.rsa_eb, hn, content, sig)
  else
    raise "CertificateVerify: unsupported signature scheme " + alg.to_s
  raise "CertificateVerify signature does not verify" if !ok
  true
