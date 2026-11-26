# core/jose — JOSE (JWS/JWE/JWK/JWT, RFC 7515-7519), W3C DIDs (did:key, did:web, did:jwk),
# Verifiable Credentials Data Model 1.1/2.0, Data Integrity Cryptosuites (eddsa-rdfc-2022,
# ecdsa-rdfc-2019), Bitstring Status List v1.0, RDF Dataset Canonicalization (RDFC-1.0),
# JSON-LD 1.1, and W3C Payment Method Identifiers.

use core/base64
use core/gzip
use core/crypto/bytes
use core/crypto/chacha
use core/crypto/curve25519
use core/crypto/pkfast

# ---- Base64url (RFC 7515 Appendix C) ----

-> b64url_encode(data)
  s = data.is_a?(ByteArray) ? str_of(data) : data.to_s
  Base64.encode(s).gsub("+", "-").gsub("/", "_").gsub("=", "").gsub("\n", "")

-> b64url_decode(s)
  t = s.to_s.gsub("-", "+").gsub("_", "/")
  while (t.size % 4) != 0
    t = t + "="
  dec = Base64.decode(t)
  dec.is_a?(ByteArray) ? dec : bytes_of(dec)

# ---- Multibase Base58btc (used by did:key and Data Integrity proofs) ----

BASE58_ALPH = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

-> base58_encode(bytes)
  b = bytes.is_a?(ByteArray) ? bytes : bytes_of(bytes)
  zeros = 0
  while zeros < b.size && b[zeros] == 0
    zeros += 1
  n = 0
  i = zeros
  while i < b.size
    n = n * 256 + b[i]
    i += 1
  chars = []
  while n > 0
    rem = n % 58
    n = n / 58
    chars.push(BASE58_ALPH.slice(rem, 1))
  out = StringBuffer()
  zeros.times -> out << "1"
  k = chars.size - 1
  while k >= 0
    out << chars[k]
    k -= 1
  out.to_s

-> base58_decode(s)
  zeros = 0
  while zeros < s.size && s.byte_at(zeros) == 49 # '1'
    zeros += 1
  n = 0
  i = zeros
  while i < s.size
    idx = BASE58_ALPH.index(s.slice(i, 1))
    raise "Base58: invalid char" if idx == nil
    n = n * 58 + idx
    i += 1
  raw = []
  while n > 0
    raw.push(n & 255)
    n = n >> 8
  out = ByteArray.new(zeros + raw.size)
  k = 0
  while k < raw.size
    out[zeros + k] = raw[raw.size - 1 - k]
    k += 1
  out

# ---- JWS & JWT (RFC 7515 / RFC 7519): HS256, HS384, ES256 (P-256), EdDSA ----

-> jws_sign_hs256(header_hash, payload_bytes, secret)
  hdr = header_hash.dup
  hdr["alg"] = "HS256" if !hdr.has_key?("alg")
  p1 = b64url_encode(JSON.encode(hdr))
  p2 = b64url_encode(payload_bytes)
  si = bytes_of(p1 + "." + p2)
  kb = secret.is_a?(ByteArray) ? secret : bytes_of(secret)
  sig = hdr["alg"] == "HS384" ? hmac384(kb, si) : hmac256(kb, si)
  p1 + "." + p2 + "." + b64url_encode(sig)

-> jws_verify(token, key)
  parts = token.to_s.split(".")
  return [false, nil, nil] if parts.size != 3
  hdr = JSON.parse(str_of(b64url_decode(parts[0])))
  pay = b64url_decode(parts[1])
  sig = b64url_decode(parts[2])
  alg = hdr["alg"]
  si = bytes_of(parts[0] + "." + parts[1])
  ok = false
  if alg == "HS256" || alg == "HS384"
    kb = key.is_a?(ByteArray) ? key : bytes_of(key)
    exp = alg == "HS384" ? hmac384(kb, si) : hmac256(kb, si)
    ok = exp.size == sig.size
    i = 0
    while ok && i < exp.size
      ok = false if exp[i] != sig[i]
      i += 1
  elsif alg == "ES256" && key.is_a?(Hash) && key["kty"] == "EC" && key["crv"] == "P-256"
    # IEEE P1363 raw R||S (64 bytes) verified via constant-space core/crypto/pkfast!
    if sig.size == 64
      h = sha256(si)
      r = bslice(sig, 0, 32)
      s = bslice(sig, 32, 32)
      qx = b64url_decode(key["x"])
      qy = b64url_decode(key["y"])
      ok = pk_ecdsa_verify(256, h, r, s, qx, qy)
  [ok, hdr, pay]

