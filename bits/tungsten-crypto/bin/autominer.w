# autominer — one miner, many chains, always on the most profitable one.
#
#   autominer status          evaluate every configured coin, print the table
#   autominer run             mine, switching to the best coin as prices move
#
# Configuration (~/.tungsten/autominer.config), one daemon per line:
#
#   coin.PPC = 127.0.0.1:9902:tungsten:secret
#   coin.TIT = 127.0.0.1:8232:tungsten:secret:mzE...   # optional payout addr
#   eval_secs = 120        # re-rank interval (fresh prices every cycle)
#   min_price_usd = 0      # 0: coins with no price feed rank at $0/day but
#                          # may still be mined when nothing prices higher
#
# The ranking is recomputed from scratch every cycle: difficulty comes from
# each daemon's CURRENT block template (the exact nBits we would mine), the
# reward from that template's coinbasevalue, and the price from a live
# CoinGecko/CoinPaprika fetch. Nothing survives a cycle — a coin that pumps
# 3x mid-day pulls the miner over within one eval_secs.

use ../lib/crypto
use ../lib/gpu_search

GPU_CHUNK = 134217728
TIP_CHECK_MS = 2000

-> am_hexpad(n, width)
  s = ""
  v = n
  digits = "0123456789abcdef"
  i = 0
  while i < width
    s = digits.slice(v & 0xF, 1) + s
    v = v >> 4
    i += 1
  s

-> am_hex_to_i64(hex)
  v = 0
  cs = hex.bytes
  i = 0
  while i < cs.size
    v = v * 16 + btc_hex_nibble(cs[i])
    i += 1
  v

# ---- configuration --------------------------------------------------------

# Parse "host:port:user:pass[:address]" into a connection hash.
-> am_parse_conn(ticker, spec)
  parts = spec.split(":")
  if parts.size < 4
    return nil
  addr = ""
  if parts.size > 4
    addr = parts[4]
  {ticker: ticker, host: parts[0], port: parts[1].to_i,
   user: parts[2], pass: parts[3], address: addr}

# Every configured coin, as connection hashes joined to their registry
# entries. Unknown tickers are reported and skipped, not mined blind.
-> am_load_coins(cfg)
  out = []
  reg = coins_registry()
  keys = cfg.keys
  i = 0
  while i < keys.size
    key = keys[i]
    if key.starts_with?("coin.")
      ticker = key.slice(5, key.size - 5)
      entry = reg[ticker]
      if entry == nil
        << "config names unknown coin [ticker] — skipping (registry: [reg.keys])"
      else
        conn = am_parse_conn(ticker, cfg[key])
        if conn == nil
          << "config for [ticker] is malformed (want host:port:user:pass\[:address\]) — skipping"
        else
          out.push({conn: conn, reg: entry})
    i += 1
  out

# ---- per-coin evaluation --------------------------------------------------

# Ask one daemon for its current template and turn it into an evaluation:
#
#   {ok:, ticker:, height:, bits:, difficulty:, reward:, price:, usd_day:,
#    blocks_day:, tmpl:, err:}
#
# `hashrate` is what we will actually point at the chain. `price` may be
# -1.0 (no feed) — the coin then ranks at $0/day but stays minable.
-> am_evaluate(coin, hashrate, price)
  conn = coin[:conn]
  reg = coin[:reg]
  rpc = BitcoinRPC.new(conn[:host], conn[:port], conn[:user], conn[:pass])
  tmpl = rpc.getblocktemplate_p(reg[:gbt_params])
  if tmpl == nil
    return {ok: 0, ticker: conn[:ticker], err: "getblocktemplate failed (daemon down, syncing, or wrong params)"}
  bits = am_hex_to_i64(tmpl["bits"])
  if btc_target_from_bits(bits) == nil
    return {ok: 0, ticker: conn[:ticker], err: "invalid nBits in template"}
  diff = coins_difficulty_from_bits(bits)
  reward = tmpl["coinbasevalue"]
  if reward == nil
    return {ok: 0, ticker: conn[:ticker], err: "template has no coinbasevalue"}
  p = price
  usd = coins_revenue_per_day(hashrate, bits, reward, p)
  {ok: 1, ticker: conn[:ticker], height: tmpl["height"], bits: bits,
   difficulty: diff, reward: reward, price: p,
   blocks_day: coins_blocks_per_day_bits(hashrate, bits), usd_day: usd,
   tmpl: tmpl, err: nil}

