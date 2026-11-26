# core/net/websocket — High-performance RFC 6455 WebSocket Client & Framing Engine
#
# Features:
#   - Full RFC 6455 handshake (`ws://` over TCP and `wss://` over TLS 1.3/1.2 via core/net/tls13)
#   - Subprotocol negotiation (`Sec-WebSocket-Protocol`) & custom headers (`Origin`, `Cookie`, etc.)
#   - RFC 7692 `permessage-deflate` extension (stateless no_context_takeover using core/gzip raw DEFLATE)
#   - Fast 4-byte-unrolled XOR masking directly in ByteArray (`ws_mask_inplace`)
#   - Buffered socket reads + single-write frame coalescing (zero double-syscall Nagle stalls)
#   - Automatic Ping/Pong keepalive heartbeat thread with configurable interval, dead-peer pong timeout,
#     and live RTT measurement (`rtt_ms`, `pings_sent`, `pongs_received`)
#   - Fragmented message reassembly (text UTF-8, binary ByteArray) + control-frame interleaving
#   - Clean RFC 6455 Close handshake (status codes 1000..1015 + reason)
#   - Thread-safe async event queue (`start_async()`, `poll_events()`) for browser JS `WebSocket` integration

use core/crypto/bytes
use core/crypto/chacha
use core/crypto/curve25519
use core/crypto/mlkem
use core/crypto/pkfast
use core/crypto/x509
use core/net/tls13
use core/gzip

WS_RFC_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

WS_OP_CONT   = 0
WS_OP_TEXT   = 1
WS_OP_BINARY = 2
WS_OP_CLOSE  = 8
WS_OP_PING   = 9
WS_OP_PONG   = 10

WS_STATE_CONNECTING = 0
WS_STATE_OPEN       = 1
WS_STATE_CLOSING    = 2
WS_STATE_CLOSED     = 3

-> ws_now_ms
  (clock() * ~1000.0).to_i

-> ws_compute_accept(key)
  Base64.encode(Crypto.sha1_bytes(bytes_of(key.strip + WS_RFC_GUID)))

# Fast 4-byte-unrolled XOR masking in place on ByteArray[offset, len).
-> ws_mask_inplace(buf, offset, len, mask)
  return buf if len <= 0 || mask == nil
  m0 = mask[0]
  m1 = mask[1]
  m2 = mask[2]
  m3 = mask[3]
  i = 0
  lim = len - 3
  while i < lim
    p = offset + i
    buf[p] = buf[p] ^ m0
    buf[p + 1] = buf[p + 1] ^ m1
    buf[p + 2] = buf[p + 2] ^ m2
    buf[p + 3] = buf[p + 3] ^ m3
    i += 4
  while i < len
    p = offset + i
    buf[p] = buf[p] ^ mask[i & 3]
    i += 1
  buf

# Raw DEFLATE compress for RFC 7692 permessage-deflate (strips gzip 10-byte header + 8-byte trailer).
-> ws_deflate_payload(raw_bytes)
  gz = Gzip.compress(raw_bytes, 6)
  return raw_bytes if gz == nil || gz.size < 18
  # Raw DEFLATE stream sits between byte 10 and gz.size - 8.
  defl = bslice(gz, 10, gz.size - 18)
  defl

# Raw DEFLATE inflate for RFC 7692 permessage-deflate (appends 00 00 FF FF if needed).
-> ws_inflate_payload(comp_bytes)
  begin
    return Gzip.inflate(comp_bytes)
  rescue e
    # RFC 7692 strips trailing 0x00 0x00 0xFF 0xFF sync-flush marker on non-final blocks.
    tail = ByteArray.new(4)
    tail[0] = 0
    tail[1] = 0
    tail[2] = 255
    tail[3] = 255
    return Gzip.inflate(bcat(comp_bytes, tail))

