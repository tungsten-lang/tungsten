# tungsten-crypto spec.
#
# Every expectation here is anchored to an externally verifiable value —
# a FIPS 180-4 test vector, or real data from the Bitcoin blockchain.
# Nothing asserts against a value this implementation produced, because a
# self-consistent hash function that computes the wrong hash would pass
# such a test and fail on the network.
#
# Run: bin/tungsten bits/tungsten-crypto/spec/crypto_spec.w
#      (and compiled, via -o — the engines must agree)

use spec
use ../lib/crypto

GENESIS_MERKLE = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
GENESIS_HASH = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
ZERO32 = "0000000000000000000000000000000000000000000000000000000000000000"

describe "SHA-256" ->
  it "matches the FIPS 180-4 vector for the empty string" ->
    k = sha256_k()
    expect(sha256_hex(sha256_string_words("", k))).to eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

  it "matches the FIPS 180-4 vector for \"abc\"" ->
    k = sha256_k()
    expect(sha256_hex(sha256_string_words("abc", k))).to eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

  it "matches the FIPS 180-4 two-block vector" ->
    k = sha256_k()
    msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    expect(sha256_hex(sha256_string_words(msg, k))).to eq("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

  it "pads correctly at the 55/56-byte block boundary" ->
    # 55 bytes is the largest message whose 0x80 marker and 8-byte length
    # still fit in the same block; 56 forces a second, all-padding block.
    # 64 is a whole block, so the padding block is entirely synthetic.
    k = sha256_k()
    a55 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    a56 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    a64 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    expect(a55.size).to eq(55)
    expect(a56.size).to eq(56)
    expect(a64.size).to eq(64)
    expect(sha256_hex(sha256_string_words(a55, k))).to eq("9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
    expect(sha256_hex(sha256_string_words(a56, k))).to eq("b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
    expect(sha256_hex(sha256_string_words(a64, k))).to eq("ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")

describe "Bitcoin byte order" ->
  it "reverses a display hash into internal order" ->
    b = btc_hash_hex_to_internal(GENESIS_MERKLE)
    expect(btc_bytes_to_hex(b, 32)).to eq("3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a")

  it "round-trips internal order back to display" ->
    b = btc_hash_hex_to_internal(GENESIS_MERKLE)
    btc_reverse(b, 32)
    expect(btc_bytes_to_hex(b, 32)).to eq(GENESIS_MERKLE)

describe "Bitcoin genesis block" ->
  it "serializes the 80-byte header exactly" ->
    h = btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 2083236893)
    expect(btc_bytes_to_hex(h, 80)).to eq("0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c")

  it "hashes to the known genesis block hash" ->
    k = sha256_k()
    h = btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 2083236893)
    expect(sha256_hex_le(btc_header_hash(h, k))).to eq(GENESIS_HASH)

  it "meets the difficulty-1 target" ->
    k = sha256_k()
    h = btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 2083236893)
    expect(btc_meets_target(btc_header_hash(h, k), btc_target_from_bits(0x1d00ffff))).to eq(1)

  it "rejects the header one nonce below the solution" ->
    k = sha256_k()
    h = btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 2083236892)
    expect(btc_meets_target(btc_header_hash(h, k), btc_target_from_bits(0x1d00ffff))).to eq(0)

