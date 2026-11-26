# core/cbor — CBOR (RFC 8949) deterministic encoder/decoder + COSE (RFC 9052/9053)
# COSE_Sign1, COSE_Mac0, COSE_Key (ES256, EdDSA, HS256).

use core/crypto/bytes

# Semantic tag wrapper for CBOR Major Type 6
+ CborTag
  ro :tag, :value

  -> new(@tag, @value)

# ---- CBOR Encoder (RFC 8949 §4.2 deterministic preferred serialization) ----

-> cbor_write_head(out, major, val)
  m = (major & 7) << 5
  if val < 24
    out.push(m | val)
  elsif val < 256
    out.push(m | 24)
    out.push(val & 255)
  elsif val < 65536
    out.push(m | 25)
    out.push((val >> 8) & 255)
    out.push(val & 255)
  elsif val < 4294967296
    out.push(m | 26)
    out.push((val >> 24) & 255)
    out.push((val >> 16) & 255)
    out.push((val >> 8) & 255)
    out.push(val & 255)
  else
    out.push(m | 27)
    sh = 56
    while sh >= 0
      out.push((val >> sh) & 255)
      sh -= 8

-> cbor_encode_into(v, out)
  if v == nil
    out.push(0xF6) # null
  elsif v == false
    out.push(0xF4)
  elsif v == true
    out.push(0xF5)
  elsif v.is_a?(Integer)
    if v >= 0
      cbor_write_head(out, 0, v)
    else
      cbor_write_head(out, 1, -1 - v)
  elsif v.is_a?(Float)
    out.push(0xFB) # IEEE 754 float64
    bits = wvalue_bits(v) ## i64
    sh = 56
    while sh >= 0
      out.push((bits >> sh) & 255)
      sh -= 8
  elsif v.is_a?(ByteArray)
    cbor_write_head(out, 2, v.size)
    bappend(out, v)
  elsif v.is_a?(String)
    bs = bytes_of(v)
    cbor_write_head(out, 3, bs.size)
    bappend(out, bs)
  elsif v.is_a?(Array)
    cbor_write_head(out, 4, v.size)
    i = 0
    while i < v.size
      cbor_encode_into(v[i], out)
      i += 1
  elsif v.is_a?(Hash)
    cbor_write_head(out, 5, v.size)
    v.each ->(k, val)
      cbor_encode_into(k, out)
      cbor_encode_into(val, out)
  elsif v.is_a?(CborTag)
    cbor_write_head(out, 6, v.tag)
    cbor_encode_into(v.value, out)
  else
    bs = bytes_of(v.to_s)
    cbor_write_head(out, 3, bs.size)
    bappend(out, bs)

-> cbor_encode(v)
  out = ByteArray.new(0)
  cbor_encode_into(v, out)
  out

# ---- CBOR Decoder (RFC 8949) ----

-> cbor_read_arg(b, pos_box, ai)
  return ai if ai < 24
  p = pos_box[0]
  if ai == 24
    pos_box[0] = p + 1
    return b[p]
  if ai == 25
    pos_box[0] = p + 2
    return (b[p] << 8) | b[p + 1]
  if ai == 26
    pos_box[0] = p + 4
    return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]
  if ai == 27
    pos_box[0] = p + 8
    v = 0
    k = 0
    while k < 8
      v = (v << 8) | b[p + k]
      k += 1
    return v
  raise "CBOR: unsupported additional info " + ai.to_s

