# TLS 1.3 cipher suites (AES-256-GCM, ChaCha20-Poly1305), GREASE, OCSP, SCT,
# and RFC 8879 CompressedCertificate (Brotli alg=2 + zlib alg=1) spec.

use core/crypto/bytes
use core/crypto/chacha
use core/crypto/curve25519
use core/crypto/mlkem
use core/net/psl
use core/crypto/x509
use core/brotli_dict
use core/brotli
use core/net/tls13

-> tls_check(name, cond)
  raise "FAIL " + name if !cond
  << "PASS " + name

# 1. AEAD round-trip for TLS_AES_256_GCM_SHA384 (0x1302) and TLS_CHACHA20_POLY1305_SHA256 (0x1303).
k256 = brand(32)
iv12 = brand(12)
aad  = bytes_of("\x17\x03\x03\x00\x25")
pt   = bytes_of("hello-tls13-ciphers-ok")

ct_aes256 = aead_seal(0x1302, k256, iv12, pt, aad)
dec_aes256 = aead_open(0x1302, k256, iv12, ct_aes256, aad)
tls_check("aead.aes256_gcm", beq(dec_aes256, pt))

ct_chacha = aead_seal(0x1303, k256, iv12, pt, aad)
dec_chacha = aead_open(0x1303, k256, iv12, ct_chacha, aad)
tls_check("aead.chacha20_poly1305", beq(dec_chacha, pt))

# 2. Build a synthetic TLS 1.3 Certificate payload with leaf OCSP (ext 5) + SCT (ext 18).
raw_cert = ByteArray.new(0)
raw_cert.push(0)           # certificate_request_context len = 0
bpush24(raw_cert, 24)      # certificate_list len = 24
bpush24(raw_cert, 4)       # cert_data len = 4
raw_cert.push(0x30); raw_cert.push(0x02); raw_cert.push(0x05); raw_cert.push(0x00)
bpush16(raw_cert, 15)      # extensions len = 15
# ext 5 (status_request / OCSP): status_type=1, len=2, [0xde, 0xad]
bpush16(raw_cert, 5)
bpush16(raw_cert, 6)
raw_cert.push(1)
bpush24(raw_cert, 2)
raw_cert.push(0xde); raw_cert.push(0xad)
# ext 18 (signed_certificate_timestamp): [0xbe]
bpush16(raw_cert, 18)
bpush16(raw_cert, 1)
raw_cert.push(0xbe)

# 3. RFC 8879 CompressedCertificate with Brotli (alg = 2, RFC 7932 uncompressed meta-block).
br_stream = ByteArray.new(0)
br_stream.push(0xb0)       # WBITS=16 (0), ISLAST=0 (0), MNIBBLES=4 (00), low nibble of (28-1=27) = 0xb
br_stream.push(0x01)       # next two nibbles of 27 = 0x01
br_stream.push(0x10)       # top nibble = 0, ISUNCOMPRESSED=1, pad=000
bappend(br_stream, raw_cert)
br_stream.push(0x03)       # ISLAST=1, ISLASTEMPTY=1

cc_br = ByteArray.new(0)
bpush16(cc_br, 2)          # brotli = 2
bpush24(cc_br, raw_cert.size)
bpush24(cc_br, br_stream.size)
bappend(cc_br, br_stream)

t_br = Tls13.new("example.com", ["h2"])
t_br.compressed_certificate(cc_br)
tls_check("cert_comp.brotli.alg", t_br.cert_compressed == 2)
tls_check("cert_comp.brotli.certs", t_br.certs.size == 1 && t_br.certs[0].size == 4)
tls_check("cert_comp.brotli.ocsp", t_br.ocsp_response != nil && t_br.ocsp_response.size == 2 && t_br.ocsp_response[0] == 0xde && t_br.ocsp_response[1] == 0xad)
tls_check("cert_comp.brotli.sct", t_br.sct_list != nil && t_br.sct_list.size == 1 && t_br.sct_list[0] == 0xbe)

# 4. RFC 8879 CompressedCertificate with zlib (alg = 1, RFC 1950 stored deflate + Adler-32).
zl_stream = ByteArray.new(0)
zl_stream.push(0x78); zl_stream.push(0x01) # CMF/FLG zlib header
zl_stream.push(0x01)                       # BFINAL=1, BTYPE=00 (stored)
nlen = raw_cert.size
zl_stream.push(nlen & 0xff); zl_stream.push((nlen >> 8) & 0xff)
inv = nlen ^ 0xffff
zl_stream.push(inv & 0xff); zl_stream.push((inv >> 8) & 0xff)
bappend(zl_stream, raw_cert)
s1 = 1
s2 = 0
i = 0
while i < raw_cert.size
  s1 = (s1 + raw_cert[i]) % 65521
  s2 = (s2 + s1) % 65521
  i += 1
bpush32(zl_stream, (s2 << 16) | s1)

cc_zl = ByteArray.new(0)
bpush16(cc_zl, 1)          # zlib = 1
bpush24(cc_zl, raw_cert.size)
bpush24(cc_zl, zl_stream.size)
bappend(cc_zl, zl_stream)

t_zl = Tls13.new("example.com", ["h2"])
t_zl.compressed_certificate(cc_zl)
tls_check("cert_comp.zlib.alg", t_zl.cert_compressed == 1)
tls_check("cert_comp.zlib.certs", t_zl.certs.size == 1 && t_zl.certs[0].size == 4)
tls_check("cert_comp.zlib.ocsp", t_zl.ocsp_response != nil && t_zl.ocsp_response[0] == 0xde)
tls_check("cert_comp.zlib.sct", t_zl.sct_list != nil && t_zl.sct_list[0] == 0xbe)
