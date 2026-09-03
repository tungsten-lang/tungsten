# Crypto:SHA256 (core/crypto/sha256.w): FIPS 180-4 known-answer vectors
# ("", "abc", the 448-bit two-block message, the 896-bit message, a million
# 'a'), messages straddling the 55/56/64-byte padding boundaries, the raw
# digest bytes, and the hex alias.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/crypto_sha256_spec.w
#   bin/tungsten -o /tmp/crypto-sha256-spec spec/core/crypto_sha256_spec.w && /tmp/crypto-sha256-spec

use core/crypto

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s
    exit 1

TWO = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
BIG = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"

check("sha256.empty", Crypto:SHA256.hexdigest(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256.abc", Crypto:SHA256.hexdigest("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256.two_block", Crypto:SHA256.hexdigest(TWO), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
check("sha256.big", Crypto:SHA256.hexdigest(BIG), "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
check("sha256.fox", Crypto:SHA256.hexdigest("The quick brown fox jumps over the lazy dog"), "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
check("sha256.hex.alias", Crypto:SHA256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

# padding boundaries: 55, 56, 63, 64 and 65 bytes of 'a'
# (values from Python hashlib; 55 bytes fits one block with padding,
#  56 forces a second block)
check("sha256.a55", Crypto:SHA256.hexdigest("a" * 55), "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
check("sha256.a56", Crypto:SHA256.hexdigest("a" * 56), "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
check("sha256.a63", Crypto:SHA256.hexdigest("a" * 63), "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34")
check("sha256.a64", Crypto:SHA256.hexdigest("a" * 64), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
check("sha256.a65", Crypto:SHA256.hexdigest("a" * 65), "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0")

# a million 'a' (FIPS 180-4 long-message vector)
check("sha256.million_a", Crypto:SHA256.hexdigest("a" * 1_000_000), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")

# digest: 32 raw bytes matching the hex
d = Crypto:SHA256.digest("abc")
check("sha256.digest.size", d.size, 32)
check("sha256.digest.byte0", d[0], 0xBA)
check("sha256.digest.byte1", d[1], 0x78)
check("sha256.digest.byte31", d[31], 0xAD)
check("sha256.digest.hex_roundtrip", Crypto:HMAC.__hex(d), Crypto:SHA256.hexdigest("abc"))
check("sha256.digest.empty.size", Crypto:SHA256.digest("").size, 32)

# facade parity
check("facade.sha256", Crypto.sha256("abc"), Crypto:SHA256.hexdigest("abc"))
check("facade.sha256_bytes", Crypto.sha256_bytes("abc")[0], 0xBA)

<< "crypto_sha256_spec: all checks passed"