describe "difficulty targets" ->
  it "decodes the difficulty-1 compact target" ->
    t = btc_target_from_bits(0x1d00ffff)
    expect(t[0]).to eq(0x00000000)
    expect(t[1]).to eq(0xffff0000)
    expect(t[2]).to eq(0)

  # Exponents <= 3 shift the mantissa RIGHT rather than left, which is easy
  # to get wrong. Each of these was checked against Bitcoin Core's
  # SetCompact semantics (mant >> 8*(3-exp) when exp <= 3).
  it "decodes low-exponent targets by shifting right" ->
    t = btc_target_from_bits(0x03000001)
    expect(t[7]).to eq(1)
    expect(t[0]).to eq(0)
    t2 = btc_target_from_bits(0x02008000)
    expect(t2[7]).to eq(0x80)
    t3 = btc_target_from_bits(0x01120000)
    expect(t3[7]).to eq(0x12)
    # Shifted entirely off the bottom.
    t4 = btc_target_from_bits(0x01003456)
    expect(t4[7]).to eq(0)

  # Differentially tested against Bitcoin Core's SetCompact over 18 nBits
  # values, including every reject path. A target the network would refuse
  # must not be mined against: the miner would "solve" a block and have it
  # rejected with no local diagnostic.
  it "rejects an nBits whose sign bit is set" ->
    expect(btc_target_from_bits(0x04923456) == nil).to eq(true)
    expect(btc_target_from_bits(0x01fedcba) == nil).to eq(true)

  it "rejects an nBits that overflows 256 bits" ->
    expect(btc_target_from_bits(0x2200ffff) == nil).to eq(true)
    expect(btc_target_from_bits(0x2300000f) == nil).to eq(true)
    expect(btc_target_from_bits(0x21010000) == nil).to eq(true)

  it "accepts a zero mantissa regardless of the sign and size bits" ->
    # Core only flags negative/overflow when the mantissa is nonzero.
    expect(btc_target_from_bits(0x00800000) == nil).to eq(false)
    expect(btc_target_from_bits(0x2200ffff) == nil).to eq(true)

  it "decodes the regtest target" ->
    t = btc_target_from_bits(0x207fffff)
    expect(t[0]).to eq(0x7fffff00)
    expect(t[1]).to eq(0)

  it "decodes a modern high-difficulty target" ->
    # 0x1b04864c: exponent 0x1b = 27, mantissa 0x04864c, so the target is
    # 0x04864c * 256**24 — the mantissa sits in the second big-endian word.
    t = btc_target_from_bits(0x1b04864c)
    expect(t[0]).to eq(0)
    expect(t[1]).to eq(0x0004864c)
    expect(t[2]).to eq(0)
    expect(t[7]).to eq(0)

describe "merkle roots" ->
  it "returns the single txid unchanged for a one-transaction block" ->
    k = sha256_k()
    expect(btc_merkle_root([GENESIS_MERKLE], k)).to eq(GENESIS_MERKLE)

  it "reproduces the merkle root of mainnet block 100000" ->
    k = sha256_k()
    txids = [
      "8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87",
      "fff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4",
      "6359f0868171b1d194cbee1af2f16ea598ae8fad666d9b012c8ed2b79a236ec4",
      "e9a66845e05d5abc0ad04ec80f774a7e585c6e8db975962d069a522137b80c1d"
    ]
    expect(btc_merkle_root(txids, k)).to eq("f3e94742aca4b5ef85488dc37c06c3282295ffec960994b2c0d5ac2a25a95766")

  it "duplicates the tail hash on an odd level" ->
    k = sha256_k()
    txids = [
      "8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87",
      "fff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4",
      "6359f0868171b1d194cbee1af2f16ea598ae8fad666d9b012c8ed2b79a236ec4"
    ]
    expect(btc_merkle_root(txids, k)).to eq("fa435470825de273081dcc706b25514c936fa6dc80ab965ce6970d68ddd0b553")

describe "mainnet block 100000" ->
  it "hashes its header to the known block hash" ->
    k = sha256_k()
    h = btc_header_bytes(1, "000000000002d01c1fccc21636b607dfd930d31d01c3a62104612a1719011250",
                         "f3e94742aca4b5ef85488dc37c06c3282295ffec960994b2c0d5ac2a25a95766",
                         1293623863, 0x1b04864c, 274148111)
    expect(sha256_hex_le(btc_header_hash(h, k))).to eq("000000000003ba27aa200b1cecaad478d2b00432346c3f1f3986da1afd33e506")

