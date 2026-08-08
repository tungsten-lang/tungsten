in Crypto

# CRC-32 checksums. NOT cryptographic: these detect accidental corruption
# (storage, transmission, framing) and are trivially forgeable by an adversary.
# For integrity against tampering use an HMAC or an AEAD such as AES-GCM.
#
#   CRC32       IEEE 802.3 polynomial (zlib/gzip/PNG).
#   CRC32C      Castagnoli polynomial (iSCSI, ext4, many storage formats);
#               has a hardware instruction and better error detection.
# Both return an unsigned 32-bit checksum as an Int.

+ CRC32
  -> .checksum(data)
    ccall("w_crypto_crc32", data)

  -> .castagnoli(data)
    ccall("w_crypto_crc32c", data)

  -> .crc32c(data)
    ccall("w_crypto_crc32c", data)