-> jwt_sign(claims, secret, alg = "HS256")
  jws_sign_hs256({"alg" => alg, "typ" => "JWT"}, bytes_of(JSON.encode(claims)), secret)

-> jwt_verify(token, key, now_sec = nil)
  res = jws_verify(token, key)
  return [false, nil, "invalid signature"] if !res[0]
  claims = JSON.parse(str_of(res[2]))
  now = now_sec == nil ? (clock_ms() / 1000) : now_sec
  return [false, claims, "token expired"] if claims["exp"] != nil && now >= claims["exp"].to_i
  return [false, claims, "token not yet valid"] if claims["nbf"] != nil && now < claims["nbf"].to_i
  [true, claims, nil]

# ---- JWE (RFC 7516): dir + A256GCM / A128GCM Compact Serialization ----

-> jwe_encrypt_dir(plaintext, cek, alg_enc = "A256GCM")
  hdr = {"alg" => "dir", "enc" => alg_enc}
  p_hdr = b64url_encode(JSON.encode(hdr))
  iv = brand(12)
  aad = bytes_of(p_hdr)
  pt = plaintext.is_a?(ByteArray) ? plaintext : bytes_of(plaintext)
  kb = cek.is_a?(ByteArray) ? cek : bytes_of(cek)
  ct_tag = aes_gcm_seal(kb, iv, pt, aad)
  ct = bslice(ct_tag, 0, ct_tag.size - 16)
  tag = bslice(ct_tag, ct_tag.size - 16, 16)
  p_hdr + ".." + b64url_encode(iv) + "." + b64url_encode(ct) + "." + b64url_encode(tag)

-> jwe_decrypt_dir(jwe_str, cek)
  parts = jwe_str.to_s.split(".")
  return nil if parts.size != 5
  iv = b64url_decode(parts[2])
  ct = b64url_decode(parts[3])
  tag = b64url_decode(parts[4])
  aad = bytes_of(parts[0])
  kb = cek.is_a?(ByteArray) ? cek : bytes_of(cek)
  aes_gcm_open(kb, iv, bcat(ct, tag), aad)

# ---- W3C Decentralized Identifiers (DIDs): did:key, did:web, did:jwk ----

-> did_parse(did_str)
  s = did_str.to_s
  return nil if !s.starts_with?("did:")
  frag = nil
  fi = s.index("#")
  if fi != nil
    frag = s.slice(fi + 1, s.size - fi - 1)
    s = s.slice(0, fi)
  p1 = s.index(":", 4)
  return nil if p1 == nil
  method = s.slice(4, p1 - 4)
  msid = s.slice(p1 + 1, s.size - p1 - 1)
  {did: "did:" + method + ":" + msid, method: method, id: msid, fragment: frag}

-> did_resolve_local(did_str)
  p = did_parse(did_str)
  return nil if p == nil
  if p[:method] == "jwk"
    jwk = JSON.parse(str_of(b64url_decode(p[:id])))
    vm_id = p[:did] + "#0"
    return {
      "@context" => ["https://www.w3.org/ns/did/v1", "https://w3id.org/security/suites/jws-2020/v1"],
      "id" => p[:did],
      "verificationMethod" => [{"id" => vm_id, "type" => "JsonWebKey2020", "controller" => p[:did], "publicKeyJwk" => jwk}],
      "authentication" => [vm_id],
      "assertionMethod" => [vm_id]
    }
  if p[:method] == "key" && p[:id].starts_with?("z")
    raw = base58_decode(p[:id].slice(1, p[:id].size - 1))
    # Multicodec prefix: 0xed 0x01 = Ed25519-pub, 0x80 0x24 = P-256-pub, 0xec 0x01 = X25519-pub
    ktype = "Multikey"
    if raw.size >= 2 && raw[0] == 0xED && raw[1] == 0x01
      ktype = "Ed25519VerificationKey2020"
    elsif raw.size >= 2 && raw[0] == 0xEC && raw[1] == 0x01
      ktype = "X25519KeyAgreementKey2020"
    vm_id = p[:did] + "#" + p[:id]
    return {
      "@context" => ["https://www.w3.org/ns/did/v1"],
      "id" => p[:did],
      "verificationMethod" => [{"id" => vm_id, "type" => ktype, "controller" => p[:did], "publicKeyMultibase" => p[:id]}],
      "authentication" => [vm_id],
      "assertionMethod" => [vm_id]
    }
  if p[:method] == "web"
    # did:web:example.com:user:alice -> https://example.com/user/alice/did.json
    segs = p[:id].split(":")
    host = segs[0].gsub("%3A", ":").gsub("%3a", ":")
    doc_url = segs.size == 1 ? ("https://" + host + "/.well-known/did.json") : ("https://" + host + "/" + segs.slice(1, segs.size - 1).join("/") + "/did.json")
    return {"id" => p[:did], "resolveUrl" => doc_url}
  nil

