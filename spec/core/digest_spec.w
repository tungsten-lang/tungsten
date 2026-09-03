# Digest — the cryptographic-hash facade (core/digest.w).
#
# Every method here is a one-line delegation to a Crypto:* algorithm class. The
# non-cryptographic `bytes64/file64/string64` intrinsics of the same class are
# covered by spec/core/digest64_spec.w and are not repeated here.
#
# Expected values are the published NIST/RFC vectors for "abc" and "".
#
# Run:
#   bin/tungsten run --interpret spec/core/digest_spec.w
#   bin/tungsten -o /tmp/digest_spec spec/core/digest_spec.w && /tmp/digest_spec

use core/digest

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- MD5 (RFC 1321 test suite) ----
check("md5 of abc", Digest.md5("abc") == "900150983cd24fb0d6963f7d28e17f72")
check("md5 of the empty string", Digest.md5("") == "d41d8cd98f00b204e9800998ecf8427e")
check("md5_bytes is an array", type(Digest.md5_bytes("abc")) == "Array")
check("md5_bytes is 16 bytes", Digest.md5_bytes("abc").size == 16)
check("md5_bytes first byte matches the hex", Digest.md5_bytes("abc")[0] == 0x90)

# ---- SHA-1 (FIPS 180) ----
check("sha1 of abc", Digest.sha1("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
check("sha1_bytes is 20 bytes", Digest.sha1_bytes("abc").size == 20)
check("sha1_base64", Digest.sha1_base64("abc") == "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=")

# ---- SHA-2 family ----
check("sha224 of abc",
      Digest.sha224("abc") == "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7")
check("sha224_bytes is 28 bytes", Digest.sha224_bytes("abc").size == 28)
check("sha256 of abc",
      Digest.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256 of the empty string",
      Digest.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256_bytes is 32 bytes", Digest.sha256_bytes("abc").size == 32)
check("sha256_bytes matches the hex",
      Digest.sha256_bytes("abc")[0] == 0xba && Digest.sha256_bytes("abc")[31] == 0xad)
check("sha384 of abc",
      Digest.sha384("abc") ==
      "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
check("sha384_bytes is 48 bytes", Digest.sha384_bytes("abc").size == 48)
check("sha512 of abc",
      Digest.sha512("abc") ==
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
check("sha512_bytes is 64 bytes", Digest.sha512_bytes("abc").size == 64)
check("sha512_224 of abc",
      Digest.sha512_224("abc") == "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa")
check("sha512_224_bytes is 28 bytes", Digest.sha512_224_bytes("abc").size == 28)
check("sha512_256 of abc",
      Digest.sha512_256("abc") == "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23")
check("sha512_256_bytes is 32 bytes", Digest.sha512_256_bytes("abc").size == 32)

# ---- sha2(data, bits) dispatches by width, defaulting to 256 ----
check("sha2 defaults to 256", Digest.sha2("abc") == Digest.sha256("abc"))
check("sha2 224", Digest.sha2("abc", 224) == Digest.sha224("abc"))
check("sha2 384", Digest.sha2("abc", 384) == Digest.sha384("abc"))
check("sha2 512", Digest.sha2("abc", 512) == Digest.sha512("abc"))
check("sha2 512/224", Digest.sha2("abc", "512/224") == Digest.sha512_224("abc"))
check("sha2 512/256", Digest.sha2("abc", "512/256") == Digest.sha512_256("abc"))
check("sha2_bytes defaults to 256", Digest.sha2_bytes("abc").size == 32)
check("sha2_bytes 512", Digest.sha2_bytes("abc", 512).size == 64)

# ---- SHA-3 (Keccak, FIPS 202) ----
check("sha3 defaults to 256",
      Digest.sha3("abc") == "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")
check("sha3 224",
      Digest.sha3("abc", 224) == "e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf")
check("sha3 384",
      Digest.sha3("abc", 384) ==
      "ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25")
check("sha3 512",
      Digest.sha3("abc", 512) ==
      "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0")
check("sha3 differs from sha2 at the same width", Digest.sha3("abc") != Digest.sha256("abc"))
check("sha3_bytes defaults to 32 bytes", Digest.sha3_bytes("abc").size == 32)
check("sha3_bytes 512", Digest.sha3_bytes("abc", 512).size == 64)

# ---- CRC-32 checksums ----
check("crc32 of abc", Digest.crc32("abc") == 0x352441C2)
check("crc32 of the empty string", Digest.crc32("") == 0)
check("crc32c of abc", Digest.crc32c("abc") == 0x364B3FB7)
check("crc32c of the empty string", Digest.crc32c("") == 0)
check("crc32 and crc32c use different polynomials", Digest.crc32("abc") != Digest.crc32c("abc"))

# ---- every digest is a pure function of its input ----
check("md5 is deterministic", Digest.md5("hello") == Digest.md5("hello"))
check("sha256 discriminates", Digest.sha256("hello") != Digest.sha256("hellp"))
check("hexdigest length is bits/4",
      Digest.sha256("x").size == 64 && Digest.sha512("x").size == 128 && Digest.md5("x").size == 32)

<< "ALL PASS digest_spec ([passed.load()] checks)"