# Build a complete RFC 6455 wire frame in a single contiguous ByteArray (zero double-write syscalls).
-> ws_encode_frame(opcode, payload, masked = false, rsv1 = false, fin = true)
  p = payload == nil ? ByteArray.new(0) : payload
  n = p.size
  hdr_len = 2
  if n >= 65536
    hdr_len = 10
  elsif n >= 126
    hdr_len = 4
  hdr_len += 4 if masked
  out = ByteArray.new(hdr_len + n)
  b0 = (fin ? 0x80 : 0) | (rsv1 ? 0x40 : 0) | (opcode & 0x0F)
  out[0] = b0
  mbit = masked ? 0x80 : 0
  pos = 2
  if n < 126
    out[1] = mbit | n
  elsif n < 65536
    out[1] = mbit | 126
    out[2] = (n >> 8) & 255
    out[3] = n & 255
    pos = 4
  else
    out[1] = mbit | 127
    out[2] = (n >> 56) & 255
    out[3] = (n >> 48) & 255
    out[4] = (n >> 40) & 255
    out[5] = (n >> 32) & 255
    out[6] = (n >> 24) & 255
    out[7] = (n >> 16) & 255
    out[8] = (n >> 8) & 255
    out[9] = n & 255
    pos = 10
  mask = nil
  if masked
    mask = brand(4)
    out[pos] = mask[0]
    out[pos + 1] = mask[1]
    out[pos + 2] = mask[2]
    out[pos + 3] = mask[3]
    pos += 4
  if n > 0
    bmove(out, pos, p, 0, n)
    ws_mask_inplace(out, pos, n, mask) if masked
  out

-> ws_close_payload(code, reason = "")
  rb = reason == nil || reason == "" ? ByteArray.new(0) : bytes_of(reason)
  out = ByteArray.new(2 + rb.size)
  out[0] = (code >> 8) & 255
  out[1] = code & 255
  bmove(out, 2, rb, 0, rb.size) if rb.size > 0
  out

-> ws_parse_close_payload(payload)
  return [1005, ""] if payload == nil || payload.size < 2
  code = (payload[0] << 8) | payload[1]
  reason = payload.size > 2 ? str_of(bslice(payload, 2, payload.size - 2)) : ""
  [code, reason]

# Parse ws:// or wss:// URL -> {scheme, host, port, path, tls}
-> ws_parse_url(url_str)
  return nil if url_str == nil
  s = url_str.to_s.strip
  tls = false
  rest = ""
  if s.starts_with?("wss://")
    tls = true
    rest = s.slice(6, s.size - 6)
  elsif s.starts_with?("ws://")
    tls = false
    rest = s.slice(5, s.size - 5)
  else
    return nil
  slash = rest.index("/")
  qmark = rest.index("?")
  cut = rest.size
  cut = slash if slash != nil && slash < cut
  cut = qmark if qmark != nil && qmark < cut
  auth = rest.slice(0, cut)
  path = cut < rest.size ? rest.slice(cut, rest.size - cut) : "/"
  path = "/" + path if !path.starts_with?("/")
  host = auth
  port = tls ? 443 : 80
  if auth.starts_with?('[')
    rb = auth.index(']')
    return nil if rb == nil
    host = auth.slice(1, rb - 1)
    if rb + 1 < auth.size && auth.byte_at(rb + 1) == 58
      port = auth.slice(rb + 2, auth.size - rb - 2).to_i
  else
    col = auth.rindex(":")
    if col != nil
      host = auth.slice(0, col)
      port = auth.slice(col + 1, auth.size - col - 1).to_i
  return nil if host == "" || port <= 0 || port > 65535
  {scheme: tls ? "wss" : "ws", host: host, port: port, path: path, tls: tls}