# Fresh prices for every coin in one pass: a single batched CoinGecko call,
# then per-coin fallbacks (CoinPaprika) only for the ids the batch missed.
# Returns ticker -> price (absent ticker = no feed answered).
-> am_fetch_prices(coins)
  gecko_ids = []
  i = 0
  while i < coins.size
    gid = coins[i][:reg][:gecko_id]
    if gid != ""
      gecko_ids.push(gid)
    i += 1
  multi = price_gecko_multi(gecko_ids)
  out = {}
  i = 0
  while i < coins.size
    reg = coins[i][:reg]
    t = coins[i][:conn][:ticker]
    gid = reg[:gecko_id]
    if gid != "" && multi[gid] != nil
      out[t] = multi[gid]
    else
      p = price_usd(reg[:paprika_id], "")
      if p > 0.0
        out[t] = p
    i += 1
  out

# ---- payout scripts -------------------------------------------------------

# The scriptPubKey a coin's coinbase pays. Resolution order:
#
#   1. config address — decoded locally: bech32 first, then base58check
#      against the registry's version byte. Wrong-network addresses die
#      here, before any hash is spent.
#   2. node wallet — getnewaddress + payout_script (needs a loaded wallet).
#
# nil is fatal upstream: mining to nothing burns the reward.
-> am_payout_script(coin, rpc)
  conn = coin[:conn]
  reg = coin[:reg]
  addr = conn[:address]
  if addr != ""
    s = btc_address_to_script(addr)
    if s != nil
      return {script: s, address: addr}
    k = sha256_k()
    s = b58_p2pkh_script(addr, reg[:p2pkh_ver], k)
    if s != nil
      return {script: s, address: addr}
    << "  [conn[:ticker]]: configured address [addr] failed to decode"
    << "  (bech32 rejected it, and base58check against version [reg[:p2pkh_ver]] rejected it)"
    return nil
  a = rpc.getnewaddress
  if a == nil || a == ""
    << "  [conn[:ticker]]: no configured address and the node has no loaded wallet"
    return nil
  s = rpc.payout_script(a)
  if s == nil || s == ""
    << "  [conn[:ticker]]: node would not resolve a scriptPubKey for [a]"
    return nil
  {script: s, address: a}

# ---- mining one template --------------------------------------------------

# Mine `ev`'s template until it is solved, the chain tip moves, or the
# evaluation deadline passes. Returns:
#
#   {outcome: "solved", height:, hash:, reward:}
#   {outcome: "stale"}      tip moved under us — refetch
#   {outcome: "deadline"}   eval_secs elapsed — re-rank coins
#   {outcome: "error", err:}
-> am_mine_template(coin, ev, payout, gpu, k, deadline_ms)
  conn = coin[:conn]
  reg = coin[:reg]
  rpc = BitcoinRPC.new(conn[:host], conn[:port], conn[:user], conn[:pass])
  tmpl = ev[:tmpl]
  height = tmpl["height"]
  bits = ev[:bits]
  target = btc_target_from_bits(bits)
  prev = tmpl["previousblockhash"]
  curtime = tmpl["curtime"]
  version = tmpl["version"]
  reward = ev[:reward]
  commitment = tmpl["default_witness_commitment"]
  if commitment == nil
    commitment = ""
  txtime = -1
  if reg[:txtime] == 1
    txtime = curtime
  txs = tmpl["transactions"]
  tx_hexes = []
  txids = []
  if txs != nil
    i = 0
    while i < txs.size
      tx_hexes.push(txs[i]["data"])
      id = txs[i]["txid"]
      if id == nil
        id = txs[i]["hash"]
      txids.push(id)
      i += 1

  cores = System.cpu_count
  last_tip_check = crypto_now_ms()
  extra = 0
  while extra < 65536
    extra_hex = am_hexpad(extra, 8)
    coinbase = btc_coinbase_hex_ex(height, reward, payout[:script], extra_hex, commitment, txtime)
    cb_txid = btc_coinbase_txid_hex_ex(height, reward, payout[:script], extra_hex, commitment, txtime, k)
    all_txids = [cb_txid]
    i = 0
    while i < txids.size
      all_txids.push(txids[i])
      i += 1
    root = btc_merkle_root(all_txids, k)
    header = btc_header_bytes(version, prev, root, curtime, bits, 0)

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
        # Between GPU launches: is this template still worth hashing?
        now = crypto_now_ms()
        if nonce < 0 && now - last_tip_check > TIP_CHECK_MS
          last_tip_check = now
          tip = rpc.getbestblockhash
          if tip != nil && tip != prev
            return {outcome: "stale"}
          if now > deadline_ms
            return {outcome: "deadline"}
    else
      pool = crypto_pool_prepare(header, target, cores, k)
      handles = crypto_pool_start(pool, 0, 4294967296, 67108864)
      live = 1
      while live > 0
        ccall("__w_sleep_ms", 200)
        snap = crypto_pool_poll(pool)
        live = snap[:live]
        now = crypto_now_ms()
        if now - last_tip_check > TIP_CHECK_MS
          last_tip_check = now
          tip = rpc.getbestblockhash
          stale = 0
          if tip != nil && tip != prev
            stale = 1
          if stale == 1 || now > deadline_ms
            # slots[6] is the pool's abort flag; every worker loop checks it
            # between sub-chunks.
            pool[:slots][6] = 1
            crypto_pool_finish(pool, handles)
            if stale == 1
              return {outcome: "stale"}
            return {outcome: "deadline"}
      res = crypto_pool_finish(pool, handles)
      nonce = res[:nonce]

    if nonce >= 0
      solved = btc_header_bytes(version, prev, root, curtime, bits, nonce)
      hash_hex = sha256_hex_le(btc_header_hash(solved, k))
      # Independent re-check before submission, from the serialized bytes.
      if btc_meets_target(sha256d_bytes(solved, 80, k), target) != 1
        return {outcome: "error", err: "internal: solved nonce fails re-verification"}
      block_hex = btc_block_hex(solved, coinbase, tx_hexes)
      reply = rpc.submitblock(block_hex)
      if reply == nil
        return {outcome: "solved", height: height, hash: hash_hex, reward: reward}
      return {outcome: "error", err: "submitblock rejected: " + reply.to_s}
    extra += 1
  {outcome: "error", err: "extra-nonce space exhausted"}

