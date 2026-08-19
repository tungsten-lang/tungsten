# Bitcoin peer-to-peer protocol: framing, handshake, and header sync.
#
# WHAT THIS IS
# ------------
# A real P2P client. It speaks the wire protocol directly to a Bitcoin node —
# no JSON-RPC, no trusted intermediary — performs the version/verack
# handshake, and downloads the block-header chain with `getheaders`.
#
# Because every header carries its own proof of work, a synced header chain
# can be verified independently: each header must hash below its stated
# target, and must name its predecessor. That is genuine, checkable sync of
# the chain's skeleton, and it reuses the PoW code the miner already has.
#
# WHAT THIS IS NOT
# ----------------
# This is NOT a full node, and header sync must not be mistaken for one. A
# validating node additionally needs the script interpreter, ECDSA/Schnorr
# verification, the UTXO set, and every soft-fork rule (P2SH, CLTV, CSV,
# segwit, taproot) applied exactly as the network applies them. Getting any
# one of those subtly wrong does not produce a bug — it produces a chain
# split, where you believe a different history than everyone else.
#
# Header sync tells you which chain has the most work. It does NOT tell you
# that the blocks on it are valid, that their transactions are authorized,
# or that any coin you see is real. Do not make money decisions on it alone.
#
# Message frame:
#   magic(4) | command(12, NUL-padded) | length(4 LE) | checksum(4) | payload
# where checksum is the first 4 bytes of double-SHA256(payload).

use bitcoin

P2P_MAGIC_MAIN = "f9beb4d9"
P2P_MAGIC_TESTNET = "0b110907"
P2P_MAGIC_REGTEST = "fabfb5da"
P2P_PROTOCOL_VERSION = 70016

-> p2p_magic(network)
  if network == "mainnet"
    return P2P_MAGIC_MAIN
  if network == "testnet"
    return P2P_MAGIC_TESTNET
  P2P_MAGIC_REGTEST

# ---- little-endian byte writers -------------------------------------------
#
# Payloads are built as byte arrays rather than hex strings: they go straight
# out over a socket, and some fields (user agent) are raw text.

-> p2p_buf(cap)
  {bytes: i64[cap], len: 0}

-> p2p_push(buf, v)
  a = buf[:bytes]
  a[buf[:len]] = v & 0xFF
  buf[:len] = buf[:len] + 1
  0

-> p2p_push_u16(buf, v)
  p2p_push(buf, v)
  p2p_push(buf, v >> 8)

-> p2p_push_u32(buf, v)
  p2p_push(buf, v)
  p2p_push(buf, v >> 8)
  p2p_push(buf, v >> 16)
  p2p_push(buf, v >> 24)

-> p2p_push_u64(buf, v)
  p2p_push_u32(buf, v & 0xFFFFFFFF)
  p2p_push_u32(buf, (v >> 32) & 0xFFFFFFFF)

-> p2p_push_bytes(buf, arr, n)
  i = 0
  while i < n
    p2p_push(buf, arr[i])
    i += 1
  0

-> p2p_push_hex(buf, hex)
  b = btc_hex_to_bytes(hex)
  p2p_push_bytes(buf, b, hex.size / 2)

-> p2p_push_varint(buf, n)
  if n < 0xFD
    return p2p_push(buf, n)
  if n <= 0xFFFF
    p2p_push(buf, 0xFD)
    return p2p_push_u16(buf, n)
  if n <= 0xFFFFFFFF
    p2p_push(buf, 0xFE)
    return p2p_push_u32(buf, n)
  p2p_push(buf, 0xFF)
  p2p_push_u64(buf, n)

-> p2p_push_str(buf, s)
  bs = s.bytes.to_a
  p2p_push_varint(buf, bs.size)
  p2p_push_bytes(buf, bs, bs.size)

# ---- framing ---------------------------------------------------------------

