# Crypto:SHA2 facade (core/crypto/sha2.w): every SHA-2 variant selector
# (224, 256, 384, 512, "512/224", "512/256" and their aliases) against the
# FIPS 180-4 / NIST CAVP known-answer vectors for "", "abc", the 448-bit
# two-block message, and the 896-bit message. Byte digests are checked for
# length and leading bytes; unsupported selectors must raise.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/crypto_sha2_spec.w
#   bin/tungsten -o /tmp/crypto-sha2-spec spec/core/crypto_sha2_spec.w && /tmp/crypto-sha2-spec

use core/crypto

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s
    exit 1

TWO = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
BIG = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"

# --- SHA-224 --------------------------------------------------------------
check("sha224.empty", Crypto:SHA2.hexdigest("", 224), "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f")
check("sha224.abc", Crypto:SHA2.hexdigest("abc", 224), "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7")
check("sha224.two_block", Crypto:SHA2.hexdigest(TWO, 224), "75388b16512776cc5dba5da1fd890150b0c6455cb4f58b1952522525")
check("sha224.digest.size", Crypto:SHA2.digest("abc", 224).size, 28)
check("sha224.digest.byte0", Crypto:SHA2.digest("abc", 224)[0], 0x23)

# --- SHA-256 (default selector) -------------------------------------------
check("sha256.default.empty", Crypto:SHA2.hexdigest(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256.abc", Crypto:SHA2.hexdigest("abc", 256), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256.two_block", Crypto:SHA2.hexdigest(TWO, 256), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
check("sha256.big", Crypto:SHA2.hexdigest(BIG), "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
check("sha256.digest.size", Crypto:SHA2.digest("abc").size, 32)
check("sha256.digest.byte0", Crypto:SHA2.digest("abc")[0], 0xBA)
check("sha256.digest.byte31", Crypto:SHA2.digest("abc")[31], 0xAD)

# --- SHA-384 --------------------------------------------------------------
check("sha384.empty", Crypto:SHA2.hexdigest("", 384), "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b")
check("sha384.abc", Crypto:SHA2.hexdigest("abc", 384), "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
check("sha384.big", Crypto:SHA2.hexdigest(BIG, 384), "09330c33f71147e83d192fc782cd1b4753111b173b3b05d22fa08086e3b0f712fcc7c71a557e2db966c3e9fa91746039")
check("sha384.digest.size", Crypto:SHA2.digest("abc", 384).size, 48)

# --- SHA-512 --------------------------------------------------------------
check("sha512.empty", Crypto:SHA2.hexdigest("", 512), "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
check("sha512.abc", Crypto:SHA2.hexdigest("abc", 512), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
check("sha512.big", Crypto:SHA2.hexdigest(BIG, 512), "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909")
check("sha512.digest.size", Crypto:SHA2.digest("abc", 512).size, 64)
check("sha512.digest.byte0", Crypto:SHA2.digest("abc", 512)[0], 0xDD)

# --- SHA-512/224 and SHA-512/256 truncations (all selector spellings) ----
check("sha512_224.empty", Crypto:SHA2.hexdigest("", "512/224"), "6ed0dd02806fa89e25de060c19d3ac86cabb87d6a0ddd05c333b84f4")
check("sha512_224.abc", Crypto:SHA2.hexdigest("abc", "512/224"), "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa")
check("sha512_224.abc.dash", Crypto:SHA2.hexdigest("abc", "512-224"), "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa")
check("sha512_224.abc.symbol", Crypto:SHA2.hexdigest("abc", :sha512_224), "4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa")
check("sha512_224.big", Crypto:SHA2.hexdigest(BIG, "512/224"), "23fec5bb94d60b23308192640b0c453335d664734fe40e7268674af9")
check("sha512_224.digest.size", Crypto:SHA2.digest("abc", "512/224").size, 28)
check("sha512_256.empty", Crypto:SHA2.hexdigest("", "512/256"), "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a")
check("sha512_256.abc", Crypto:SHA2.hexdigest("abc", "512/256"), "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23")
check("sha512_256.abc.dash", Crypto:SHA2.hexdigest("abc", "512-256"), "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23")
check("sha512_256.abc.symbol", Crypto:SHA2.hexdigest("abc", :sha512_256), "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23")
check("sha512_256.big", Crypto:SHA2.hexdigest(BIG, "512/256"), "3928e184fb8690f840da3988121d31be65cb9d3ef83ee6146feac861e19b563a")
check("sha512_256.digest.size", Crypto:SHA2.digest("abc", "512/256").size, 32)

# --- hex alias and facade parity -------------------------------------------
check("hex.alias", Crypto:SHA2.hex("abc", 384), Crypto:SHA2.hexdigest("abc", 384))
check("facade.sha2.default", Crypto.sha2("abc"), Crypto:SHA2.hexdigest("abc", 256))
check("facade.sha2.512", Crypto.sha2("abc", 512), Crypto:SHA2.hexdigest("abc", 512))
check("facade.sha224", Crypto.sha224("abc"), Crypto:SHA2.hexdigest("abc", 224))
check("facade.sha512_256", Crypto.sha512_256("abc"), Crypto:SHA2.hexdigest("abc", "512/256"))

# --- unsupported variants raise --------------------------------------------
raised = false
begin
  Crypto:SHA2.hexdigest("abc", 160)
rescue e
  raised = true
check("unsupported.bits.raises", raised, true)
raised = false
begin
  Crypto:SHA2.digest("abc", "512/512")
rescue e
  raised = true
check("unsupported.truncation.raises", raised, true)

<< "crypto_sha2_spec: all checks passed"