# ---- ledger ---------------------------------------------------------------

-> am_ledger_path
  h = env("HOME")
  if h == nil
    return nil
  h + "/.tungsten/autominer-ledger.log"

# One line per accepted block: when, what, how much, and what it was worth
# at the moment it was found. Appends; never rewrites history.
-> am_ledger_append(ticker, height, hash, reward, price)
  p = am_ledger_path()
  if p == nil
    return 0
  old = read_file(p)
  if old == nil
    old = ""
  # value_usd is only meaningful with a live price — an unpriced coin
  # (price -1) must not log a spurious negative dollar figure.
  price_s = "n/a"
  usd_s = "n/a"
  if price > 0.0
    price_s = price.to_s
    usd_s = ((reward / 100000000.0) * price).to_s
  line = crypto_now_ms().to_s + " " + ticker + " height=" + height.to_s
  line = line + " hash=" + hash + " reward=" + reward.to_s
  line = line + " price_usd=" + price_s + " value_usd=" + usd_s + "\n"
  ccall("__w_write_file", p, old + line)
  1

# ---- status ---------------------------------------------------------------

-> am_fmt_usd(v)
  if v <= 0.0
    return "-"
  # Two decimals is plenty for a table; sub-cent revenue prints as <0.01.
  cents = (v * 100.0).to_i
  if cents == 0
    return "<$0.01"
  "$" + (cents / 100).to_s + "." + am_pad2(cents % 100)

-> am_pad2(n)
  if n < 10
    return "0" + n.to_s
  n.to_s

-> cmd_status(coins, hashrate)
  << "evaluating [coins.size] coins at [hashrate / 1000000] MH/s ..."
  << ""
  prices = am_fetch_prices(coins)
  << "  coin    height      difficulty      reward        price         blocks/day    USD/day"
  << "  ----    ------      ----------      ------        -----         ----------    -------"
  i = 0
  while i < coins.size
    t = coins[i][:conn][:ticker]
    p = prices[t]
    if p == nil
      p = -1.0
    ev = am_evaluate(coins[i], hashrate, p)
    if ev[:ok] == 1
      << "  [t]    [ev[:height]]    [ev[:difficulty]]    [ev[:reward]]    [ev[:price]]    [ev[:blocks_day]]    [am_fmt_usd(ev[:usd_day])]"
    else
      << "  [t]    UNAVAILABLE: [ev[:err]]"
    i += 1
  0

# ---- the switching loop ---------------------------------------------------