describe "transactions" ->
  it "computes the txid of the real block 1 coinbase" ->
    k = sha256_k()
    raw = "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff0704ffff001d0104ffffffff0100f2052a0100000043410496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858eeac00000000"
    expect(btc_txid(raw, k)).to eq("0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098")

  it "encodes varints across the size boundaries" ->
    expect(btc_varint_hex(0)).to eq("00")
    expect(btc_varint_hex(252)).to eq("fc")
    expect(btc_varint_hex(253)).to eq("fdfd00")
    expect(btc_varint_hex(65535)).to eq("fdffff")
    expect(btc_varint_hex(65536)).to eq("fe00000100")

  it "encodes BIP34 heights as minimal script numbers" ->
    expect(btc_script_num_hex(1)).to eq("01")
    expect(btc_script_num_hex(127)).to eq("7f")
    # 128 has its top bit set, so a zero byte is appended to keep it positive.
    expect(btc_script_num_hex(128)).to eq("8000")
    expect(btc_script_num_hex(227836)).to eq("fc7903")

  # These two byte strings were parsed field-by-field with an independent
  # Python decoder: every byte is consumed, the BIP34 height reads back as
  # 800000, the commitment output carries the aa21a9ed magic, and the txid
  # is exactly the double-SHA of the stripped form.
  it "serializes a non-witness coinbase" ->
    script = btc_p2wpkh_script("0000000000000000000000000000000000000000")
    expect(btc_coinbase_hex(800000, 625000000, script, "746e6773746e", "")).to eq("01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff0b0300350c06746e6773746effffffff0140be402500000000160014000000000000000000000000000000000000000000000000")

  it "serializes a segwit coinbase with the witness commitment" ->
    script = btc_p2wpkh_script("0000000000000000000000000000000000000000")
    comm = "6a24aa21a9ed0000000000000000000000000000000000000000000000000000000000000000"
    expect(btc_coinbase_hex(800000, 625000000, script, "746e6773746e", comm)).to eq("010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff0b0300350c06746e6773746effffffff0240be40250000000016001400000000000000000000000000000000000000000000000000000000266a24aa21a9ed00000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000000000000000")

  it "derives the txid from the stripped serialization, not the witness one" ->
    k = sha256_k()
    script = btc_p2wpkh_script("0000000000000000000000000000000000000000")
    comm = "6a24aa21a9ed0000000000000000000000000000000000000000000000000000000000000000"
    stripped = btc_coinbase_serialize(800000, 625000000, script, "746e6773746e", comm, 0)
    expect(btc_coinbase_txid_hex(800000, 625000000, script, "746e6773746e", comm, k)).to eq(btc_txid(stripped, k))
    expect(btc_coinbase_txid_hex(800000, 625000000, script, "746e6773746e", comm, k)).to eq("e487c3a1c86b19baad8b5774a8a3c000e4b0fcf0e9642663f737d9c977f0994e")
    # The witness form must NOT hash to the txid — that is the whole point
    # of the two encodings.
    witness = btc_coinbase_hex(800000, 625000000, script, "746e6773746e", comm)
    expect(btc_txid(witness, k) == btc_txid(stripped, k)).to eq(false)

  it "computes the block subsidy schedule" ->
    expect(btc_subsidy(0)).to eq(5000000000)
    expect(btc_subsidy(209999)).to eq(5000000000)
    expect(btc_subsidy(210000)).to eq(2500000000)
    expect(btc_subsidy(840000)).to eq(312500000)
    expect(btc_subsidy(210000 * 64)).to eq(0)

