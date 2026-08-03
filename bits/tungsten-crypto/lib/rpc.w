# Bitcoin Core JSON-RPC client.
#
# Speaks HTTP/1.1 directly over a socket because the tree has no
# general-purpose HTTP client — core/ has none, and the only complete one
# (bits/tungsten-forge/lib/acme/http_client.w) is namespaced under ACME and
# defaults to ACME's content type. bitcoind's RPC surface is small and
# entirely POST-with-basic-auth, so a focused client is the smaller thing.
#
# Connection handling: one connection per call, `Connection: close`, read to
# EOF. bitcoind's default rpcworkqueue handles this comfortably at the rate
# a miner polls (once per block template, not once per hash), and it avoids
# a keep-alive state machine that would buy nothing here.

use bitcoin

# ---- transport ------------------------------------------------------------

# Perform one JSON-RPC call. Returns the parsed `result` value, or nil on
# transport failure or an RPC-level error. `err` receives a diagnostic.
-> btc_rpc_call(host, port, user, pass, method, params)
  body = btc_rpc_request_body(method, params)
  auth = Base64.encode(user + ":" + pass)
  req = "POST / HTTP/1.1\r\n"
  req = req + "Host: " + host + ":" + port.to_s + "\r\n"
  req = req + "Authorization: Basic " + auth + "\r\n"
  req = req + "Content-Type: application/json\r\n"
  req = req + "Content-Length: " + body.size.to_s + "\r\n"
  req = req + "Connection: close\r\n\r\n"
  req = req + body
  # A miner must survive its node going away — a refused connection or a
  # mid-request close is an ordinary event (node restart, reorg, reindex),
  # not a reason to abort the process. Every transport failure becomes nil,
  # which callers already handle.
  raw = ""
  begin
    sock = Socket.connect(host, port)
    if sock == nil
      return nil
    # A read timeout and a peer close both surface as nil from read(), so
    # the deadline bounds a hung daemon; it cannot be told apart from EOF.
    sock.set_timeout(30000)
    sock.write(req)
    loop
      chunk = sock.read(65536)
      break unless chunk
      break if chunk.size == 0
      raw = raw + chunk
    sock.close
  rescue e
    return nil
  btc_rpc_parse_response(raw)

# Split an HTTP response into its body. bitcoind answers a well-formed
# request with an unchunked, Content-Length-delimited body, and this client
# always sends `Connection: close`, so read-to-EOF is the length — no
# chunked decoder is needed. Returns nil if the response has no header
# terminator.
#
# Kept separate from the JSON step because `JSON.parse` is compiled-only
# (core/json.w's class methods call each other bare, which the interpreter
# does not resolve), and this half should stay testable on both engines.
-> btc_rpc_body(raw)
  if raw == nil || raw.size == 0
    return nil
  sep = raw.index("\r\n\r\n")
  if sep == nil
    return nil
  raw.slice(sep + 4, raw.size - sep - 4)

# Split headers from body and hand the body to the JSON parser.
-> btc_rpc_parse_response(raw)
  body = btc_rpc_body(raw)
  if body == nil
    return nil
  parsed = JSON.parse(body)
  if parsed == nil
    return nil
  # bitcoind reports application errors in `error` with a 500 status; the
  # result is null in that case.
  err = parsed["error"]
  if err != nil
    return nil
  parsed["result"]

# Build a JSON-RPC 1.0 request. Params arrive already encoded as JSON text
# so callers can pass structured arguments (getblocktemplate's rules object)
# without this layer needing a general encoder — `JSON.encode` exists but is
# compiled-only, and the miner must also run interpreted.
-> btc_rpc_request_body(method, params)
  "{\"jsonrpc\":\"1.0\",\"id\":\"tungsten\",\"method\":\"" + method + "\",\"params\":" + params + "}"

# ---- typed wrappers -------------------------------------------------------

+ BitcoinRPC
  -> new(@host, @port, @user, @pass)

  -> call(method, params)
    btc_rpc_call(@host, @port, @user, @pass, method, params)

  -> getblockcount
    call("getblockcount", "\[\]")

  -> getbestblockhash
    call("getbestblockhash", "\[\]")

  -> getblockchaininfo
    call("getblockchaininfo", "\[\]")

  # Fetch a block template to mine against. `rules` must include "segwit"
  # for any modern node to answer at all (BIP 9 requires the client to
  # declare which soft-fork rules it understands).
  -> getblocktemplate
    call("getblocktemplate", "\[{\"rules\":\[\"segwit\"\]}\]")

  # The same call with caller-chosen params, verbatim JSON. Old forks
  # predate BIP9 and reject a `rules` argument they do not understand —
  # for those the right params are "\[\]" or "\[{}\]"; the coin registry
  # carries the correct spelling per daemon.
  -> getblocktemplate_p(params)
    call("getblocktemplate", params)

  -> getmininginfo
    call("getmininginfo", "\[\]")

  -> getdifficulty
    call("getdifficulty", "\[\]")

  -> validateaddress(address)
    call("validateaddress", "\[\"" + address + "\"\]")

  # Submit a fully serialized block. Returns nil on acceptance — bitcoind's
  # submitblock answers with a null result when the block is good, and with
  # a rejection reason string when it is not.
  -> submitblock(block_hex)
    call("submitblock", "\[\"" + block_hex + "\"\]")

  # Regtest convenience: generate to an address without mining ourselves,
  # used by the test harness to get a funded chain.
  -> generatetoaddress(n, address)
    call("generatetoaddress", "\[" + n.to_s + ",\"" + address + "\"\]")

  -> getnewaddress
    call("getnewaddress", "\[\]")

  # Ask the node for an address's scriptPubKey. This is how the miner gets a
  # spendable payout script without implementing bech32 or holding any keys:
  # the node's wallet owns the private key, and we only need the output
  # script to put in the coinbase.
  -> getaddressinfo(address)
    call("getaddressinfo", "\[\"" + address + "\"\]")

  # The payout scriptPubKey for `address`, or nil if the node cannot supply
  # one. nil must be treated as fatal by the caller — mining to a script you
  # cannot spend burns the entire block reward.
  #
  # Tries getaddressinfo first (Core 0.17+), then validateaddress — which is
  # where daemons forked from pre-0.17 Core (every 2013-era altcoin) report
  # the scriptPubKey.
  -> payout_script(address)
    info = getaddressinfo(address)
    if info != nil
      s = info["scriptPubKey"]
      if s != nil && s != ""
        return s
    info = validateaddress(address)
    if info == nil
      return nil
    info["scriptPubKey"]