-> cmd_run(coins, cfg)
  k = sha256_k()
  eval_secs = crypto_config_get(cfg, "eval_secs", "120").to_i
  if eval_secs < 10
    eval_secs = 10

  gpu = nil
  engine = "CPU [System.cpu_count] threads"
  if gpu_search_available()
    gpu = gpu_search_open()
    if gpu != nil
      engine = "GPU (Metal)"
  hashrate = 500000000
  if gpu != nil
    hashrate = 2100000000

  << "autominer: [coins.size] coins, engine [engine], re-ranking every [eval_secs]s"
  << "ledger: [am_ledger_path()]"
  << ""

  # Payout scripts resolve once per coin per process — the address does not
  # move with the market. Coins that cannot pay are dropped now, loudly.
  minable = []
  i = 0
  while i < coins.size
    conn = coins[i][:conn]
    rpc = BitcoinRPC.new(conn[:host], conn[:port], conn[:user], conn[:pass])
    pay = am_payout_script(coins[i], rpc)
    if pay != nil
      << "  [conn[:ticker]] pays [pay[:address]]"
      minable.push({conn: conn, reg: coins[i][:reg], payout: pay})
    i += 1
  if minable.size == 0
    << "no minable coins — every configured daemon failed payout resolution"
    return 1
  << ""

  current = ""
  blocks_found = 0
  loop
    # ---- rank: fresh prices, fresh templates, every cycle ----
    prices = am_fetch_prices(minable)
    best = nil
    best_ev = nil
    i = 0
    while i < minable.size
      t = minable[i][:conn][:ticker]
      p = prices[t]
      if p == nil
        p = -1.0
      ev = am_evaluate(minable[i], hashrate, p)
      if ev[:ok] == 1
        take = 0
        if best_ev == nil
          take = 1
        else
          # This reads naturally as
          #   elsif best_ev[:usd_day] <= 0.0 && ev[..] > best_ev[..]
          # but that exact shape — an `elsif <float> <= 0.0 && ...`
          # compound inside the `else` of a loop-carried nil accumulator —
          # miscompiles: the ownership pass emits a w_value_free whose float
          # literal does not dominate it (invalid LLVM IR, "Instruction does
          # not dominate all uses"). Nested plain `if`s avoid it. Repro:
          # scratchpad/ownership_dominance_repro.w. Restore the elsif once
          # the pass is fixed.
          if ev[:usd_day] > best_ev[:usd_day]
            take = 1
          else
            # No coin has a price: prefer the one we can actually solve.
            if best_ev[:usd_day] <= 0.0
              if ev[:blocks_day] > best_ev[:blocks_day]
                take = 1
        if take == 1
          best = minable[i]
          best_ev = ev
      else
        << "[t]: [ev[:err]]"
      i += 1

    if best == nil
      << "no daemon produced a template; retrying in 30s"
      ccall("__w_sleep_ms", 30000)
    else
      t = best[:conn][:ticker]
      if t != current
        << "==> switching to [t]: [am_fmt_usd(best_ev[:usd_day])]/day expected ([best_ev[:blocks_day]] blocks/day at difficulty [best_ev[:difficulty]])"
        current = t
      deadline = crypto_now_ms() + eval_secs * 1000

      # Mine this coin until the deadline, riding template refreshes.
      mining = 1
      while mining == 1
        r = am_mine_template(best, best_ev, best[:payout], gpu, k, deadline)
        oc = r[:outcome]
        if oc == "solved"
          blocks_found += 1
          p = prices[t]
          if p == nil
            p = -1.0
          << "*** BLOCK [blocks_found]: [t] height [r[:height]] hash [r[:hash]] reward [r[:reward]] ***"
          am_ledger_append(t, r[:height], r[:hash], r[:reward], p)
          # Solved: the tip is ours; refetch a fresh template immediately.
        elsif oc == "error"
          << "[t]: [r[:err]] — re-ranking"
          mining = 0
        elsif oc == "deadline"
          mining = 0
        # "stale" falls through: refetch template below.
        if mining == 1
          if crypto_now_ms() > deadline
            mining = 0
          else
            ev2 = am_evaluate(best, hashrate, best_ev[:price])
            if ev2[:ok] == 1
              best_ev = ev2
            else
              << "[t]: [ev2[:err]] — re-ranking"
              mining = 0
  0

# ---- entry ----------------------------------------------------------------

-> am_config_load
  h = env("HOME")
  if h == nil
    return {}
  text = read_file(h + "/.tungsten/autominer.config")
  if text == nil
    return {}
  crypto_config_parse(text)

cfg = am_config_load()
coins = am_load_coins(cfg)

args = argv()
cmd = "status"
if args.size > 0
  cmd = args[0]

if coins.size == 0
  << "no coins configured. Add daemons to ~/.tungsten/autominer.config:"
  << ""
  << "  coin.PPC = 127.0.0.1:9902:rpcuser:rpcpass"
  << "  coin.TIT = 127.0.0.1:8232:rpcuser:rpcpass:optional_payout_address"
  << "  eval_secs = 120"
  << ""
  << "registry: [coins_registry().keys]"
  exit(1)

if cmd == "status"
  hashrate = 2100000000
  exit(cmd_status(coins, hashrate))
elsif cmd == "run"
  exit(cmd_run(coins, cfg))
else
  << "usage: autominer \[status|run\]"
  exit(1)