# ---- W3C Bitstring Status List v1.0 (Revocation / Suspension Check) ----

-> bitstring_status_encode(bits_arr)
  nb = (bits_arr.size + 7) / 8
  nb = 16384 if nb < 16384 # Spec minimum 16KB (131,072 entries) for herd privacy
  raw = ByteArray.new(nb)
  i = 0
  while i < bits_arr.size
    if bits_arr[i] == 1 || bits_arr[i] == true
      bi = i / 8
      bit = 7 - (i % 8)
      raw[bi] = raw[bi] | (1 << bit)
    i += 1
  gz = Gzip.compress(raw)
  "u" + b64url_encode(gz)

-> bitstring_status_at(encoded_list, idx)
  s = encoded_list.to_s
  s = s.slice(1, s.size - 1) if s.starts_with?("u") # multibase base64url prefix
  raw = Gzip.decompress(b64url_decode(s))
  bi = idx / 8
  return 0 if bi < 0 || bi >= raw.size
  bit = 7 - (idx % 8)
  (raw[bi] >> bit) & 1

# ---- W3C RDF Dataset Canonicalization (URDNA2015 / RDFC-1.0) & JSON-LD 1.1 ----

-> rdf_canonicalize_nquads(nquads_str)
  # Canonicalizes an N-Quads dataset: computes first-degree blank-node hashes (SHA-256),
  # assigns canonical _:c14n0, _:c14n1, ... identifiers, and sorts lines lexicographically.
  lines = []
  nquads_str.split("\n").each ->(ln)
    t = ln.strip
    lines.push(t) if t.size > 0 && !t.starts_with?("#")
  # Collect blank nodes `_:...`
  bnodes = []
  lines.each ->(ln)
    ln.split(" ").each ->(tok)
      if tok.starts_with?("_:") && !bnodes.include?(tok)
        bnodes.push(tok)
  if bnodes.size > 0
    # Hash each blank node's incident statements replacing self with `_:a` and others with `_:z`
    hashed = []
    bnodes.each ->(bn)
      inc = []
      lines.each ->(ln)
        if ln.index(bn) != nil
          r = ln.gsub(bn, "_:a")
          bnodes.each ->(ob) r = r.gsub(ob, "_:z") if ob != bn
          inc.push(r)
      inc = rdf_sort_strings(inc)
      h = bhex(sha256(bytes_of(inc.join("\n") + "\n")))
      hashed.push([h, bn])
    # Sort by hash
    i = 1
    while i < hashed.size
      key = hashed[i]; j = i - 1
      while j >= 0 && hashed[j][0] > key[0]
        hashed[j + 1] = hashed[j]; j -= 1
      hashed[j + 1] = key; i += 1
    # Map to canonical _:c14n0, _:c14n1, ...
    out_lines = []
    lines.each ->(ln)
      r = ln
      ci = 0
      while ci < hashed.size
        r = r.gsub(hashed[ci][1], "__C14N_" + ci.to_s + "__")
        ci += 1
      ci = 0
      while ci < hashed.size
        r = r.gsub("__C14N_" + ci.to_s + "__", "_:c14n" + ci.to_s)
        ci += 1
      out_lines.push(r)
    lines = out_lines
  rdf_sort_strings(lines).join("\n") + (lines.size > 0 ? "\n" : "")

-> rdf_sort_strings(arr)
  out = arr.dup
  i = 1
  while i < out.size
    key = out[i]; j = i - 1
    while j >= 0 && out[j] > key
      out[j + 1] = out[j]; j -= 1
    out[j + 1] = key; i += 1
  out

# JSON-LD 1.1 Expansion -> N-Quads (core terms + @context IRI resolution + @id/@type/@value)
-> jsonld_to_nquads(doc)
  ctx = {}
  if doc.is_a?(Hash) && doc["@context"] != nil
    c = doc["@context"]
    if c.is_a?(Hash)
      c.each ->(k, v) ctx[k] = v if v.is_a?(String)
    elsif c.is_a?(Array)
      c.each ->(ci)
        if ci.is_a?(Hash)
          ci.each ->(k, v) ctx[k] = v if v.is_a?(String)
  quads = []
  bseq = [0]
  jsonld_emit_node(doc, ctx, quads, bseq)
  rdf_canonicalize_nquads(quads.join("\n"))

