# Auth-math conformance for the auth stack pgwire relies on. The HMAC /
# PBKDF2 / SCRAM implementations live in core (core/crypto/{hmac,pbkdf2,
# scram}.w — also covered by spec/core/crypto_hmac_scram_spec.w); this file
# pins the RFC vectors from the bit's side so the suite stays self-contained,
# plus the PG-specific md5 construction that remains in pgwire.w.
use tungsten-pg/pgwire

fails = 0

-> check(label, got, want)
  if got == want
    << "  ok  [label]"
    0
  else
    << "  FAIL [label]"
    << "    got  [got]"
    << "    want [want]"
    1

# 1. HMAC-SHA256 — RFC 4231 test case 1
key = u8[20]
i = 0
while i < 20
  key[i] = 0x0B
  i += 1
fails += check("hmac rfc4231 tc1", Crypto:HMAC.sha256_hex(key, "Hi There"),
  "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")

# 2. PBKDF2-HMAC-SHA256, 1 iteration
fails += check("pbkdf2 1-iter", Crypto:PBKDF2.sha256_hex("pw", "salt", 1),
  "6f4ad8c78ec365c060e648eb694ee40dea58484b0371fbd61715ac4410b7380a")

# 3. RFC 7677 salted password (4096 iterations)
salted = Crypto:PBKDF2.sha256("pencil", Base64.decode("W22ZaJ0SNY7soEsUEjb6gQ=="), 4096)
fails += check("pbkdf2 4096 (salted password)", Base64.encode(salted),
  "xKSVEDI6tPlSysH6mUQZOeeOp01r6B3fcJbodRPcYV0=")

# 4. Full SCRAM-SHA-256 — RFC 7677 vector (injected nonce)
s = Crypto:ScramSha256.new("user", "pencil", "rOprNGfwEbeRWgbNEkqO")
server_first = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
fails += check("scram client-first", s.client_first, "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
fails += check("scram client-final", s.client_final(server_first),
  "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")
fails += check("scram server-signature", s.server_signature,
  "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
verify_ok = s.verify_server_final("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
fails += check("scram verify", verify_ok, true)

# 5. md5 auth response construction (pgwire-side)
salt4 = u8[4]
salt4[0] = 1
salt4[1] = 2
salt4[2] = 3
salt4[3] = 4
fails += check("md5 auth", pgw_md5_auth("erik", "secret", salt4),
  "md5cdb5b20192ccd872a12c8056da0fb8d7")

if fails > 0
  << "scram_test: [fails] FAILED"
  exit(1)
<< "scram_test: all passed"