# Internal byte transport wrapping either a plain TcpSocket or a TlsConn.
+ WsTransport
  rw :tls, :sock, :tls_conn, :rbuf, :rpos, :rend, :closed

  -> new(@tls, @sock, @tls_conn)
    @rbuf = ByteArray.new(65536)
    @rpos = 0
    @rend = 0
    @closed = false

  -> push_leftover(b)
    return nil if b == nil || b.size == 0
    if b.size > @rbuf.size
      @rbuf = ByteArray.new(b.size + 16384)
    bmove(@rbuf, 0, b, 0, b.size)
    @rpos = 0
    @rend = b.size
    nil

  -> write_bytes(b)
    return false if @closed
    begin
      if @tls
        @tls_conn.write(b)
      else
        @sock.write_bytes(b)
      return true
    rescue e
      @closed = true
      return false

  -> read_exact(n)
    return ByteArray.new(0) if n <= 0
    while @rend - @rpos < n
      return nil if @closed
      keep = @rend - @rpos
      if keep == 0
        @rpos = 0
        @rend = 0
      elsif @rpos > 0 && @rbuf.size - @rend < 16384
        bmove(@rbuf, 0, @rbuf, @rpos, keep)
        @rpos = 0
        @rend = keep
      if @rbuf.size - @rpos < n
        ncap = @rbuf.size * 2
        ncap = n + 32768 if ncap < n + 32768
        nb = ByteArray.new(ncap)
        bmove(nb, 0, @rbuf, @rpos, keep) if keep > 0
        @rbuf = nb
        @rpos = 0
        @rend = keep
      if @tls
        chunk = nil
        begin
          chunk = @tls_conn.read()
        rescue e
          @closed = true
          return nil
        if chunk == nil || chunk.size == 0
          @closed = true
          return nil
        if @rend + chunk.size > @rbuf.size
          nb = ByteArray.new(@rend + chunk.size + 16384)
          bmove(nb, 0, @rbuf, @rpos, @rend - @rpos)
          @rend = @rend - @rpos
          @rpos = 0
          @rbuf = nb
        bmove(@rbuf, @rend, chunk, 0, chunk.size)
        @rend += chunk.size
      else
        need = n - (@rend - @rpos)
        got = nil
        begin
          got = @sock.read_into(@rbuf, @rend, need)
        rescue e
          @closed = true
          return nil
        if got == nil || got <= 0
          @closed = true
          return nil
        @rend += got
    out = bslice(@rbuf, @rpos, n)
    @rpos += n
    if @rpos == @rend
      @rpos = 0
      @rend = 0
    out

  -> close
    return nil if @closed
    @closed = true
    begin
      if @tls
        @tls_conn.close() if @tls_conn != nil
      else
        @sock.close() if @sock != nil
    rescue e
      nil
    nil

