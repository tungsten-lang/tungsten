# Live USD prices for mined coins, over HTTPS.
#
# The profitability ranking is only as honest as its freshest price — a
# switcher that cements yesterday's quote mines the wrong coin all day. So
# this module is a *fetcher*, called on every evaluation cycle; nothing here
# caches beyond what the caller decides to hold.
#
# Two independent sources, tried in order:
#
#   CoinPaprika  GET /v1/tickers/<id>        "USD":{"price":N
#   CoinGecko    GET /api/v3/simple/price    "<id>":{"usd":N
#
# Both are free, keyless, and list even the long-dead coins this miner
# targets.
#
# Transport is Core HTTP over the runtime's verified in-process TLS client;
# no child process or temporary response file is involved.
#
# Prices for dead-ish coins are routinely 1e-5 .. 1e-9 USD, which JSON
# serializers emit in exponent notation, so the number parser here handles
# the full float grammar rather than leaning on JSON.parse.

# One bounded HTTPS GET through Core's verified in-process TLS transport.
# Returns the response body on a successful HTTP status, or nil on failure.
-> price_http(url)
  body = nil
  begin
    headers = {"Accept": "application/json", "User-Agent": "Tungsten Crypto"}
    response = HTTP.request("GET", url, headers, nil, 15_000, 2_097_152)
    if response.success?()
      body = response.body
  rescue e
    body = nil
  body

# Parse the float starting at byte index `i` of `s`: -?digits[.digits][e±n].
# Returns -1.0 when there is no number there. Good to ~15 significant
# digits, which is beyond what any price feed serves.
-> price_parse_float(s, i)
  bs = s.bytes
  n = s.size
  sign = 1.0
  if i < n && bs[i] == 45
    sign = -1.0
    i += 1
  if i >= n
    return -1.0
  c = bs[i]
  if c < 48 || c > 57
    return -1.0
  mant = 0.0
  while i < n
    c = bs[i]
    if c >= 48 && c <= 57
      mant = mant * 10.0 + (c - 48) * 1.0
      i += 1
    else
      break
  frac = 0 ## i64
  if i < n && bs[i] == 46
    i += 1
    while i < n
      c = bs[i]
      if c >= 48 && c <= 57
        mant = mant * 10.0 + (c - 48) * 1.0
        frac += 1
        i += 1
      else
        break
  ex = 0 ## i64
  exsign = 1 ## i64
  if i < n && (bs[i] == 101 || bs[i] == 69)
    i += 1
    if i < n && bs[i] == 45
      exsign = -1
      i += 1
    elsif i < n && bs[i] == 43
      i += 1
    while i < n
      c = bs[i]
      if c >= 48 && c <= 57
        ex = ex * 10 + (c - 48)
        i += 1
      else
        break
  scale = ex * exsign - frac
  v = mant
  while scale > 0
    v = v * 10.0
    scale -= 1
  while scale < 0
    v = v / 10.0
    scale += 1
  v * sign

# Find `key` in `body` and parse the number that follows it, skipping
# whitespace after the colon. Returns -1.0 when absent.
-> price_extract(body, key)
  if body == nil
    return -1.0
  at = body.index(key)
  if at == nil
    return -1.0
  i = at + key.size
  bs = body.bytes
  while i < body.size
    c = bs[i]
    if c == 32 || c == 58 || c == 9
      i += 1
    else
      break
  price_parse_float(body, i)

# CoinPaprika: the USD quote lives at quotes.USD.price.
-> price_from_paprika(id)
  body = price_http("https://api.coinpaprika.com/v1/tickers/" + id)
  if body == nil
    return -1.0
  at = body.index("\"USD\"")
  if at == nil
    return -1.0
  tail = body.slice(at, body.size - at)
  price_extract(tail, "\"price\":")

# CoinGecko: {"<id>":{"usd":N}}.
-> price_from_gecko(id)
  body = price_http("https://api.coingecko.com/api/v3/simple/price?ids=" + id + "&vs_currencies=usd")
  if body == nil
    return -1.0
  at = body.index("\"" + id + "\"")
  if at == nil
    return -1.0
  tail = body.slice(at, body.size - at)
  price_extract(tail, "\"usd\":")

# One CoinGecko request for many coins: ids joined with commas, answer is
# {"id1":{"usd":n1},"id2":{"usd":n2},...}. Returns a hash of id -> price
# for every id that came back with a positive quote; absent ids are simply
# missing (caller falls back per-coin). This keeps the switcher's steady-
# state price load at ONE request per evaluation cycle regardless of how
# many coins are registered.
-> price_gecko_multi(ids)
  out = {}
  if ids.size == 0
    return out
  joined = ""
  i = 0
  while i < ids.size
    if i > 0
      joined = joined + ","
    joined = joined + ids[i]
    i += 1
  body = price_http("https://api.coingecko.com/api/v3/simple/price?ids=" + joined + "&vs_currencies=usd")
  if body == nil
    return out
  i = 0
  while i < ids.size
    id = ids[i]
    at = body.index("\"" + id + "\"")
    if at != nil
      tail = body.slice(at, body.size - at)
      p = price_extract(tail, "\"usd\":")
      if p > 0.0
        out[id] = p
    i += 1
  out

# The USD price for a coin, trying every source it is listed on. Sources
# are independent businesses with independent outages; either alone is a
# single point of failure for the whole ranking. -1.0 means no source
# answered — the caller must skip the coin, not treat it as free.
#
# CoinGecko first: CoinPaprika's free tier is 60 requests/hour and blocks
# the IP for a full hour on breach, so it is strictly the fallback.
-> price_usd(paprika_id, gecko_id)
  if gecko_id != ""
    p = price_from_gecko(gecko_id)
    if p > 0.0
      return p
  if paprika_id != ""
    p = price_from_paprika(paprika_id)
    if p > 0.0
      return p
  -1.0
