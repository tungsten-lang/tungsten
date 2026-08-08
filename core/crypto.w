# Crypto - secure random bytes and digest algorithms.
#
# Algorithm implementations live in core/crypto/*.w. This top-level class is
# the convenience namespace people reach for first; Digest remains the
# compatibility facade for hash-only code.

use core/crypto/md5
use core/crypto/sha1
use core/crypto/sha2
use core/crypto/sha224
use core/crypto/sha256
use core/crypto/sha384
use core/crypto/sha512
use core/crypto/sha3
use core/crypto/shake
use core/crypto/crc32
use core/crypto/aes
use core/crypto/hmac
use core/crypto/pbkdf2
use core/crypto/scram

+ Crypto

  -> .random_bytes(length)
    ccall("w_crypto_random_bytes", length)

  -> .md5(data)
    Crypto:MD5.hexdigest(data)

  -> .md5_bytes(data)
    Crypto:MD5.digest(data)

  -> .hmac_sha256(key, data)
    Crypto:HMAC.sha256_hex(key, data)

  -> .hmac_sha256_bytes(key, data)
    Crypto:HMAC.sha256(key, data)

  -> .pbkdf2_sha256(password, salt, iterations, dklen = 32)
    Crypto:PBKDF2.sha256(password, salt, iterations, dklen)

  -> .sha1(data)
    Crypto:SHA1.hexdigest(data)

  -> .sha1_bytes(data)
    Crypto:SHA1.digest(data)

  -> .sha1_base64(data)
    Crypto:SHA1.base64digest(data)

  -> .sha224(data)
    Crypto:SHA224.hexdigest(data)

  -> .sha224_bytes(data)
    Crypto:SHA224.digest(data)

  -> .sha256(data)
    Crypto:SHA256.hexdigest(data)

  -> .sha256_bytes(data)
    Crypto:SHA256.digest(data)

  -> .sha384(data)
    Crypto:SHA384.hexdigest(data)

  -> .sha384_bytes(data)
    Crypto:SHA384.digest(data)

  -> .sha512(data)
    Crypto:SHA512.hexdigest(data)

  -> .sha512_bytes(data)
    Crypto:SHA512.digest(data)

  -> .sha512_224(data)
    Crypto:SHA2.hexdigest(data, "512/224")

  -> .sha512_224_bytes(data)
    Crypto:SHA2.digest(data, "512/224")

  -> .sha512_256(data)
    Crypto:SHA2.hexdigest(data, "512/256")

  -> .sha512_256_bytes(data)
    Crypto:SHA2.digest(data, "512/256")

  -> .sha2(data, bits = 256)
    Crypto:SHA2.hexdigest(data, bits)

  -> .sha2_bytes(data, bits = 256)
    Crypto:SHA2.digest(data, bits)

  -> .sha3(data, bits = 256)
    Crypto:SHA3.hexdigest(data, bits)

  -> .sha3_bytes(data, bits = 256)
    Crypto:SHA3.digest(data, bits)

  -> .shake128(data, outlen)
    Crypto:SHAKE.shake128(data, outlen)

  -> .shake256(data, outlen)
    Crypto:SHAKE.shake256(data, outlen)

  -> .crc32(data)
    Crypto:CRC32.checksum(data)

  -> .crc32c(data)
    Crypto:CRC32.castagnoli(data)

  -> .aes_gcm_encrypt(key, nonce, plaintext, aad = "")
    Crypto:AES.gcm_encrypt(key, nonce, plaintext, aad)

  -> .aes_gcm_decrypt(key, nonce, sealed, aad = "")
    Crypto:AES.gcm_decrypt(key, nonce, sealed, aad)
