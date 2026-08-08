in Crypto

# AES-GCM authenticated encryption (AEAD). Key length selects the cipher:
# 16 bytes → AES-128, 32 bytes → AES-256. The nonce MUST be 12 bytes and MUST
# be unique per key — reusing a (key, nonce) pair breaks confidentiality AND
# authenticity for GCM. `aad` is additional authenticated data: covered by the
# tag but not encrypted (pass "" if unused).
#
# gcm_encrypt returns ciphertext with the 16-byte authentication tag appended.
# gcm_decrypt verifies the tag in constant time and raises on any mismatch;
# it never returns unauthenticated plaintext.

+ AES
  -> .gcm_encrypt(key, nonce, plaintext, aad = "")
    ccall("w_crypto_aes_gcm_seal", key, nonce, plaintext, aad)

  -> .gcm_decrypt(key, nonce, sealed, aad = "")
    ccall("w_crypto_aes_gcm_open", key, nonce, sealed, aad)