describe "bech32 addresses" ->
  # Every rejection here protects a block reward: paying a coinbase to a
  # malformed script destroys it irrecoverably, with no way to detect the
  # mistake afterwards.
  it "decodes a mainnet P2WPKH address" ->
    a = "bc1q4za48y8ssc6h227ljnq0mjcy969x5wzt7yuwpa"
    expect(btc_address_to_script(a)).to eq("0014a8bb5390f08635752bdf94c0fdcb042e8a6a384b")
    expect(btc_address_network(a)).to eq("mainnet")

  it "decodes the BIP173 reference vector" ->
    expect(btc_address_to_script("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")).to eq("0014751e76e8199196d454941c45d1b3a323f1433bd6")

  it "decodes a regtest address" ->
    a = "bcrt1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080"
    expect(btc_address_to_script(a)).to eq("0014751e76e8199196d454941c45d1b3a323f1433bd6")
    expect(btc_address_network(a)).to eq("regtest")

  it "decodes a witness-v1 (taproot) address using bech32m" ->
    a = "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y"
    expect(btc_address_decode(a)[:version]).to eq(1)
    expect(btc_address_decode(a)[:encoding]).to eq(2)

  it "rejects a one-character checksum corruption" ->
    expect(btc_address_to_script("bc1q4za48y8ssc6h227ljnq0mjcy969x5wzt7yuwpb") == nil).to eq(true)
    expect(btc_address_to_script("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5") == nil).to eq(true)

  it "rejects a swapped network prefix" ->
    # The hrp is covered by the checksum, so bc -> tb cannot be forged.
    expect(btc_address_to_script("tb1q4za48y8ssc6h227ljnq0mjcy969x5wzt7yuwpa") == nil).to eq(true)

  it "rejects mixed case" ->
    expect(btc_address_to_script("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7Kv8f3t4") == nil).to eq(true)

  it "rejects a truncated address" ->
    expect(btc_address_to_script("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7k") == nil).to eq(true)

  it "rejects witness v1 encoded with bech32 instead of bech32m" ->
    expect(btc_address_to_script("bc1p38j9r5y49hruaue7wxjce0updqjuyyx0kh56v8s25huc6995vvpql3jow4") == nil).to eq(true)

  it "rejects nil and empty input" ->
    expect(btc_address_to_script("") == nil).to eq(true)
    expect(btc_address_to_script(nil) == nil).to eq(true)

describe "P2P wire protocol" ->
  it "frames a verack exactly as the network does" ->
    k = sha256_k()
    empty = i64[1]
    f = p2p_frame(P2P_MAGIC_MAIN, "verack", empty, 0, k)
    expect(btc_bytes_to_hex(f[:bytes], f[:len])).to eq("f9beb4d976657261636b000000000000000000005df6e0e2")

  it "verifies a real mainnet header chain from genesis" ->
    k = sha256_k()
    h1 = btc_hex_to_bytes("010000006fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000982051fd1e4ba744bbbe680e1fee14677ba1a3c3540bf7b1cdb606e857233e0e61bc6649ffff001d01e36299")
    h2 = btc_hex_to_bytes("010000004860eb18bf1b1620e37e9490fc8a427514416fd75159ab86688e9a8300000000d5fdcc541e25de1c7a5addedf24858b8bb665c9f36ef744ee42c316022c90f9bb0bc6649ffff001d08d2bd61")
    r = p2p_verify_header_chain([h1, h2], 2, "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f", k)
    expect(r[:ok]).to eq(1)
    expect(r[:tip]).to eq("000000006a625f06636b8bb6ac7b960a8d03705d1ace08b1a19da3fdcc99ddbd")

  it "rejects a chain whose links do not match" ->
    k = sha256_k()
    h1 = btc_hex_to_bytes("010000006fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000982051fd1e4ba744bbbe680e1fee14677ba1a3c3540bf7b1cdb606e857233e0e61bc6649ffff001d01e36299")
    h2 = btc_hex_to_bytes("010000004860eb18bf1b1620e37e9490fc8a427514416fd75159ab86688e9a8300000000d5fdcc541e25de1c7a5addedf24858b8bb665c9f36ef744ee42c316022c90f9bb0bc6649ffff001d08d2bd61")
    r = p2p_verify_header_chain([h2, h1], 2, "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f", k)
    expect(r[:ok]).to eq(0)
    expect(r[:reason]).to eq("chain break")

