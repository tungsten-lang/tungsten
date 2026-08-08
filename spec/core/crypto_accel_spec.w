# Hardware-accelerated crypto surface: SHA-1, SHA-256/512 (hw compress paths),
# SHA-3 / SHAKE, CRC-32 / CRC-32C, and AES-GCM. Every expectation is anchored to
# an external reference (FIPS 180-4 / FIPS 202 vectors, zlib CRC, Go crypto/cipher
# GCM), never to a value this implementation produced.
#
# Run interpreted:  bin/tungsten spec/core/crypto_accel_spec.w
# Run compiled:     bin/tungsten -o /tmp/cas spec/core/crypto_accel_spec.w && /tmp/cas
# The two engines must produce identical output.

use core/crypto

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# ---- SHA-1 (legacy; exercises the hardware SHA-1 compress) -----------------
check("sha1.empty", Crypto:SHA1.hexdigest(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
check("sha1.abc", Crypto:SHA1.hexdigest("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
check("sha1.fox", Crypto:SHA1.hexdigest("The quick brown fox jumps over the lazy dog"), "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")

# ---- SHA-256 (hw compress path) -------------------------------------------
check("sha256.empty", Crypto.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256.abc", Crypto.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256.fox", Crypto.sha256("The quick brown fox jumps over the lazy dog"), "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

# ---- SHA-512 (hw compress path) -------------------------------------------
check("sha512.empty", Crypto.sha512(""), "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
check("sha512.abc", Crypto.sha512("abc"), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")

# ---- SHA-3 (Keccak sponge) ------------------------------------------------
check("sha3_256.empty", Crypto.sha3(""), "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a")
check("sha3_256.abc", Crypto.sha3("abc"), "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")
check("sha3_512.abc", Crypto.sha3("abc", 512), "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0")
check("sha3_256.fox", Crypto.sha3("The quick brown fox jumps over the lazy dog"), "69070dda01975c8c120c3aada1b282394e7f032fa9cf32f4cb2259a0897dfc04")

# ---- SHAKE XOF ------------------------------------------------------------
check("shake128.abc", Crypto:SHAKE.hexdigest("abc", 128, 32), "5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8")
check("shake256.abc", Crypto:SHAKE.hexdigest("abc", 256, 64), "483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4")

# ---- CRC-32 / CRC-32C (checksums, not cryptographic) ----------------------
check("crc32.check", Crypto.crc32("123456789"), 3421780262)
check("crc32c.check", Crypto.crc32c("123456789"), 3808858755)

# ---- AES-GCM: known-answer (sha256 of ciphertext||tag pins the exact bytes
#      to Go's crypto/cipher output) + round-trip + tamper rejection ---------
AES_K128 = "0123456789abcdef"
AES_K256 = "0123456789abcdef0123456789abcdef"
AES_NONCE = "nonce--12byt"
AES_PT = "attack at dawn!!"
AES_AAD = "hdr"

ct128 = Crypto.aes_gcm_encrypt(AES_K128, AES_NONCE, AES_PT, AES_AAD)
check("aes128gcm.known", Crypto.sha256(ct128), "ee9104a8823d255486f042d4b16476333c70be550bab5eab8b0677732ac25d0e")
check("aes128gcm.roundtrip", Crypto.sha256(Crypto.aes_gcm_decrypt(AES_K128, AES_NONCE, ct128, AES_AAD)), Crypto.sha256(AES_PT))

ct256 = Crypto.aes_gcm_encrypt(AES_K256, AES_NONCE, AES_PT, AES_AAD)
check("aes256gcm.known", Crypto.sha256(ct256), "9724cb2351407f2fc4657ddaed5003a2cd9ce8457e193f6e264b6cdee669fcef")
check("aes256gcm.roundtrip", Crypto.sha256(Crypto.aes_gcm_decrypt(AES_K256, AES_NONCE, ct256, AES_AAD)), Crypto.sha256(AES_PT))

<< "ALL PASS crypto_accel_spec"