# Wrap a payload in a network message. Returns {bytes:, len:}.
-> p2p_frame(magic_hex, command, payload, plen, k)
  msg = p2p_buf(plen + 32)
  p2p_push_hex(msg, magic_hex)
  # Command is 12 bytes, NUL-padded.
  cb = command.bytes.to_a
  i = 0
  while i < 12
    if i < cb.size
      p2p_push(msg, cb[i])
    else
      p2p_push(msg, 0)
    i += 1
  p2p_push_u32(msg, plen)
  # Checksum: first 4 bytes of double-SHA256 over the payload. An empty
  # payload still gets the double-SHA of the empty string.
  dg = sha256d_bytes(payload, plen, k)
  p2p_push(msg, (dg[0] >> 24) & 0xFF)
  p2p_push(msg, (dg[0] >> 16) & 0xFF)
  p2p_push(msg, (dg[0] >> 8) & 0xFF)
  p2p_push(msg, dg[0] & 0xFF)
  p2p_push_bytes(msg, payload, plen)
  msg

# The `version` payload — the first thing either side sends.
-> p2p_version_payload(height, now)
  p = p2p_buf(256)
  p2p_push_u32(p, P2P_PROTOCOL_VERSION)
  p2p_push_u64(p, 0)                 # services: none, we are not serving
  p2p_push_u64(p, now)               # timestamp
  # addr_recv and addr_from: services + 16-byte IPv6 + port. Peers ignore
  # the contents from a non-listening client, so zeros are fine.
  j = 0
  while j < 2
    p2p_push_u64(p, 0)
    i = 0
    while i < 16
      p2p_push(p, 0)
      i += 1
    p2p_push_u16(p, 0)
    j += 1
  p2p_push_u64(p, 0x1234567890abcdef)  # nonce, detects self-connection
  p2p_push_str(p, "/tungsten-crypto:0.1.0/")
  p2p_push_u32(p, height)
  p2p_push(p, 0)                     # relay = false: headers only, no mempool
  p

# `getheaders`: ask for up to 2000 headers after the given locator hash.
-> p2p_getheaders_payload(locator_hex, stop_hex)
  p = p2p_buf(128)
  p2p_push_u32(p, P2P_PROTOCOL_VERSION)
  p2p_push_varint(p, 1)
  lb = btc_hash_hex_to_internal(locator_hex)
  p2p_push_bytes(p, lb, 32)
  sb = btc_hash_hex_to_internal(stop_hex)
  p2p_push_bytes(p, sb, 32)
  p

# ---- header-chain validation ----------------------------------------------
#
# The part that makes header sync worth anything. Given consecutive 80-byte
# headers, check that each links to its predecessor and satisfies its own
# stated proof of work. Both are cheap and both are checkable locally.
#
# NOTE what this does NOT check: that `bits` is the value the retarget rule
# demands. A peer could feed a low-difficulty chain that is internally
# consistent. Real SPV clients compare total work across peers; this returns
# the work so a caller can do that.
-> p2p_verify_header_chain(headers, count, prev_hash_hex, k)
  prev = prev_hash_hex
  i = 0 ## i64
  while i < count
    h = headers[i]
    got_prev = btc_bytes_to_hex(p2p_slice(h, 4, 32), 32)
    want = btc_hash_hex_to_internal(prev)
    if got_prev != btc_bytes_to_hex(want, 32)
      return {ok: 0, at: i, reason: "chain break"}
    bits = h[72] | (h[73] << 8) | (h[74] << 16) | (h[75] << 24)
    target = btc_target_from_bits(bits)
    if target == nil
      return {ok: 0, at: i, reason: "invalid nBits"}
    if btc_meets_target(btc_header_hash(h, k), target) != 1
      return {ok: 0, at: i, reason: "insufficient proof of work"}
    prev = sha256_hex_le(btc_header_hash(h, k))
    i += 1
  {ok: 1, at: count, tip: prev}

-> p2p_slice(arr, off, n)
  out = i64[n]
  i = 0
  while i < n
    out[i] = arr[off + i]
    i += 1
  out

# ---- live connection -------------------------------------------------------
#
# Everything above is pure computation and testable offline. Below here the
# module talks to an actual peer.

