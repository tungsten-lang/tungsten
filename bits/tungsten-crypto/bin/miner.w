# tungsten-miner — a Bitcoin miner.
#
#   miner selftest              hash vectors + real mainnet blocks
#   miner bench [n]             hash rate, naive vs midstate
#   miner demo [bits]           mine a block at a chosen difficulty
#   miner solo [host port user pass]
#                               solo-mine against a bitcoind via JSON-RPC
#
# `solo` is the real thing: it pulls a template with getblocktemplate,
# builds the coinbase, mines, and submits with submitblock. Point it at a
# regtest or signet node to see it work end to end. Aimed at mainnet it is
# honest but futile — see the README on why a CPU cannot compete.

use ../lib/crypto
# The GPU path pulls in core/metal, which the interpreter cannot run — but
# this file is only ever compiled (bin/tungsten -o), so importing it here is
# safe. It is kept OUT of lib/crypto.w so interpreted consumers of the bit
# still work.
use ../lib/gpu_search

-> hexpad(n, width)
  s = ""
  v = n
  digits = "0123456789abcdef"
  i = 0
  while i < width
    s = digits.slice(v & 0xF, 1) + s
    v = v >> 4
    i += 1
  s

-> report(label, got, want)
  if got == want
    << "  ok    " + label
    return 1
  << "  FAIL  " + label
  << "        got  [got]"
  << "        want [want]"
  0

# ---- selftest -------------------------------------------------------------