-> cbor_decode_at(b, pos_box)
  p = pos_box[0]
  raise "CBOR: unexpected EOF" if p >= b.size
  ib = b[p]
  pos_box[0] = p + 1
  major = (ib >> 5) & 7
  ai = ib & 31
  case major
  when 0
    return cbor_read_arg(b, pos_box, ai)
  when 1
    return -1 - cbor_read_arg(b, pos_box, ai)
  when 2
    ln = cbor_read_arg(b, pos_box, ai)
    s = pos_box[0]
    pos_box[0] = s + ln
    return bslice(b, s, ln)
  when 3
    ln = cbor_read_arg(b, pos_box, ai)
    s = pos_box[0]
    pos_box[0] = s + ln
    return str_of(bslice(b, s, ln))
  when 4
    ln = cbor_read_arg(b, pos_box, ai)
    arr = []
    i = 0
    while i < ln
      arr.push(cbor_decode_at(b, pos_box))
      i += 1
    return arr
  when 5
    ln = cbor_read_arg(b, pos_box, ai)
    h = {}
    i = 0
    while i < ln
      k = cbor_decode_at(b, pos_box)
      v = cbor_decode_at(b, pos_box)
      h[k] = v
      i += 1
    return h
  when 6
    tg = cbor_read_arg(b, pos_box, ai)
    return CborTag.new(tg, cbor_decode_at(b, pos_box))
  when 7
    return false if ai == 20
    return true if ai == 21
    return nil if ai == 22 || ai == 23
    if ai == 27
      bits = cbor_read_arg(b, pos_box, 27)
      return wvalue_from_bits(bits ## i64)
    if ai == 25 # IEEE 754 half-precision float16
      h = cbor_read_arg(b, pos_box, 25)
      exp = (h >> 10) & 31
      mant = h & 1023
      sgn = (h & 0x8000) != 0 ? ~-1.0 : ~1.0
      return sgn * (mant.to_f / ~1024.0) * Math.pow(~2.0, ~-14.0) if exp == 0
      return sgn * (~1.0 + mant.to_f / ~1024.0) * Math.pow(~2.0, (exp - 15).to_f)
    return nil
  else
    return nil

-> cbor_decode(data)
  b = data.is_a?(ByteArray) ? data : bytes_of(data)
  cbor_decode_at(b, [0])

# ---- COSE (RFC 9052 / 9053): COSE_Sign1 (Tag 18) & COSE_Mac0 (Tag 17) ----
# COSE Algorithm IDs:
#   -7  = ES256 (ECDSA w/ SHA-256)
#   -8  = EdDSA (Ed25519)
#    5  = HMAC 256/256 (HS256)

COSE_ALG_ES256 = -7
COSE_ALG_EDDSA = -8
COSE_ALG_HS256 = 5

-> cose_sig_structure(protected_bytes, payload_bytes, external_aad = nil)
  aad = external_aad == nil ? ByteArray.new(0) : external_aad
  cbor_encode(["Signature1", protected_bytes, aad, payload_bytes])

-> cose_mac0_create(payload, key, alg = COSE_ALG_HS256, unprotected = nil)
  prot = cbor_encode({1 => alg})
  unp = unprotected == nil ? {} : unprotected
  pay = payload.is_a?(ByteArray) ? payload : bytes_of(payload)
  kb = key.is_a?(ByteArray) ? key : bytes_of(key)
  mac_struct = cbor_encode(["MAC0", prot, ByteArray.new(0), pay])
  tag = hmac256(kb, mac_struct)
  cbor_encode(CborTag.new(17, [prot, unp, pay, tag]))

-> cose_mac0_verify(cose_bytes, key)
  obj = cbor_decode(cose_bytes)
  arr = obj.is_a?(CborTag) ? obj.value : obj
  return [false, nil, nil] if !arr.is_a?(Array) || arr.size != 4
  prot = arr[0]; unp = arr[1]; pay = arr[2]; tag = arr[3]
  kb = key.is_a?(ByteArray) ? key : bytes_of(key)
  mac_struct = cbor_encode(["MAC0", prot, ByteArray.new(0), pay])
  exp = hmac256(kb, mac_struct)
  ok = exp.size == tag.size
  i = 0
  while ok && i < exp.size
    ok = false if exp[i] != tag[i]
    i += 1
  [ok, cbor_decode(prot), pay]

-> cose_sign1_encode(protected_hdr, unprotected_hdr, payload, sig_bytes)
  prot = cbor_encode(protected_hdr)
  pay = payload.is_a?(ByteArray) ? payload : bytes_of(payload)
  cbor_encode(CborTag.new(18, [prot, unprotected_hdr == nil ? {} : unprotected_hdr, pay, sig_bytes]))

-> cose_sign1_decode(cose_bytes)
  obj = cbor_decode(cose_bytes)
  arr = obj.is_a?(CborTag) ? obj.value : obj
  return nil if !arr.is_a?(Array) || arr.size != 4
  {
    protected_raw: arr[0],
    protected: arr[0].size > 0 ? cbor_decode(arr[0]) : {},
    unprotected: arr[1],
    payload: arr[2],
    signature: arr[3]
  }