# High-performance RFC 6455 WebSocket Client with automatic Ping/Pong keepalives,
# permessage-deflate compression, fragmented message reassembly, and async event queue.
+ WsClient
  rw :url, :state, :protocol, :extensions, :deflate_enabled, :max_message_bytes
  rw :ping_interval_ms, :pong_timeout_ms, :pings_sent, :pongs_received, :rtt_ms
  rw :last_rx_ms, :last_pong_ms, :close_code, :close_reason, :error, :buffered_amount

  -> new(url_str, opts = nil)
    @url = url_str.to_s
    @opts = opts.is_a?(Hash) ? opts : {}
    @state = WS_STATE_CONNECTING
    @protocol = ""
    @extensions = ""
    @deflate_enabled = false
    @max_message_bytes = @opts[:max_message_bytes] != nil ? @opts[:max_message_bytes] : 16777216
    @ping_interval_ms = @opts[:ping_interval_ms] != nil ? @opts[:ping_interval_ms] : 25000
    @pong_timeout_ms = @opts[:pong_timeout_ms] != nil ? @opts[:pong_timeout_ms] : 10000
    @pings_sent = 0
    @pongs_received = 0
    @rtt_ms = -1
    @last_rx_ms = ws_now_ms()
    @last_pong_ms = @last_rx_ms
    @pending_ping_ms = 0
    @pending_ping_seq = 0
    @close_code = 1005
    @close_reason = ""
    @error = nil
    @buffered_amount = 0
    @transport = nil
    @wlock = Mutex.new
    @elock = Mutex.new
    @events = []
    @keepalive_started = false
    @reader_started = false

  # Connect synchronously and complete the HTTP/1.1 101 Switching Protocols handshake.
  -> .connect(url_str, opts = nil)
    ws = WsClient.new(url_str, opts)
    ws.connect_sync()
    ws

  -> push_event(ev)
    @elock.lock
    @events.push(ev)
    @elock.unlock
    nil

  -> poll_events
    @elock.lock
    if @events.size == 0
      @elock.unlock
      return []
    out = @events
    @events = []
    @elock.unlock
    out

  -> connect_sync
    u = ws_parse_url(@url)
    if u == nil
      @error = "Invalid WebSocket URL: " + @url
      @state = WS_STATE_CLOSED
      @close_code = 1006
      return false
    sock = nil
    tconn = nil
    begin
      sock = Socket.connect_timeout(u[:host], u[:port], 10000)
      if u[:tls]
        tconn = TlsConn.new(sock, u[:host], ["http/1.1"])
        tconn.handshake()
    rescue e
      @error = "Connection failed: " + e.to_s
      @state = WS_STATE_CLOSED
      @close_code = 1006
      return false
    @transport = WsTransport.new(u[:tls], sock, tconn)

    # RFC 6455 client opening handshake
    ws_key = Base64.encode(brand(16))
    want_accept = ws_compute_accept(ws_key)
    host_hdr = u[:host]
    if (u[:tls] && u[:port] != 443) || (!u[:tls] && u[:port] != 80)
      host_hdr = host_hdr + ":" + u[:port].to_s
    req = "GET " + u[:path] + " HTTP/1.1\r\n" +
          "Host: " + host_hdr + "\r\n" +
          "Upgrade: websocket\r\n" +
          "Connection: Upgrade\r\n" +
          "Sec-WebSocket-Key: " + ws_key + "\r\n" +
          "Sec-WebSocket-Version: 13\r\n"
    protos = @opts[:protocols]
    if protos.is_a?(Array) && protos.size > 0
      req = req + "Sec-WebSocket-Protocol: " + protos.join(", ") + "\r\n"
    elsif protos.is_a?(String) && protos.size > 0
      req = req + "Sec-WebSocket-Protocol: " + protos + "\r\n"
    want_deflate = @opts[:deflate] != false
    if want_deflate
      req = req + "Sec-WebSocket-Extensions: permessage-deflate; client_no_context_takeover; server_no_context_takeover\r\n"
    hdrs = @opts[:headers]
    if hdrs.is_a?(Hash)
      hdrs.each ->(k, v)
        req = req + k.to_s + ": " + v.to_s + "\r\n"
    req = req + "\r\n"

    if !@transport.write_bytes(bytes_of(req))
      @error = "Handshake write failed"
      @state = WS_STATE_CLOSED
      @close_code = 1006
      @transport.close()
      return false

    # Read HTTP 101 response header bytes until \r\n\r\n
    raw = ByteArray.new(0)
    he = -1
    while he < 0
      b1 = @transport.read_exact(1)
      if b1 == nil
        @error = "EOF during WebSocket handshake"
        @state = WS_STATE_CLOSED
        @close_code = 1006
        @transport.close()
        return false
      raw.push(b1[0])
      n = raw.size
      if n >= 4 && raw[n - 4] == 13 && raw[n - 3] == 10 && raw[n - 2] == 13 && raw[n - 1] == 10
        he = n - 4
      if n > 32768
        @error = "WebSocket handshake header too large"
        @state = WS_STATE_CLOSED
        @close_code = 1006
        @transport.close()
        return false

    head_s = str_of(bslice(raw, 0, he))
    lines = head_s.split("\r\n")
    if lines.size == 0 || lines[0].index(" 101") == nil
      @error = "WebSocket upgrade rejected: " + (lines.size > 0 ? lines[0] : "")
      @state = WS_STATE_CLOSED
      @close_code = 1006
      @transport.close()
      return false
    rh = {}
    i = 1
    while i < lines.size
      cpos = lines[i].index(":")
      if cpos != nil
        rh[lines[i].slice(0, cpos).strip.downcase] = lines[i].slice(cpos + 1, lines[i].size - cpos - 1).strip
      i += 1
    if rh["sec-websocket-accept"] != want_accept
      @error = "Invalid Sec-WebSocket-Accept header"
      @state = WS_STATE_CLOSED
      @close_code = 1006
      @transport.close()
      return false
    @protocol = rh["sec-websocket-protocol"] != nil ? rh["sec-websocket-protocol"] : ""
    @extensions = rh["sec-websocket-extensions"] != nil ? rh["sec-websocket-extensions"] : ""
    @deflate_enabled = want_deflate && @extensions.downcase.index("permessage-deflate") != nil
    @last_rx_ms = ws_now_ms()
    @last_pong_ms = @last_rx_ms
    @state = WS_STATE_OPEN
    true

  -> send_raw_frame(opcode, payload, rsv1 = false)
    return false if @state != WS_STATE_OPEN && !(opcode == WS_OP_CLOSE && @state == WS_STATE_CLOSING)
    return false if @transport == nil
    frame = ws_encode_frame(opcode, payload, true, rsv1, true)
    @wlock.lock
    @buffered_amount += frame.size
    ok = @transport.write_bytes(frame)
    @buffered_amount -= frame.size
    @buffered_amount = 0 if @buffered_amount < 0
    @wlock.unlock
    if !ok
      @state = WS_STATE_CLOSED
      @close_code = 1006
    ok

  -> send_text(text)
    return false if @state != WS_STATE_OPEN
    raw = bytes_of(text.to_s)
    if @deflate_enabled && raw.size >= 128
      comp = ws_deflate_payload(raw)
      if comp.size < raw.size
        return send_raw_frame(WS_OP_TEXT, comp, true)
    send_raw_frame(WS_OP_TEXT, raw, false)

  -> send_binary(bytes)
    return false if @state != WS_STATE_OPEN
    raw = bytes.is_a?(ByteArray) ? bytes : bytes_of(bytes.to_s)
    if @deflate_enabled && raw.size >= 128
      comp = ws_deflate_payload(raw)
      if comp.size < raw.size
        return send_raw_frame(WS_OP_BINARY, comp, true)
    send_raw_frame(WS_OP_BINARY, raw, false)

  -> send_ping(payload = nil)
    return false if @state != WS_STATE_OPEN
    @pending_ping_seq += 1
    p = payload != nil ? (payload.is_a?(ByteArray) ? payload : bytes_of(payload.to_s)) : bytes_of("ka-" + @pending_ping_seq.to_s)
    @pending_ping_ms = ws_now_ms()
    @pings_sent += 1
    send_raw_frame(WS_OP_PING, p, false)

  -> send_pong(payload = nil)
    p = payload == nil ? ByteArray.new(0) : payload
    send_raw_frame(WS_OP_PONG, p, false)

  -> close(code = 1000, reason = "")
    return nil if @state == WS_STATE_CLOSED
    was_open = @state == WS_STATE_OPEN
    @state = WS_STATE_CLOSING
    @close_code = code
    @close_reason = reason.to_s
    if was_open && @transport != nil
      send_raw_frame(WS_OP_CLOSE, ws_close_payload(code, reason), false)
    @state = WS_STATE_CLOSED
    @transport.close() if @transport != nil
    nil

  # Read one complete WebSocket message (handling fragmentation, Ping->Pong, Pong RTT, and Close).
  # Returns {type: :text|:binary, data: String|ByteArray} or nil on close/error.
  -> read_message
    acc = ByteArray.new(0)
    msg_op = 0
    msg_rsv1 = false
    started = false
    while @state == WS_STATE_OPEN || @state == WS_STATE_CLOSING
      h = @transport.read_exact(2)
      if h == nil
        @state = WS_STATE_CLOSED
        @close_code = 1006 if @close_code == 1005
        return nil
      @last_rx_ms = ws_now_ms()
      b0 = h[0]
      b1 = h[1]
      fin = (b0 & 0x80) != 0
      rsv1 = (b0 & 0x40) != 0
      op = b0 & 0x0F
      masked = (b1 & 0x80) != 0
      len = b1 & 0x7F
      if len == 126
        ex = @transport.read_exact(2)
        if ex == nil
          @state = WS_STATE_CLOSED
          return nil
        len = (ex[0] << 8) | ex[1]
      elsif len == 127
        ex = @transport.read_exact(8)
        if ex == nil
          @state = WS_STATE_CLOSED
          return nil
        len = 0
        j = 0
        while j < 8
          len = (len << 8) | ex[j]
          j += 1
      if len > @max_message_bytes
        close(1009, "Message too big")
        return nil
      mask = nil
      if masked
        mask = @transport.read_exact(4)
        if mask == nil
          @state = WS_STATE_CLOSED
          return nil
      payload = @transport.read_exact(len)
      if payload == nil
        @state = WS_STATE_CLOSED
        return nil
      ws_mask_inplace(payload, 0, len, mask) if masked && len > 0

      if op == WS_OP_CLOSE
        cp = ws_parse_close_payload(payload)
        @close_code = cp[0]
        @close_reason = cp[1]
        if @state == WS_STATE_OPEN
          @state = WS_STATE_CLOSING
          send_raw_frame(WS_OP_CLOSE, ws_close_payload(cp[0], cp[1]), false)
        @state = WS_STATE_CLOSED
        @transport.close()
        return nil
      elsif op == WS_OP_PING
        send_pong(payload)
      elsif op == WS_OP_PONG
        now = ws_now_ms()
        @last_pong_ms = now
        @pongs_received += 1
        if @pending_ping_ms > 0
          @rtt_ms = now - @pending_ping_ms
          @pending_ping_ms = 0
      elsif op == WS_OP_TEXT || op == WS_OP_BINARY || op == WS_OP_CONT
        if op != WS_OP_CONT
          msg_op = op
          msg_rsv1 = rsv1
          acc = payload
          started = true
        elsif started
          acc = bcat(acc, payload)
          if acc.size > @max_message_bytes
            close(1009, "Message too big")
            return nil
        if fin && started
          body = msg_rsv1 && @deflate_enabled ? ws_inflate_payload(acc) : acc
          if msg_op == WS_OP_TEXT
            return {type: :text, data: str_of(body)}
          return {type: :binary, data: body}
    nil

  # Start automatic background Ping/Pong keepalive monitor thread.
  -> start_keepalive
    return nil if @keepalive_started || @ping_interval_ms <= 0
    @keepalive_started = true
    ws = self
    Thread.new ->
      while ws.state == WS_STATE_OPEN
        step = ws.ping_interval_ms < 200 ? ws.ping_interval_ms : 200
        slept = 0
        while slept < ws.ping_interval_ms && ws.state == WS_STATE_OPEN
          sleep(step / ~1000.0)
          slept += step
        break if ws.state != WS_STATE_OPEN
        now = ws_now_ms()
        # Check whether an earlier ping timed out without a pong/rx
        if ws.pings_sent > ws.pongs_received && now - ws.last_rx_ms > ws.pong_timeout_ms + ws.ping_interval_ms
          ws.error = "WebSocket keepalive pong timeout"
          ws.close(1006, "Keepalive timeout")
          break
        ws.send_ping()
      nil
    nil

  # Start full async lifecycle (connect + reader + keepalive) pushing events to poll_events().
  -> start_async
    return nil if @reader_started
    @reader_started = true
    ws = self
    Thread.new ->
      ok = ws.connect_sync()
      if !ok
        ws.push_event({type: :error, message: ws.error.to_s})
        ws.push_event({type: :close, code: ws.close_code, reason: ws.close_reason, clean: false})
      else
        ws.push_event({type: :open, protocol: ws.protocol, extensions: ws.extensions})
        ws.start_keepalive()
        while ws.state == WS_STATE_OPEN || ws.state == WS_STATE_CLOSING
          msg = ws.read_message()
          break if msg == nil
          ws.push_event({type: :message, kind: msg[:type], data: msg[:data]})
        ws.push_event({type: :close, code: ws.close_code, reason: ws.close_reason, clean: ws.close_code == 1000})
      nil
    nil
