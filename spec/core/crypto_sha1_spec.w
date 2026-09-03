# Crypto:SHA1 (core/crypto/sha1.w): FIPS 180-4 known-answer vectors for "",
# "abc", the 448-bit two-block message and the 896-bit message; the digest
# byte form; the hex alias; and base64digest (the WebSocket-accept / UUIDv5
# use case). SHA-1 prints a one-time deprecation notice on stderr unless
# TUNGSTEN_SHA1_OK=1 is set; that notice does not affect the digests.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/crypto_sha1_spec.w
#   bin/tungsten -o /tmp/crypto-sha1-spec spec/core/crypto_sha1_spec.w && /tmp/crypto-sha1-spec

use core/crypto

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s
    exit 1

TWO = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
BIG = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"

check("sha1.empty", Crypto:SHA1.hexdigest(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
check("sha1.abc", Crypto:SHA1.hexdigest("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
check("sha1.two_block", Crypto:SHA1.hexdigest(TWO), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
check("sha1.big", Crypto:SHA1.hexdigest(BIG), "a49b2446a02c645bf419f995b67091253a04a259")
check("sha1.fox", Crypto:SHA1.hexdigest("The quick brown fox jumps over the lazy dog"), "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
check("sha1.hex.alias", Crypto:SHA1.hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")

# digest: 20 raw bytes
d = Crypto:SHA1.digest("abc")
check("sha1.digest.size", d.size, 20)
check("sha1.digest.byte0", d[0], 0xA9)
check("sha1.digest.byte1", d[1], 0x99)
check("sha1.digest.byte19", d[19], 0x9D)
check("sha1.digest.empty.size", Crypto:SHA1.digest("").size, 20)

# base64digest: standard base64 of the 20 raw bytes (28 chars, "=" padded)
check("sha1.base64.abc", Crypto:SHA1.base64digest("abc"), "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=")
check("sha1.base64.empty", Crypto:SHA1.base64digest(""), "2jmj7l5rSw0yVb/vlWAYkK/YBwk=")
# RFC 6455 §1.3 WebSocket accept: base64(SHA-1(key + GUID))
ws = "dGhlIHNhbXBsZSBub25jZQ==" + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
check("sha1.websocket_accept", Crypto:SHA1.base64digest(ws), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

# a million 'a' (FIPS 180-4 long-message vector)
million = "a" * 1_000_000
check("sha1.million_a", Crypto:SHA1.hexdigest(million), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")

# facade parity
check("facade.sha1", Crypto.sha1("abc"), Crypto:SHA1.hexdigest("abc"))
check("facade.sha1_base64", Crypto.sha1_base64("abc"), Crypto:SHA1.base64digest("abc"))

<< "crypto_sha1_spec: all checks passed"