-> cmd_selftest
  k = sha256_k()
  pass = 0
  total = 0

  << "SHA-256 (FIPS 180-4)"
  total += 1
  pass += report("empty string", sha256_hex(sha256_string_words("", k)),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  total += 1
  pass += report("abc", sha256_hex(sha256_string_words("abc", k)),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  total += 1
  pass += report("448-bit message", sha256_hex(sha256_string_words("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", k)),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

  << "Bitcoin genesis block"
  zero = "0000000000000000000000000000000000000000000000000000000000000000"
  gm = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
  gh = btc_header_bytes(1, zero, gm, 1231006505, 0x1d00ffff, 2083236893)
  total += 1
  pass += report("header serialization", btc_bytes_to_hex(gh, 80),
    "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c")
  total += 1
  pass += report("block hash", sha256_hex_le(btc_header_hash(gh, k)),
    "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
  total += 1
  pass += report("meets difficulty-1 target",
    btc_meets_target(btc_header_hash(gh, k), btc_target_from_bits(0x1d00ffff)).to_s, "1")

  << "Bitcoin mainnet block 100000"
  txids = [
    "8c14f0db3df150123e6f3dbbf30f8b955a8249b62ac1d1ff16284aefa3d06d87",
    "fff2525b8931402dd09222c50775608f75787bd2b87e56995a7bdd30f79702c4",
    "6359f0868171b1d194cbee1af2f16ea598ae8fad666d9b012c8ed2b79a236ec4",
    "e9a66845e05d5abc0ad04ec80f774a7e585c6e8db975962d069a522137b80c1d"
  ]
  root = btc_merkle_root(txids, k)
  total += 1
  pass += report("merkle root (4 txs)", root,
    "f3e94742aca4b5ef85488dc37c06c3282295ffec960994b2c0d5ac2a25a95766")
  h100k = btc_header_bytes(1, "000000000002d01c1fccc21636b607dfd930d31d01c3a62104612a1719011250",
                           root, 1293623863, 0x1b04864c, 274148111)
  total += 1
  pass += report("block hash", sha256_hex_le(btc_header_hash(h100k, k)),
    "000000000003ba27aa200b1cecaad478d2b00432346c3f1f3986da1afd33e506")
  total += 1
  pass += report("odd-count merkle (3 txs)", btc_merkle_root([txids[0], txids[1], txids[2]], k),
    "fa435470825de273081dcc706b25514c936fa6dc80ab965ce6970d68ddd0b553")
  total += 1
  pass += report("block 1 coinbase txid",
    btc_txid("01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff0704ffff001d0104ffffffff0100f2052a0100000043410496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858eeac00000000", k),
    "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098")

  << "midstate path"
  job = miner_prepare(btc_header_bytes(1, zero, gm, 1231006505, 0x1d00ffff, 0), k)
  total += 1
  pass += report("reproduces genesis hash", sha256_hex_le(miner_hash_nonce(job, 2083236893, k)),
    "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
  # The midstate loop must agree with a plain full-header hash everywhere,
  # not just at the genesis nonce.
  agree = 1
  n = 0
  while n < 500
    nonce = 1000000 + n * 7919
    want = sha256_hex(sha256d_bytes(btc_header_bytes(1, zero, gm, 1231006505, 0x1d00ffff, nonce), 80, k))
    if sha256_hex(miner_hash_nonce(job, nonce, k)) != want
      agree = 0
    n += 1
  total += 1
  pass += report("agrees with naive hash over 500 nonces", agree.to_s, "1")
  total += 1
  pass += report("search re-finds the genesis nonce",
    miner_search(job, btc_target_from_bits(0x1d00ffff), 2083236880, 40, k).to_s, "2083236893")

  << "BIP34 / consensus encodings"
  total += 1
  pass += report("script number (height 227836)", btc_script_num_hex(227836), "fc7903")
  total += 1
  pass += report("script number sign padding (128)", btc_script_num_hex(128), "8000")
  total += 1
  pass += report("varint 0xFD boundary", btc_varint_hex(253), "fdfd00")
  total += 1
  pass += report("subsidy at height 0", btc_subsidy(0).to_s, "5000000000")
  total += 1
  pass += report("subsidy after 4 halvings", btc_subsidy(840000).to_s, "312500000")

  << ""
  << "[pass]/[total] checks passed"
  if pass == total
    return 0
  1

# ---- benchmark ------------------------------------------------------------

-> cmd_bench(n)
  k = sha256_k()
  zero = "0000000000000000000000000000000000000000000000000000000000000000"
  gm = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
  # A target nothing in range will meet, so both loops run to completion.
  hard = btc_target_from_bits(0x03000001)
  header = btc_header_bytes(1, zero, gm, 1231006505, 0x1d00ffff, 0)
  job = miner_prepare(header, k)

  << "scanning [n] nonces per strategy"
  t0 = crypto_now_ms()
  miner_search_naive(header, hard, 1000000, n, k)
  naive_ms = crypto_now_ms() - t0

  t0 = crypto_now_ms()
  miner_search(job, hard, 1000000, n, k)
  mid_ms = crypto_now_ms() - t0

  if naive_ms == 0 || mid_ms == 0
    << "too fast to measure — pass a larger n"
    return 1
  naive_hs = n * 1000 / naive_ms
  mid_hs = n * 1000 / mid_ms
  << ""
  << "naive     [naive_ms] ms   [naive_hs] H/s   (3 compressions per nonce)"
  << "midstate  [mid_ms] ms   [mid_hs] H/s   (2 compressions per nonce)"
  << "midstate is [mid_hs * 100 / naive_hs]% of naive"
  0

# ---- demo -----------------------------------------------------------------

# Mine a real block at a chosen difficulty, with a real coinbase. This is
# the whole pipeline minus the network: build a coinbase, take its txid as
# the merkle root, search for a nonce, verify the result.
-> cmd_demo(bits, payout_addr)
  k = sha256_k()
  chain_desc = "offline demo"
  tip_desc = "-"
  height = 800000
  reward = btc_subsidy(height)
  # With an address, decode it locally (no node needed) and pay there.
  # Without one, fall back to an UNSPENDABLE burn script — fine for an
  # offline demonstration, catastrophic anywhere else, and announced as such.
  burning = 0
  if payout_addr != ""
    script = btc_address_to_script(payout_addr)
    if script == nil
      << "invalid address: [payout_addr]"
      << "  checksum, length, or witness-version check failed — refusing to mine"
      return 1
  else
    script = btc_p2wpkh_script("0000000000000000000000000000000000000000")
    burning = 1
  prev = "0000000000000000000f9c0a1e2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"
  version = 0x20000000
  curtime = 1753900000
  target = btc_target_from_bits(bits)
  if target == nil
    << "nBits 0x[hexpad(bits, 8)] is not a valid target (negative or overflowing)"
    return 1
  cores = System.cpu_count

  << "mining a block"
  << "  height     [height]"
  << "  reward     [reward] sat"
  << "  nBits      0x[hexpad(bits, 8)]"
  if burning == 1
    << "  payout     UNSPENDABLE burn script (pass an address to get paid)"
  else
    << "  payout     [payout_addr] ([btc_address_network(payout_addr)])"
    << "             scriptPubKey [script]"
  << "  threads    [cores]"
  << "  sha ext    [crypto_accel_available()]"

  # One pass over the 32-bit nonce field is only 2**32 hashes. When the
  # target needs more than that, a miner changes the coinbase — a different
  # extra-nonce gives a different coinbase txid, hence a different merkle
  # root, hence a completely fresh 2**32 nonce space to search.
  t_start = crypto_now_ms()
  scanned = 0
  extra = 0
  while extra < 4096
    extra_hex = hexpad(extra, 8)
    coinbase = btc_coinbase_hex(height, reward, script, extra_hex, "")
    txid = btc_coinbase_txid_hex(height, reward, script, extra_hex, "", k)
    root = btc_merkle_root([txid], k)
    header = btc_header_bytes(version, prev, root, curtime, bits, 0)
    pool = crypto_pool_prepare(header, target, cores, k)
    res = crypto_mine_parallel(pool, 0, 4294967296, k)
    scanned += res[:scanned]
    nonce = res[:nonce]
    if nonce >= 0
      ms = crypto_now_ms() - t_start
      solved = btc_header_bytes(version, prev, root, curtime, bits, nonce)
      << ""
      << "  SOLVED"
      << "  extranonce [extra]"
      << "  nonce      [nonce]"
      << "  merkle     [root]"
      << "  hash       [sha256_hex_le(btc_header_hash(solved, k))]"
      << "  elapsed    [ms] ms"
      if ms > 0
        << "  rate       [(scanned / ms) * 1000] H/s"
      # Independent check: re-hash the assembled header from scratch and
      # re-test the target, so the answer does not rest on the search's own
      # bookkeeping.
      if btc_meets_target(sha256d_bytes(solved, 80, k), target) != 1
        << "  VERIFY FAILED"
        return 1
      << "  verified   hash <= target, re-checked from the serialized header"
      block_hex = btc_block_hex(solved, coinbase, [])
      << "  block      [block_hex.size / 2] bytes"
      return 0
    << "  extranonce [extra] exhausted (2**32 nonces), rolling"
    extra += 1
  << "  gave up after 4096 extra-nonce rolls"
  1



# ---- header sync -----------------------------------------------------------

# Connect to a peer, download the header chain, verify every header's proof
# of work and linkage, and report the tip. This is what makes mining mean
# anything: without a real tip and real nBits, a miner produces blocks that
# name a predecessor which does not exist.
-> cmd_sync(host, port, network, maxh)
  k = sha256_k()
  start = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
  if network == "regtest"
    start = "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"
  # No host given: bootstrap off the public network the way any Bitcoin
  # client does, through the DNS seeds Core itself ships.
  hosts = [host]
  if host == ""
    if network != "mainnet"
      << "a host is required for [network] — DNS seeds only exist for mainnet"
      return 1
    hosts = p2p_mainnet_seeds()
    << "bootstrapping from [hosts.size] DNS seeds ([network])"
  else
    << "connecting to [host]:[port] ([network])"
  conn = p2p_connect_any(hosts, port, network, 0, 1753900000, k)
  if conn == nil
    << "no peer completed a handshake — all of them refused, timed out, or"
    << "are on a different network than [network]"
    return 1
  if host == ""
    << "peer [conn[:host]]"
  << "handshake complete, downloading headers"
  t0 = crypto_now_ms()
  r = p2p_sync_headers(conn, start, 0, maxh, k)
  ms = crypto_now_ms() - t0
  conn[:sock].close
  if r[:error] != nil
    << "CHAIN INVALID: [r[:error]] at header [r[:at]]"
    return 1
  << ""
  << "  headers   [r[:count]] verified in [ms] ms"
  << "  height    [r[:height]]"
  << "  tip       [r[:tip]]"
  << "  nBits     0x[hexpad(r[:bits], 8)]"
  << "  every header checked: proof of work below its stated target, and"
  << "  each one naming its predecessor."
  0

# ---- live mining with a display -------------------------------------------

# Scan the nonce space in chunks so the main thread can redraw between them.
# The chunk is a normal full-speed parallel scan; nothing in the hash loop
# knows the display exists.
CHUNK = 67108864
# One GPU launch. ~128M nonces keeps a dispatch near 70 ms on an M5 Max —
# long enough to amortize launch cost, short enough to refresh the display.
GPU_CHUNK = 134217728

-> cmd_mine(bits, payout_addr, height, phost, pport, pnet)
  k = sha256_k()
  if payout_addr == ""
    << "usage: miner mine <nbits_hex> <address>"
    << "  an address is required — mining to a placeholder burns the reward"
    return 1
  script = btc_address_to_script(payout_addr)
  if script == nil
    << "invalid address: [payout_addr] — refusing to mine"
    return 1
  # --- real chain state, if a peer was given ---
  chain_desc = "offline (no node configured)"
  tip_desc = "-"
  if phost != ""
    << "syncing headers ([pnet]) ..."
    startpt = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
    if pnet == "regtest"
      startpt = "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"
    mhosts = [phost]
    if phost == "seeds"
      mhosts = p2p_mainnet_seeds()
    conn = p2p_connect_any(mhosts, pport, pnet, 0, 1753900000, k)
    if conn == nil
      << "cannot reach any peer — refusing to mine against a fabricated"
      << "chain. Drop the host/port to run in offline demo mode."
      return 1
    sy = p2p_sync_headers(conn, startpt, 0, 2000000, k)
    conn[:sock].close
    if sy[:error] != nil
      << "peer served an INVALID chain: [sy[:error]] at header [sy[:at]]"
      return 1
    # Everything below now comes from the network, not from constants.
    prev = sy[:tip]
    height = sy[:height] + 1
    bits = sy[:bits]
    curtime = sy[:time] + 1
    reward = btc_subsidy(height)
    chain_desc = pnet + "  " + sy[:count].to_s + " headers verified"
    tip_desc = sy[:tip]
    << "tip [sy[:tip]] at height [sy[:height]], nBits 0x[hexpad(bits, 8)]"

  target = btc_target_from_bits(bits)
  if target == nil
    << "nBits 0x[hexpad(bits, 8)] is not a valid target"
    return 1
  reward = btc_subsidy(height)
  prev = "0000000000000000000f9c0a1e2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"
  version = 0x20000000
  curtime = 1753900000
  cores = System.cpu_count
  need = tui_target_zeros(target)

  # Prefer the GPU. It is ~4x the CPU on this machine, and the CPU pool is the
  # fallback when Metal is unavailable (non-Apple, or an interpreter build).
  gpu = nil
  engine = "CPU " + cores.to_s + " threads"
  if gpu_search_available()
    gpu = gpu_search_open()
    if gpu != nil
      engine = "GPU (Metal, @gpu)"

  st = {payout: payout_addr, height: height, bits_hex: hexpad(bits, 8),
        threads: cores, engine: engine, scanned: 0, elapsed: 0, best: 0xFFFFFFFF,
        need: need, extra: 0, best_hash: nil,
        target_hex: tui_target_hex(target),
        chain: chain_desc, tip: tip_desc}

  tui_hide_cursor()
  lines = 0
  t_start = crypto_now_ms()
  extra = 0
  while extra < 4096
    extra_hex = hexpad(extra, 8)
    coinbase = btc_coinbase_hex(height, reward, script, extra_hex, "")
    txid = btc_coinbase_txid_hex(height, reward, script, extra_hex, "", k)
    root = btc_merkle_root([txid], k)
    header = btc_header_bytes(version, prev, root, curtime, bits, 0)
    st[:extra] = extra
    scanned_before = st[:scanned]
    nonce = -1 ## i64

    if gpu != nil
      # GPU: dispatch the 2**32 range in chunks the size of one launch, so the
      # display refreshes between launches. The kernel tracks best-so-far
      # itself (one atomic per thread), and we recompute the winning digest on
      # the CPU only when the best actually improves.
      prep = miner_prepare(header, k)
      gpu_search_load(gpu, prep, target)
      base = 0
      while base < 4294967296 && nonce < 0
        n = GPU_CHUNK
        if base + n > 4294967296
          n = 4294967296 - base
        r = gpu_search_run_best(gpu, prep, target, base, n, 64, 32, k)
        st[:scanned] = scanned_before + base + n
        st[:elapsed] = crypto_now_ms() - t_start
        if r[:best] < st[:best]
          st[:best] = r[:best]
          # best_nonce races the value in the kernel, so recompute and only
          # trust the digest if its top word still matches the reported best.
          d = miner_hash_nonce(prep, r[:best_nonce], k)
          if btc_bswap32(d[7]) == r[:best]
            st[:best_hash] = d
        tui_rewind(lines)
        lines = tui_frame(st)
        if r[:nonce] >= 0
          nonce = r[:nonce]
        base += n
    else
      # CPU: persistent worker pool, spawned once for the whole range.
      pool = crypto_pool_prepare(header, target, cores, k)
      handles = crypto_pool_start(pool, 0, 4294967296, CHUNK)
      live = 1
      while live > 0
        ccall("__w_sleep_ms", 150)
        snap = crypto_pool_poll(pool)
        live = snap[:live]
        st[:scanned] = scanned_before + snap[:scanned]
        st[:elapsed] = crypto_now_ms() - t_start
        if snap[:best] < st[:best]
          st[:best] = snap[:best]
          st[:best_hash] = snap[:best_hash]
        tui_rewind(lines)
        lines = tui_frame(st)
      res = crypto_pool_finish(pool, handles)
      st[:scanned] = scanned_before + res[:scanned]
      if res[:best] < st[:best]
        st[:best] = res[:best]
        st[:best_hash] = res[:best_hash]
      tui_rewind(lines)
      lines = tui_frame(st)
      nonce = res[:nonce]

    if nonce >= 0
      tui_show_cursor()
      solved = btc_header_bytes(version, prev, root, curtime, bits, nonce)
      << ""
      << "  *** BLOCK SOLVED ***"
      << "  engine      [engine]"
      << "  nonce       [nonce]"
      << "  extranonce  [extra]"
      << "  hash        [sha256_hex_le(btc_header_hash(solved, k))]"
      << "  pays        [reward] sat to [payout_addr]"
      if btc_meets_target(sha256d_bytes(solved, 80, k), target) != 1
        << "  VERIFY FAILED"
        return 1
      << "  verified    re-hashed from the serialized header"
      << "  block       [btc_block_hex(solved, coinbase, []).size / 2] bytes"
      return 0
    extra += 1
  tui_show_cursor()
  1

# ---- solo mining ----------------------------------------------------------

-> cmd_solo(host, port, user, pass, payout_addr)
  k = sha256_k()
  rpc = BitcoinRPC.new(host, port, user, pass)
  << "connecting to [host]:[port]"
  count = rpc.getblockcount
  if count == nil
    << "cannot reach bitcoind (check host/port/credentials, and that the"
    << "node is started with -server and rpcuser/rpcpassword set)"
    return 1
  << "chain height [count]"

  tmpl = rpc.getblocktemplate
  if tmpl == nil
    << "getblocktemplate failed"
    return 1

  height = tmpl["height"]
  bits_hex = tmpl["bits"]
  prev = tmpl["previousblockhash"]
  curtime = tmpl["curtime"]
  version = tmpl["version"]
  coinbasevalue = tmpl["coinbasevalue"]
  bits = btc_hex_to_i64(bits_hex)
  if btc_target_from_bits(bits) == nil
    << "node sent an nBits the protocol rejects: [bits_hex]"
    return 1

  # The witness commitment must be echoed into the coinbase verbatim when
  # the template supplies one; a node running segwit rejects a block whose
  # coinbase lacks it.
  commitment = tmpl["default_witness_commitment"]
  if commitment == nil
    commitment = ""

  txs = tmpl["transactions"]
  tx_hexes = []
  txids = []
  if txs != nil
    i = 0
    while i < txs.size
      tx_hexes.push(txs[i]["data"])
      txids.push(txs[i]["txid"])
      i += 1

  << "template: height [height] nBits [bits_hex] txs [tx_hexes.size]"

  # Where the reward goes. The node's wallet owns the key; we only need the
  # output script, which getaddressinfo hands us — so no key material and no
  # bech32 decoder live in this miner.
  #
  # If no spendable script can be obtained we STOP. Mining to a placeholder
  # would look like success and silently burn the entire block reward, which
  # is the worst possible failure mode for this program.
  # An explicitly supplied address is decoded LOCALLY. That works on a node
  # with no wallet loaded, and keeps the node out of the trust path for where
  # the money goes. Otherwise ask the node's wallet for one.
  script = ""
  if payout_addr != ""
    script = btc_address_to_script(payout_addr)
    if script == nil
      << "invalid address: [payout_addr]"
      << "  checksum, length, or witness-version check failed — refusing to mine"
      return 1
  else
    payout_addr = rpc.getnewaddress
    if payout_addr == nil || payout_addr == ""
      << "cannot obtain a payout address."
      << "  the node has no loaded wallet — either load one:"
      << "    bitcoin-cli -regtest createwallet miner"
      << "  or pass an address you control as the 5th argument:"
      << "    miner solo [host] [port] [user] [pass] <address>"
      << "refusing to mine: the reward would be unspendable."
      return 1
    script = rpc.payout_script(payout_addr)
    if script == nil || script == ""
      << "node could not resolve a scriptPubKey for [payout_addr]"
      << "refusing to mine: the reward would be unspendable."
      return 1
  net = btc_address_network(payout_addr)
  << "payout: [payout_addr]"
  << "        scriptPubKey [script]"
  if net != nil
    << "        network [net]"

  cores = System.cpu_count
  # Same engine choice as `mine`: GPU when Metal is available, CPU pool
  # otherwise.
  gpu = nil
  if gpu_search_available()
    gpu = gpu_search_open()
  if gpu != nil
    << "mining on the GPU (Metal, @gpu)"
  else
    << "mining with [cores] threads, sha extension [crypto_accel_available()]"

  extra = 0
  while extra < 65536
    extra_hex = hexpad(extra, 8)
    coinbase = btc_coinbase_hex(height, coinbasevalue, script, extra_hex, commitment)
    cb_txid = btc_coinbase_txid_hex(height, coinbasevalue, script, extra_hex, commitment, k)
    all_txids = [cb_txid]
    i = 0
    while i < txids.size
      all_txids.push(txids[i])
      i += 1
    root = btc_merkle_root(all_txids, k)
    header = btc_header_bytes(version, prev, root, curtime, bits, 0)
    target = btc_target_from_bits(bits)

    # Every extra-nonce value is a fresh coinbase, hence a fresh merkle root
    # and a fresh 2**32 nonce space — the standard way to keep searching once
    # the 32-bit field is exhausted.
    t0 = crypto_now_ms()
    nonce = -1 ## i64
    if gpu != nil
      prep = miner_prepare(header, k)
      gpu_search_load(gpu, prep, target)
      base = 0
      while base < 4294967296 && nonce < 0
        n = GPU_CHUNK
        if base + n > 4294967296
          n = 4294967296 - base
        r = gpu_search_run_best(gpu, prep, target, base, n, 64, 32, k)
        if r[:nonce] >= 0
          nonce = r[:nonce]
        base += n
    else
      pool = crypto_pool_prepare(header, target, cores, k)
      res = crypto_mine_parallel(pool, 0, 4294967296, k)
      nonce = res[:nonce]
    ms = crypto_now_ms() - t0
    if nonce >= 0
      solved = btc_header_bytes(version, prev, root, curtime, bits, nonce)
      << "SOLVED nonce [nonce] hash [sha256_hex_le(btc_header_hash(solved, k))]"
      block_hex = btc_block_hex(solved, coinbase, tx_hexes)
      reply = rpc.submitblock(block_hex)
      # submitblock answers null on acceptance and a reason string otherwise.
      if reply == nil
        << "block ACCEPTED by the node"
      else
        << "block rejected: [reply]"
      return 0
    << "extra-nonce [extra] exhausted ([ms] ms), rolling"
    extra += 1
  1

-> btc_hex_to_i64(hex)
  v = 0
  cs = hex.bytes.to_a
  i = 0
  while i < cs.size
    v = v * 16 + btc_hex_nibble(cs[i])
    i += 1
  v

# ---- entry ----------------------------------------------------------------

# Defaults come from ~/.tungsten/crypto.config; anything on the command line
# overrides them. The command line always wins, so a stale config can never
# silently redirect the payout.
cfg = crypto_config_load()
cfg_addr = crypto_config_get(cfg, "address", "")
cfg_peer = crypto_config_get(cfg, "peer", "")
cfg_port = crypto_config_get(cfg, "port", "8333").to_i
cfg_net = crypto_config_get(cfg, "network", "mainnet")
cfg_bits = crypto_config_get(cfg, "nbits", "")

# argv() excludes the program name: args[0] is the first real argument.
args = argv()
cmd = "selftest"
if args.size > 0
  cmd = args[0]

if cmd == "selftest"
  exit(cmd_selftest())
elsif cmd == "bench"
  n = 200000
  if args.size > 1
    n = args[1].to_i
  exit(cmd_bench(n))
elsif cmd == "config"
  # Show what the miner will do with no arguments, and where that came from.
  p = crypto_config_path()
  << "config   [p]"
  if cfg.size == 0
    << "         (absent or empty — every value below is a built-in default)"
  << "address  " + crypto_config_get(cfg, "address", "(unset — mine/solo will refuse)")
  << "peer     " + crypto_config_get(cfg, "peer", "(unset — offline demo)")
  << "port     [cfg_port]"
  << "network  [cfg_net]"
  << "nbits    " + crypto_config_get(cfg, "nbits", "(unset — use the chain's own difficulty)")
  if cfg_addr != ""
    sc = btc_address_to_script(cfg_addr)
    if sc == nil
      << ""
      << "the configured address FAILS its checksum — mining would burn the"
      << "reward. Fix it before running mine or solo."
      exit(1)
    << ""
    << "address decodes to scriptPubKey [sc] ([btc_address_network(cfg_addr)])"
  exit(0)
elsif cmd == "demo"
  bits = 0x1e00ffff
  if args.size > 1
    bits = btc_hex_to_i64(args[1])
  elsif cfg_bits != ""
    bits = btc_hex_to_i64(cfg_bits)
  dpay = cfg_addr
  if args.size > 2
    dpay = args[2]
  exit(cmd_demo(bits, dpay))
elsif cmd == "sync"
  shost = cfg_peer
  if shost == "seeds"
    shost = ""
  sport = cfg_port
  snet = cfg_net
  smax = 2000000
  if args.size > 1
    shost = args[1]
  if args.size > 2
    sport = args[2].to_i
  if args.size > 3
    snet = args[3]
  if args.size > 4
    smax = args[4].to_i
  exit(cmd_sync(shost, sport, snet, smax))
elsif cmd == "mine"
  # nBits is a placeholder when a peer is configured: syncing replaces it
  # with the chain's real difficulty.
  mbits = 0x1d00ffff
  if cfg_bits != ""
    mbits = btc_hex_to_i64(cfg_bits)
  if args.size > 1
    mbits = btc_hex_to_i64(args[1])
  maddr = cfg_addr
  if args.size > 2
    maddr = args[2]
  mheight = 800000
  mhost = cfg_peer
  mport = cfg_port
  mnet = cfg_net
  if args.size > 3
    mhost = args[3]
  if args.size > 4
    mport = args[4].to_i
  if args.size > 5
    mnet = args[5]
  exit(cmd_mine(mbits, maddr, mheight, mhost, mport, mnet))
elsif cmd == "solo"
  host = "127.0.0.1"
  port = 8332
  user = "bitcoin"
  pass = "bitcoin"
  if args.size > 1
    host = args[1]
  if args.size > 2
    port = args[2].to_i
  if args.size > 3
    user = args[3]
  if args.size > 4
    pass = args[4]
  payout = cfg_addr
  if args.size > 5
    payout = args[5]
  exit(cmd_solo(host, port, user, pass, payout))
else
  # Brackets are escaped: `[...]` inside a double-quoted string is
  # interpolation, so an unescaped usage line evaluates its own contents.
  << "usage: miner <command>"
  << "  selftest                  hash vectors and real mainnet blocks"
  << "  config                    show the active defaults and where they came from"
  << "  bench \[n\]                 CPU hash rate, naive vs midstate"
  << "  sync \[host port network\]  download and verify the header chain"
  << "  mine \[nbits\] \[address\] \[host port network\]"
  << "  demo \[nbits\] \[address\]    mine offline against a fabricated parent"
  << "  solo \[host port user pass \[address\]\]   mine via a bitcoind's RPC"
  << ""
  << "defaults are read from ~/.tungsten/crypto.config; see `miner config`"
  exit(1)
