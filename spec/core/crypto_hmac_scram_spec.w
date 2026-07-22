# HMAC-SHA-2 (RFC 4231), PBKDF2-HMAC-SHA256 (RFC 7914-era published
# vectors), and SCRAM-SHA-256 (RFC 7677 §3) conformance for
# core/crypto/{hmac,pbkdf2,scram}.w. Self-checking; exits nonzero on the
# first failure. Needs RUN_CORE_SPECS=1 in scripts/test-specs.sh.

-> fail_check(name, detail = "")
  << "FAIL: [name] [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

# --- HMAC RFC 4231 test case 1: key = 0x0b * 20, data "Hi There"
key1 = u8[20]
i = 0
while i < 20
  key1[i] = 0x0B
  i += 1
check("hmac-sha256 tc1", Crypto:HMAC.sha256_hex(key1, "Hi There"),
  "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
check("hmac-sha384 tc1", Crypto:HMAC.sha384_hex(key1, "Hi There"),
  "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6")
check("hmac-sha512 tc1", Crypto:HMAC.sha512_hex(key1, "Hi There"),
  "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854")

# --- RFC 4231 test case 2: string key/data ("Jefe")
check("hmac-sha256 tc2",
  Crypto:HMAC.sha256_hex("Jefe", "what do ya want for nothing?"),
  "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")

# --- RFC 4231 test case 6: key larger than the block (131 x 0xaa)
key6 = u8[131]
i = 0
while i < 131
  key6[i] = 0xAA
  i += 1
check("hmac-sha256 tc6 (long key)",
  Crypto:HMAC.sha256_hex(key6, "Test Using Larger Than Block-Size Key - Hash Key First"),
  "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")

# --- facade parity
check("facade hmac_sha256",
  Crypto.hmac_sha256("Jefe", "what do ya want for nothing?"),
  "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")

# --- PBKDF2-HMAC-SHA256 published vectors
check("pbkdf2 c=1", Crypto:PBKDF2.sha256_hex("password", "salt", 1),
  "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
check("pbkdf2 c=2", Crypto:PBKDF2.sha256_hex("password", "salt", 2),
  "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
check("pbkdf2 c=4096", Crypto:PBKDF2.sha256_hex("password", "salt", 4096),
  "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
# dklen > one block (40 bytes → two blocks, truncated)
check("pbkdf2 dklen=40",
  Crypto:PBKDF2.sha256_hex("passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 40),
  "348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9")

# --- SCRAM-SHA-256: RFC 7677 §3 vector, nonce injected
s = Crypto:ScramSha256.new("user", "pencil", "rOprNGfwEbeRWgbNEkqO")
check("scram client-first", s.client_first,
  "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
server_first = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
check("scram client-final", s.client_final(server_first),
  "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")
check("scram server-signature", s.server_signature,
  "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
check("scram verify good",
  s.verify_server_final("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="), true)
check("scram verify bad", s.verify_server_final("v=Zm9yZ2Vk"), false)
check("scram verify malformed", s.verify_server_final("e=other-error"), false)

# --- security checks raise
raised = false
begin
  bad = Crypto:ScramSha256.new("user", "pencil", "clientnonce")
  bad.client_final("r=DIFFERENTnonce,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096")
rescue e
  raised = true
check("scram nonce-mismatch raises", raised, true)

raised = false
begin
  bad2 = Crypto:ScramSha256.new("user", "pencil")
  bad2.client_final("garbage")
rescue e
  raised = true
check("scram malformed server-first raises", raised, true)

<< "crypto_hmac_scram_spec: all passed"
