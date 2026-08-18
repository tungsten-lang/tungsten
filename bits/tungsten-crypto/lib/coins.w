# The coin registry: what makes each SHA-256d chain minable by this code.
#
# Every entry describes one daemon this miner knows how to talk to. The
# mining-critical fields are deliberately few, because the safest source of
# per-coin truth is the coin's own node: the reward comes from the
# template's `coinbasevalue`, the payout script from the node wallet's own
# address (or a locally decoded one), and difficulty from `getmininginfo`.
# What cannot be asked of the node is what this table holds:
#
#   rpc_port     conventional mainnet RPC port (config can override)
#   gbt_params   exact getblocktemplate params JSON. Modern Core forks
#                (0.13+) require {"rules":["segwit"]}; pre-BIP9 forks
#                reject a rules object they do not understand and want []
#   txtime       1 = peercoin lineage: transactions carry a uint32 nTime
#                between version and input count, and the coinbase's must
#                match the block time from the template
#   p2pkh_ver    base58 P2PKH version byte, for local address decoding
#                (-1 = unknown; then only node-wallet payouts are allowed)
#   gecko_id /   price API identifiers ("" = not listed there). Prices are
#   paprika_id   fetched fresh on every evaluation cycle — never cached
#                across cycles — so the switcher follows the market
#   block_secs   nominal seconds per block (for the blocks/day estimate)
#   maturity     coinbase confirmations before spendable (informational)
#
# Chains whose templates carry mandatory extra payouts (masternode coins:
# Terracoin, Dash lineage) are NOT registrable yet — a coinbase that omits
# the masternode payee is consensus-invalid there. That needs payee
# handling in block.w first.

-> coins_registry
  {
    "BTC": {name: "Bitcoin", rpc_port: 8332,
            gbt_params: "\[{\"rules\":\[\"segwit\"\]}\]",
            txtime: 0, p2pkh_ver: 0x00,
            gecko_id: "bitcoin", paprika_id: "btc-bitcoin",
            block_secs: 600, maturity: 100},
    # Bitcoin regtest — for end-to-end validation of the whole loop. Same
    # daemon, same rules, port from `-regtest`. Price 0 by construction.
    "RTC": {name: "Bitcoin regtest", rpc_port: 18443,
            gbt_params: "\[{\"rules\":\[\"segwit\"\]}\]",
            txtime: 0, p2pkh_ver: 0x6f,
            gecko_id: "", paprika_id: "",
            block_secs: 600, maturity: 100},
    # Peercoin — hybrid PoW/PoS; PoW blocks are SHA-256d and the PoW
    # difficulty is what getmininginfo reports. v0.15 (Core 25.2 base):
    # transactions are v3 with NO nTime field (RFC-0026), so txtime is 0.
    # PoW reward scales with difficulty — trust the template's
    # coinbasevalue. Coinbase maturity 500. PoS blocks land every few
    # minutes, so templates go stale fast; the mining loop must re-check
    # the tip aggressively.
    "PPC": {name: "Peercoin", rpc_port: 9902,
            gbt_params: "\[{\"rules\":\[\"segwit\"\]}\]",
            txtime: 0, p2pkh_ver: 0x37,
            gecko_id: "peercoin", paprika_id: "ppc-peercoin",
            block_secs: 600, maturity: 500},
    # Deutsche eMark — peercoin-lineage hybrid (PoW blocks SHA-256d).
    # OLD lineage (0.8-era fork): transactions carry nTime; the coinbase
    # must echo the block time.
    "DEM": {name: "Deutsche eMark", rpc_port: 6662,
            gbt_params: "\[\]",
            txtime: 1, p2pkh_ver: 0x35,
            gecko_id: "deutsche-emark", paprika_id: "dem-deutsche-emark",
            block_secs: 120, maturity: 100},
    # Titcoin — Bitcoin 0.16.3 fork, 60s blocks, no auxpow.
    "TIT": {name: "Titcoin", rpc_port: 8697,
            gbt_params: "\[{\"rules\":\[\"segwit\"\]}\]",
            txtime: 0, p2pkh_ver: -1,
            gecko_id: "titcoin", paprika_id: "tit-titcoin",
            block_secs: 60, maturity: 100},
    # Mazacoin — Bitcoin fork, KGW retarget.
    "MZC": {name: "Mazacoin", rpc_port: 12832,
            gbt_params: "\[\]",
            txtime: 0, p2pkh_ver: 0x32,
            gecko_id: "mazacoin", paprika_id: "mzc-mazacoin",
            block_secs: 120, maturity: 100},
    # Joulecoin — Bitcoin fork, 45s blocks.
    "XJO": {name: "Joulecoin", rpc_port: 8844,
            gbt_params: "\[\]",
            txtime: 0, p2pkh_ver: 0x2b,
            gecko_id: "joulecoin", paprika_id: "xjo-joulecoin",
            block_secs: 45, maturity: 100},
    # Zetacoin — Bitcoin fork, 30s blocks.
    "ZET": {name: "Zetacoin", rpc_port: 9332,
            gbt_params: "\[\]",
            txtime: 0, p2pkh_ver: 0x50,
            gecko_id: "zetacoin", paprika_id: "zet-zetacoin",
            block_secs: 30, maturity: 100},
    # Unbreakable — Bitcoin fork.
    "UNB": {name: "Unbreakable", rpc_port: 6335,
            gbt_params: "\[\]",
            txtime: 0, p2pkh_ver: 0x19,
            gecko_id: "unbreakablecoin", paprika_id: "unb-unbreakablecoin",
            block_secs: 300, maturity: 100},
    # Freicoin — Bitcoin lineage with demurrage; templates are standard
    # but rewards decay. Verify template fields before first real run.
    "FRC": {name: "Freicoin", rpc_port: 8638,
            gbt_params: "\[{\"rules\":\[\"segwit\"\]}\]",
            txtime: 0, p2pkh_ver: 0x00,
            gecko_id: "freicoin", paprika_id: "frc-freicoin",
            block_secs: 600, maturity: 100},
    # Auroracoin — a 5-algo (Myriad-lineage) chain; getblocktemplate takes
    # the algorithm as a SECOND positional param, so we request sha256d
    # explicitly, and the template's `version` carries the sha256d algo bits
    # (the miner uses it verbatim, so the double-SHA256 PoW is exactly what
    # the network expects). It is the reason this switcher takes difficulty
    # from the template nBits: AUR's explorers and its own `getblock` report
    # a sha256d "difficulty" of ~2,135, but that is a PER-ALGO NORMALIZED
    # figure (same value across all five algorithms). The real absolute work
    # — 2**256/target from the template bits — is ~9e16 hashes, i.e. ~500
    # days/block at 2.1 GH/s. So the miner correctly ranks AUR at ~$0/day
    # rather than being fooled into mining it. Kept as the worked example of
    # a multi-algo coin the switcher handles and correctly declines.
    "AUR": {name: "Auroracoin (sha256d)", rpc_port: 12341,
            gbt_params: "\[{\"rules\":\[\"segwit\"\]}, \"sha256d\"\]",
            txtime: 0, p2pkh_ver: 23,
            gecko_id: "auroracoin", paprika_id: "aur-auroracoin",
            block_secs: 300, maturity: 100},
  }