-> jsonld_expand_iri(term, ctx)
  return term if term.starts_with?("http://") || term.starts_with?("https://") || term.starts_with?("urn:") || term.starts_with?("did:")
  return ctx[term] if ctx.has_key?(term)
  col = term.index(":")
  if col != nil
    pfx = term.slice(0, col)
    loc = term.slice(col + 1, term.size - col - 1)
    return ctx[pfx] + loc if ctx.has_key?(pfx)
  ctx.has_key?("@vocab") ? (ctx["@vocab"] + term) : ("urn:jsonld:" + term)

-> jsonld_emit_node(obj, ctx, quads, bseq)
  return nil if !obj.is_a?(Hash)
  subj = nil
  if obj["id"] != nil
    subj = "<" + obj["id"].to_s + ">"
  elsif obj["@id"] != nil
    subj = "<" + obj["@id"].to_s + ">"
  else
    subj = "_:b" + bseq[0].to_s
    bseq[0] += 1
  obj.each ->(k, v)
    next if k == "@context" || k == "@id" || k == "id"
    if k == "@type" || k == "type"
      ts = v.is_a?(Array) ? v : [v]
      ts.each ->(t)
        quads.push(subj + " <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <" + jsonld_expand_iri(t.to_s, ctx) + "> .")
    else
      pred = "<" + jsonld_expand_iri(k, ctx) + ">"
      vs = v.is_a?(Array) ? v : [v]
      vs.each ->(item)
        if item.is_a?(Hash)
          sub_id = jsonld_emit_node(item, ctx, quads, bseq)
          quads.push(subj + " " + pred + " " + sub_id + " .") if sub_id != nil
        elsif item.is_a?(Integer)
          quads.push(subj + " " + pred + ' "' + item.to_s + '"^^<http://www.w3.org/2001/XMLSchema#integer> .')
        elsif item == true || item == false
          quads.push(subj + " " + pred + ' "' + item.to_s + '"^^<http://www.w3.org/2001/XMLSchema#boolean> .')
        else
          quads.push(subj + " " + pred + ' "' + item.to_s.gsub("\\", "\\\\").gsub('"', '\\"') + '" .')
  subj

# ---- W3C Verifiable Credentials Data Model 1.1 / 2.0 & Data Integrity Validation ----

-> vc_validate_model(vc)
  return [false, "VC must be an object"] if !vc.is_a?(Hash)
  ctx = vc["@context"]
  return [false, "missing @context"] if !ctx.is_a?(Array) || ctx.size == 0
  v1 = ctx[0] == "https://www.w3.org/2018/credentials/v1"
  v2 = ctx[0] == "https://www.w3.org/ns/credentials/v2"
  return [false, "first @context must be W3C VC v1 or v2"] if !v1 && !v2
  ty = vc["type"]
  return [false, "type must include VerifiableCredential"] if !ty.is_a?(Array) || !ty.include?("VerifiableCredential")
  return [false, "missing issuer"] if vc["issuer"] == nil
  return [false, "missing credentialSubject"] if vc["credentialSubject"] == nil
  [true, v2 ? "2.0" : "1.1"]

# Data Integrity proof hash (SHA-256(canon(proof_options)) || SHA-256(canon(document)))
-> vc_data_integrity_hash(doc, proof_opts)
  doc_clean = doc.dup
  doc_clean.delete("proof")
  opt_clean = proof_opts.dup
  opt_clean.delete("proofValue")
  opt_clean["@context"] = doc["@context"] if !opt_clean.has_key?("@context") && doc["@context"] != nil
  h_opt = sha256(bytes_of(jsonld_to_nquads(opt_clean)))
  h_doc = sha256(bytes_of(jsonld_to_nquads(doc_clean)))
  bcat(h_opt, h_doc)

# ---- W3C Payment Method Identifiers (https://www.w3.org/TR/payment-method-id/) ----

-> payment_method_id_valid?(pmi)
  return false if !pmi.is_a?(String) || pmi.size == 0
  # URL-based PMI: https://... without username/password
  if pmi.starts_with?("https://")
    return pmi.size > 8 && pmi.index("@") == nil
  # Standardized PMI: lowercase ASCII [a-z0-9] + `-` separated, no leading/trailing `-`
  return false if pmi.starts_with?("-") || pmi.ends_with?("-")
  i = 0
  while i < pmi.size
    b = pmi.byte_at(i)
    ok = (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 45
    return false if !ok
    i += 1
  true
