# Crypto:PBKDF2 (core/crypto/pbkdf2.w): PBKDF2-HMAC-SHA256 against the
# published RFC 7914 §11 / RFC 6070-style vectors (password "password",
# salt "salt", c = 1, 2, 4096), the multi-block dklen = 40 vector, the
# embedded-NUL "pass\0word"/"sa\0lt" input (at c = 2; hashlib reference), truncation to dklen < 32,
# dklen = 33 (a second block cut to one byte), dklen = 64 (two whole
# blocks), empty password / empty salt, ByteArray inputs, and the
# bytes/hex parity. Iteration counts stay small so both engines finish
# quickly (spec/core/crypto_hmac_scram_spec.w already runs the published
# c = 4096 vectors; the interpreter spends ~10 ms per iteration).
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/crypto_pbkdf2_spec.w
#   bin/tungsten -o /tmp/crypto-pbkdf2-spec spec/core/crypto_pbkdf2_spec.w && /tmp/crypto-pbkdf2-spec

use core/crypto

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want.to_s
    exit 1

C1 = "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"

# --- c = 1: one HMAC per block ------------------------------------------------
check("pbkdf2.c1", Crypto:PBKDF2.sha256_hex("password", "salt", 1), C1)
# c = 1 is exactly HMAC-SHA256(password, salt || INT(1))
salt_int1 = u8[8]
salt_int1[0] = 0x73
salt_int1[1] = 0x61
salt_int1[2] = 0x6C
salt_int1[3] = 0x74
salt_int1[4] = 0
salt_int1[5] = 0
salt_int1[6] = 0
salt_int1[7] = 1
check("pbkdf2.c1.is_hmac", Crypto:HMAC.sha256_hex("password", salt_int1), C1)
check("pbkdf2.c2", Crypto:PBKDF2.sha256_hex("password", "salt", 2), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")

# --- truncation and multi-block derived keys ----------------------------------
check("pbkdf2.dklen20", Crypto:PBKDF2.sha256_hex("password", "salt", 1, 20), "120fb6cffcf8b32c43e7225256c4f837a86548c9")
check("pbkdf2.dklen20.is_prefix", Crypto:PBKDF2.sha256_hex("password", "salt", 1, 20), C1.slice(0, 40))
check("pbkdf2.dklen33", Crypto:PBKDF2.sha256_hex("password", "salt", 1, 33), C1 + "4d")
check("pbkdf2.dklen64", Crypto:PBKDF2.sha256_hex("password", "salt", 1, 64), C1 + "4dbf3a2f3dad3377264bb7b8e8330d4efc7451418617dabef683735361cdc18c")
check("pbkdf2.dklen64.first_block", Crypto:PBKDF2.sha256_hex("password", "salt", 1, 64).slice(0, 64), C1)
# the second block is HMAC(password, salt || INT(2))
salt_int2 = u8[8]
salt_int2[0] = 0x73
salt_int2[1] = 0x61
salt_int2[2] = 0x6C
salt_int2[3] = 0x74
salt_int2[4] = 0
salt_int2[5] = 0
salt_int2[6] = 0
salt_int2[7] = 2
check("pbkdf2.second_block.is_hmac", Crypto:PBKDF2.sha256_hex("password", "salt", 1, 64).slice(64, 64), Crypto:HMAC.sha256_hex("password", salt_int2))

# --- embedded NUL bytes (RFC 7914 §11 inputs at c = 2, dklen = 16; reference
#     value from Python hashlib.pbkdf2_hmac) ---------------------------------
pw = u8[9]
pw[0] = 0x70
pw[1] = 0x61
pw[2] = 0x73
pw[3] = 0x73
pw[4] = 0
pw[5] = 0x77
pw[6] = 0x6F
pw[7] = 0x72
pw[8] = 0x64
sa = u8[5]
sa[0] = 0x73
sa[1] = 0x61
sa[2] = 0
sa[3] = 0x6C
sa[4] = 0x74
check("pbkdf2.nul.c2.dklen16", Crypto:PBKDF2.sha256_hex(pw, sa, 2, 16), "aa4399833b716be66298125c3e643697")

# --- empty password / empty salt ---------------------------------------------
check("pbkdf2.empty_password", Crypto:PBKDF2.sha256_hex("", "salt", 1), "f135c27993baf98773c5cdb40a5706ce6a345cde61b000a67858650cd6a324d7")
check("pbkdf2.empty_salt", Crypto:PBKDF2.sha256_hex("password", "", 1), "c1232f10f62715fda06ae7c0a2037ca19b33cf103b727ba56d870c11f290a2ab")

# --- ByteArray inputs equal String inputs ------------------------------------
pw2 = u8[8]
pw2[0] = 0x70
pw2[1] = 0x61
pw2[2] = 0x73
pw2[3] = 0x73
pw2[4] = 0x77
pw2[5] = 0x6F
pw2[6] = 0x72
pw2[7] = 0x64
sa2 = u8[4]
sa2[0] = 0x73
sa2[1] = 0x61
sa2[2] = 0x6C
sa2[3] = 0x74
check("pbkdf2.bytes_inputs", Crypto:PBKDF2.sha256_hex(pw2, sa2, 2), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")

# --- raw bytes vs hex --------------------------------------------------------
raw = Crypto:PBKDF2.sha256("password", "salt", 1)
check("pbkdf2.bytes.size", raw.size, 32)
check("pbkdf2.bytes.byte0", raw[0], 0x12)
check("pbkdf2.bytes.byte31", raw[31], 0x7B)
check("pbkdf2.bytes.hex_roundtrip", Crypto:HMAC.__hex(raw), C1)
check("pbkdf2.bytes.dklen16.size", Crypto:PBKDF2.sha256("password", "salt", 1, 16).size, 16)
check("pbkdf2.bytes.dklen40.size", Crypto:PBKDF2.sha256("password", "salt", 1, 40).size, 40)

# --- facade parity: Crypto.pbkdf2_sha256 returns the raw derived key (bytes,
#     unlike the hex-returning Crypto.sha256/hmac_sha256 facades) ------------
facade = Crypto.pbkdf2_sha256("password", "salt", 2)
check("facade.pbkdf2_sha256.size", facade.size, 32)
check("facade.pbkdf2_sha256.hex", Crypto:HMAC.__hex(facade), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")

<< "crypto_pbkdf2_spec: all checks passed"