# One coin's entry, or nil.
-> coins_get(ticker)
  coins_registry()[ticker]

# The 256-bit proof-of-work target as a single integer, built big-endian
# from btc_target_from_bits's 8 words. Tungsten ints promote to BigInt, so
# this is exact for the full 256-bit range. Returns nil for an nBits the
# protocol rejects.
-> coins_target_int(bits)
  t = btc_target_from_bits(bits)
  if t == nil
    return nil
  v = 0
  i = 0 ## i64
  while i < 8
    v = (v << 32) | (t[i] & 0xFFFFFFFF)
    i += 1
  v

# Expected hashes to find one block: 2**256 / (target + 1), exactly, as an
# integer. This is THE stable primitive the economics are built on — it
# never touches a float, so it is immune to the decimal-mantissa overflow
# that chained float division hits (a diff-1 target divided down toward
# 256^-3 wraps negative; see the history in coins_blocks_per_day). For a
# diff-1 target it is ~2**32; for a low-diff altcoin (RBL ~7k) ~3e13; for a
# mainnet-scale target a 20-digit bignum.
COINS_TWO256 = 1 << 256
-> coins_hashes_per_block(bits)
  ti = coins_target_int(bits)
  if ti == nil
    return nil
  COINS_TWO256 / (ti + 1)

# num/den as a fixed-point decimal STRING with `frac_digits` places, using
# integer arithmetic only. This is the one bridge from the 256-bit domain
# back to a printable/parseable number: `num` and `den` may be BigInt, but
# every operation here is integer division, modulo, and .to_s — all of
# which BigInt supports on both engines. (Float literals are
# arbitrary-precision decimals whose mantissa overflows under chained
# division, and BigInt->float is interpreter-unsupported, so neither float
# path is safe here.) The returned string parses with .to_f for arithmetic
# or prints directly.
-> coins_ratio_str(num, den, frac_digits)
  if den <= 0
    return "0.0"
  whole = num / den
  rem = num % den
  p = 1
  i = 0 ## i64
  while i < frac_digits
    p = p * 10
    i += 1
  frac = (rem * p) / den
  fs = frac.to_s
  z = ""
  pad = frac_digits - fs.size ## i64
  while pad > 0
    z = z + "0"
    pad -= 1
  whole.to_s + "." + z + fs

# Difficulty (relative to diff-1), for DISPLAY only, as a float. Ranking
# never uses this; it uses hashes-per-block directly. Exact to 3 places
# across the whole range, including mainnet-scale (whole part stays BigInt
# in the string, so nothing overflows).
-> coins_difficulty_from_bits(bits)
  h = coins_hashes_per_block(bits)
  if h == nil
    return 0.0
  coins_ratio_str(h, 4294967296, 3).to_f

# Expected blocks/day for `hashrate` H/s:
#   blocks/day = hashrate * 86400 / hashes_per_block
# hashes-per-block is exact; the ratio is composed to 6 places as a string
# and parsed. A mainnet-scale hashes-per-block simply yields "0.000000".
-> coins_blocks_per_day_bits(hashrate_int, bits)
  h = coins_hashes_per_block(bits)
  if h == nil
    return 0.0
  work = hashrate_int * 86400
  coins_ratio_str(work, h, 6).to_f

# Retained float form for callers that already hold a difficulty value
# (e.g. tests). Single division, so it does not hit the decimal overflow.
-> coins_blocks_per_day(hashrate, difficulty)
  if difficulty <= 0.0
    return 0.0
  (hashrate / 4294967296.0) * 86400.0 / difficulty

# Expected revenue in USD/day.
#   hashrate_int  integer H/s the coin will be mined at
#   bits          the template's compact target
#   reward_units  the template's coinbasevalue, in base units (satoshi-like)
#   price         USD per whole coin
# Assumes 1e8 base units per coin, which holds across the Bitcoin lineage.
-> coins_revenue_per_day(hashrate_int, bits, reward_units, price)
  if price <= 0.0
    return 0.0
  bpd = coins_blocks_per_day_bits(hashrate_int, bits)
  bpd * (reward_units / 100000000.0) * price