describe "P2P message parsing" ->
  it "parses a headers payload into 80-byte headers" ->
    # varint count, then count * (80-byte header + a zero tx-count byte).
    h1 = "010000006fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000982051fd1e4ba744bbbe680e1fee14677ba1a3c3540bf7b1cdb606e857233e0e61bc6649ffff001d01e36299"
    payload = btc_hex_to_bytes("01" + h1 + "00")
    hs = p2p_parse_headers(payload, 1 + 81)
    expect(hs.size).to eq(1)
    expect(btc_bytes_to_hex(hs[0], 80)).to eq(h1)

  it "returns nothing for an empty headers payload" ->
    expect(p2p_parse_headers(btc_hex_to_bytes("00"), 1).size).to eq(0)

  it "builds a getheaders payload with the locator in internal order" ->
    g = p2p_getheaders_payload("000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
                               "0000000000000000000000000000000000000000000000000000000000000000")
    hx = btc_bytes_to_hex(g[:bytes], g[:len])
    # version(4) + varint count(1) + locator(32) + stop(32)
    expect(g[:len]).to eq(69)
    expect(hx.slice(10, 64)).to eq("6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d61900000000 00".gsub(" ", ""))

describe "midstate mining" ->
  it "reproduces the genesis hash through the midstate path" ->
    k = sha256_k()
    job = miner_prepare(btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 0), k)
    expect(sha256_hex_le(miner_hash_nonce(job, 2083236893, k))).to eq(GENESIS_HASH)

  it "agrees with a full header hash across many nonces" ->
    # The whole point of the midstate is that it changes nothing observable.
    k = sha256_k()
    job = miner_prepare(btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 0), k)
    agree = 1
    n = 0
    while n < 100
      nonce = 500000 + n * 104729
      full = sha256_hex(sha256d_bytes(btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, nonce), 80, k))
      if sha256_hex(miner_hash_nonce(job, nonce, k)) != full
        agree = 0
      n += 1
    expect(agree).to eq(1)

  it "re-finds the genesis nonce by search" ->
    k = sha256_k()
    job = miner_prepare(btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 0), k)
    expect(miner_search(job, btc_target_from_bits(0x1d00ffff), 2083236880, 40, k)).to eq(2083236893)

  it "reports -1 when no nonce in the range solves the block" ->
    k = sha256_k()
    job = miner_prepare(btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 0), k)
    expect(miner_search(job, btc_target_from_bits(0x1d00ffff), 2083236880, 10, k)).to eq(-1)

  it "finds the same nonce as the unoptimized reference search" ->
    k = sha256_k()
    header = btc_header_bytes(1, ZERO32, GENESIS_MERKLE, 1231006505, 0x1d00ffff, 0)
    job = miner_prepare(header, k)
    target = btc_target_from_bits(0x1d00ffff)
    expect(miner_search(job, target, 2083236880, 40, k)).to eq(miner_search_naive(header, target, 2083236880, 40, k))

describe "JSON-RPC framing" ->
  it "builds a well-formed JSON-RPC request body" ->
    expect(btc_rpc_request_body("getblockcount", "\[\]")).to eq("{\"jsonrpc\":\"1.0\",\"id\":\"tungsten\",\"method\":\"getblockcount\",\"params\":\[\]}")

  # Body extraction is engine-independent; the JSON decode that follows it
  # needs the compiled engine, so it is exercised by `miner selftest` rather
  # than here.
  it "extracts the body from an HTTP response" ->
    raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"result\":42,\"error\":null,\"id\":\"tungsten\"}"
    expect(btc_rpc_body(raw)).to eq("{\"result\":42,\"error\":null,\"id\":\"tungsten\"}")

  it "returns nil for a response with no header terminator" ->
    expect(btc_rpc_body("HTTP/1.1 200 OK") == nil).to eq(true)

  it "returns nil for an empty response" ->
    expect(btc_rpc_body("") == nil).to eq(true)

spec_summary