-> p2p_send(sock, magic, command, payload, plen, k)
  f = p2p_frame(magic, command, payload, plen, k)
  n = f[:len]
  out = u8[n]
  b = f[:bytes]
  i = 0 ## i64
  while i < n
    out[i] = b[i]
    i += 1
  sock.write_bytes(out)

# Read exactly n bytes, or nil if the peer closes or the deadline fires.
# Socket reads are short reads, so this loops.
-> p2p_read_exact(sock, n)
  out = u8[n]
  got = 0 ## i64
  while got < n
    chunk = sock.read_exact(n - got)
    if chunk == nil
      return nil
    m = chunk.size
    if m == 0
      return nil
    i = 0 ## i64
    while i < m
      out[got + i] = chunk[i]
      i += 1
    got += m
  out

# Read one framed message. Returns {command:, payload:, len:} or nil.
# The 4-byte magic is resynchronized on rather than trusted, because a peer
# that sends something unexpected should not desync the stream permanently.
-> p2p_recv(sock, magic, k)
  hdr = p2p_read_exact(sock, 24)
  if hdr == nil
    return nil
  mg = btc_bytes_to_hex(p2p_u8_slice(hdr, 0, 4), 4)
  if mg != magic
    return {command: "?desync", payload: nil, len: 0}
  cmd = ""
  i = 4 ## i64
  while i < 16
    if hdr[i] != 0
      cmd = cmd + hdr[i].chr
    i += 1
  plen = hdr[16] | (hdr[17] << 8) | (hdr[18] << 16) | (hdr[19] << 24)
  # A hostile or broken peer must not be able to make us allocate wildly.
  # Bitcoin's own limit is 32 MiB; anything larger is a protocol violation.
  if plen < 0 || plen > 33554432
    return nil
  payload = nil
  if plen > 0
    payload = p2p_read_exact(sock, plen)
    if payload == nil
      return nil
  {command: cmd, payload: payload, len: plen}

-> p2p_u8_slice(arr, off, n)
  out = i64[n]
  i = 0 ## i64
  while i < n
    out[i] = arr[off + i]
    i += 1
  out

# Connect and complete the version/verack handshake. Returns the socket, or
# nil. `sendheaders`/`sendcmpct` and other chatter from the peer is ignored;
# we only need verack to consider the link up.
-> p2p_connect(host, port, network, height, now, k)
  magic = p2p_magic(network)
  # The ENTIRE handshake is guarded, not just the connect. A node that is at
  # its peer limit accepts the TCP connection and then drops it immediately,
  # which surfaces as `write_bytes failed` from the very first send — a raise,
  # not a nil. That is the common case when dialing public seeds, so it has to
  # be an ordinary "try the next peer", never a crash.
  sock = nil
  begin
    sock = Socket.connect(host, port)
    if sock == nil
      return nil
    sock.set_timeout(15000)
    v = p2p_version_payload(height, now)
    p2p_send(sock, magic, "version", v[:bytes], v[:len], k)
    got_verack = 0
    got_version = 0
    tries = 0 ## i64
    while tries < 20 && (got_verack == 0 || got_version == 0)
      m = p2p_recv(sock, magic, k)
      if m == nil
        sock.close
        return nil
      c = m[:command]
      if c == "version"
        got_version = 1
        empty = i64[1]
        p2p_send(sock, magic, "verack", empty, 0, k)
      elsif c == "verack"
        got_verack = 1
      tries += 1
    if got_verack == 0
      sock.close
      return nil
    return {sock: sock, magic: magic}
  rescue e
    return nil

# The DNS seeds Bitcoin Core itself ships. Each resolves to a rotating set of
# live peers, and Socket.connect goes through getaddrinfo, so handing it a
# seed name connects straight to one of them — no resolver code needed here.
-> p2p_mainnet_seeds
  ["seed.bitcoin.sipa.be", "dnsseed.bluematt.me", "seed.bitcoin.sprovoost.nl",
   "dnsseed.emzy.de", "seed.btc.petertodd.net", "seed.bitcoin.wiz.biz",
   "seed.bitcoinstats.com", "seed.bitcoin.jonasschnelli.ch"]

