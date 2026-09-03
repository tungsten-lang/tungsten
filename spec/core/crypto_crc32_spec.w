# Crypto:CRC32 (core/crypto/crc32.w): the IEEE 802.3 polynomial (zlib/gzip/
# PNG) and the Castagnoli polynomial (iSCSI/ext4) against the canonical
# "123456789" check values (CRC-32 = 0xCBF43926, CRC-32C = 0xE3069283) and
# other zlib/RFC-reference inputs; both the checksum/castagnoli names and
# the crc32c alias; ByteArray input parity with String input.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/crypto_crc32_spec.w
#   bin/tungsten -o /tmp/crypto-crc32-spec spec/core/crypto_crc32_spec.w && /tmp/crypto-crc32-spec

use core/crypto

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s
    exit 1

FOX = "The quick brown fox jumps over the lazy dog"

# --- CRC-32 (IEEE) -----------------------------------------------------------
check("crc32.check_value", Crypto:CRC32.checksum("123456789"), 0xCBF43926)
check("crc32.check_value.decimal", Crypto:CRC32.checksum("123456789"), 3421780262)
check("crc32.empty", Crypto:CRC32.checksum(""), 0)
check("crc32.a", Crypto:CRC32.checksum("a"), 0xE8B7BE43)
check("crc32.abc", Crypto:CRC32.checksum("abc"), 0x352441C2)
check("crc32.fox", Crypto:CRC32.checksum(FOX), 0x414FA339)
# result is an unsigned 32-bit Int
check("crc32.nonnegative", Crypto:CRC32.checksum(FOX) >= 0, true)
check("crc32.fits_u32", Crypto:CRC32.checksum(FOX) < 4294967296, true)

# --- CRC-32C (Castagnoli) -----------------------------------------------------
check("crc32c.check_value", Crypto:CRC32.castagnoli("123456789"), 0xE3069283)
check("crc32c.check_value.decimal", Crypto:CRC32.castagnoli("123456789"), 3808858755)
check("crc32c.empty", Crypto:CRC32.castagnoli(""), 0)
check("crc32c.a", Crypto:CRC32.castagnoli("a"), 0xC1D04330)
check("crc32c.abc", Crypto:CRC32.castagnoli("abc"), 0x364B3FB7)
check("crc32c.fox", Crypto:CRC32.castagnoli(FOX), 0x22620404)
check("crc32c.alias", Crypto:CRC32.crc32c("123456789"), Crypto:CRC32.castagnoli("123456789"))
# the two polynomials differ on every non-empty input here
check("crc32.vs.crc32c", Crypto:CRC32.checksum("abc") != Crypto:CRC32.castagnoli("abc"), true)

# --- ByteArray input matches String input -----------------------------------
digits = u8[9]
i = 0
while i < 9
  digits[i] = 0x31 + i
  i += 1
check("crc32.bytes", Crypto:CRC32.checksum(digits), 0xCBF43926)
check("crc32c.bytes", Crypto:CRC32.castagnoli(digits), 0xE3069283)

# --- facade parity ----------------------------------------------------------
check("facade.crc32", Crypto.crc32("123456789"), 0xCBF43926)
check("facade.crc32c", Crypto.crc32c("123456789"), 0xE3069283)

<< "crypto_crc32_spec: all checks passed"