# Connect to the first peer that completes a handshake. Peers refuse
# constantly — at their limit, mid-restart, or simply gone — so trying one
# and giving up is not good enough for the public network.
-> p2p_connect_any(hosts, port, network, height, now, k)
  i = 0 ## i64
  while i < hosts.size
    conn = p2p_connect(hosts[i], port, network, height, now, k)
    if conn != nil
      conn[:host] = hosts[i]
      return conn
    i += 1
  nil

# Ask for headers after `locator_hex` and parse the reply.
#
# A `headers` payload is a varint count followed by that many 81-byte
# records: an 80-byte header plus a always-zero transaction-count byte.
# Returns a list of 80-byte headers, or nil.
-> p2p_get_headers(conn, locator_hex, k)
  sock = conn[:sock]
  magic = conn[:magic]
  zero = "0000000000000000000000000000000000000000000000000000000000000000"
  gh = p2p_getheaders_payload(locator_hex, zero)
  p2p_send(sock, magic, "getheaders", gh[:bytes], gh[:len], k)
  tries = 0 ## i64
  while tries < 40
    m = p2p_recv(sock, magic, k)
    if m == nil
      return nil
    if m[:command] == "ping"
      # A peer that gets no pong will eventually drop us, and the pong must
      # echo the nonce it sent.
      if m[:len] >= 8
        pl = p2p_buf(8)
        i = 0 ## i64
        while i < 8
          p2p_push(pl, m[:payload][i])
          i += 1
        p2p_send(sock, magic, "pong", pl[:bytes], pl[:len], k)
    elsif m[:command] == "headers"
      return p2p_parse_headers(m[:payload], m[:len])
    tries += 1
  nil

-> p2p_parse_headers(payload, plen)
  if payload == nil || plen < 1
    return []
  pos = 0 ## i64
  n = payload[0] ## i64
  pos = 1
  if n == 0xFD
    n = payload[1] | (payload[2] << 8)
    pos = 3
  elsif n == 0xFE
    n = payload[1] | (payload[2] << 8) | (payload[3] << 16) | (payload[4] << 24)
    pos = 5
  elsif n == 0xFF
    return []
  out = []
  i = 0 ## i64
  while i < n
    if pos + 81 > plen
      return out
    h = i64[80]
    j = 0 ## i64
    while j < 80
      h[j] = payload[pos + j]
      j += 1
    out.push(h)
    pos += 81
    i += 1
  out

# Sync the header chain from `start_hex` forward, verifying every header's
# proof of work and linkage as it arrives. Stops when the peer stops sending
# or `max_headers` is reached.
#
# Returns {tip:, height:, count:, bits:} where `bits` is the nBits of the
# last header — which is what a miner needs to build the next block.
-> p2p_sync_headers(conn, start_hex, start_height, max_headers, k)
  tip = start_hex
  height = start_height ## i64
  total = 0 ## i64
  last_bits = 0 ## i64
  last_time = 0 ## i64
  rounds = 0 ## i64
  while total < max_headers && rounds < 2000
    hs = p2p_get_headers(conn, tip, k)
    if hs == nil || hs.size == 0
      return {tip: tip, height: height, count: total, bits: last_bits,
              time: last_time, done: 1}
    v = p2p_verify_header_chain(hs, hs.size, tip, k)
    if v[:ok] != 1
      return {tip: tip, height: height, count: total, bits: last_bits,
              error: v[:reason], at: v[:at]}
    tip = v[:tip]
    height += hs.size
    total += hs.size
    h = hs[hs.size - 1]
    last_bits = h[72] | (h[73] << 8) | (h[74] << 16) | (h[75] << 24)
    last_time = h[68] | (h[69] << 8) | (h[70] << 16) | (h[71] << 24)
    rounds += 1
  {tip: tip, height: height, count: total, bits: last_bits, time: last_time, done: 0}
