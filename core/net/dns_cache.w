# blade/dns — host names to addresses: a read-through cache over one long-lived resolver.
#
#   DnsCache     host → answer, kept for the record TTL (floor 30 s, ceiling 1 h; failures
#                10 s). get(host) answers from the cache or reads through to the resolver.
#                Concurrent misses for one host share a single query (the others wait on
#                it); safe from fetch threads.
#   DnsResolver  one per process, its transport kept open across queries:
#                  "upstream"  the nameservers of /etc/resolv.conf (else scutil --dns) over
#                              ONE UDP socket; queries are multiplexed by transaction id, a
#                              reader thread hands each answer to its waiter, so many hosts
#                              resolve at once. Retries with backoff; a truncated answer is
#                              asked again over TCP on a kept-alive connection. A and AAAA.
#                  "system"    the OS resolver (on macOS mDNSResponder: VPN / split DNS,
#                              /etc/hosts, search domains). Needs core's Dns.system_lookup
#                              (Tungsten branch blade-net); until that is in the toolchain
#                              the resolver uses "upstream".
#                BLADE_DNS=upstream|system picks one (default: system when available).
#
# Panel data (main thread only; fetch threads queue into DNS_PENDING, which dns_drain moves):
#   DNS_LOG   one row per real query: [host, ip [a,b,c,d], "live", ms, started_ms, backend, v6 count]
#   DNS_HITS  host → number of lookups answered from the cache

DNS_LOG = []
DNS_HITS = {}
DNS_PENDING = [[], {}]
DNS_PENDING_LOCK = [Mutex.new]
DNS_STATE = [nil]

DNS_TTL_FLOOR = 30
DNS_TTL_CEIL = 3600
DNS_NEG_TTL = 10

-> dns_cache
  DNS_STATE[0] = DnsCache.new(DnsResolver.new) if DNS_STATE[0] == nil
  DNS_STATE[0]

# "system" or "upstream": which resolver answers (for the panel).
-> dns_backend
  dns_cache.resolver.backend

# Move what fetch threads recorded into DNS_LOG / DNS_HITS. Call on the main thread
# (Net#poll does), so the panel never reads an array another thread is growing.
-> dns_drain
  # Called on every poll: when nothing is queued, return without allocating. (An unlocked
  # size read can only miss a row being added now; the next poll takes it.)
  return 0 if DNS_PENDING[0].size == 0 && DNS_PENDING[1].size == 0
  m = DNS_PENDING_LOCK[0]
  m.lock
  rows = DNS_PENDING[0]
  hits = DNS_PENDING[1]
  DNS_PENDING[0] = []
  DNS_PENDING[1] = {}
  m.unlock
  rows.each ->(r) DNS_LOG.push(r)
  hits.each ->(h, n) DNS_HITS[h] = (DNS_HITS[h] == nil ? 0 : DNS_HITS[h]) + n
  rows.size + hits.size

-> dns_note_query(row)
  m = DNS_PENDING_LOCK[0]
  m.lock
  DNS_PENDING[0].push(row)
  m.unlock

-> dns_note_hit(host)
  m = DNS_PENDING_LOCK[0]
  m.lock
  h = DNS_PENDING[1]
  h[host] = (h[host] == nil ? 0 : h[host]) + 1
  m.unlock

-> dns_digits?(s)
  return false if s == nil || s.size == 0
  i = 0
  while i < s.size
    b = s.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  true

-> dns_ws_split(s)
  out = []
  i = 0
  n = s.size
  while i < n
    while i < n && (s.byte_at(i) == 32 || s.byte_at(i) == 9 || s.byte_at(i) == 13 || s.byte_at(i) == 10)
      i += 1
    break if i >= n
    j = i
    while j < n && s.byte_at(j) != 32 && s.byte_at(j) != 9 && s.byte_at(j) != 13 && s.byte_at(j) != 10
      j += 1
    out.push(s.slice(i, j - i))
    i = j
  out

-> ipv4_literal(host)
  p = host.split(".")
  return nil if p.size != 4
  out = []
  p.each ->(x)
    return nil if x.size == 0 || !dns_digits?(x)
    out.push(x.to_i)
  out

-> ip_string(ip)
  ip[0].to_s + "." + ip[1].to_s + "." + ip[2].to_s + "." + ip[3].to_s

# The first IPv4 address of host, or nil (blocking; any thread).
-> resolve4(host)
  a = dns_cache.get(host)
  a == nil || a.v4.size == 0 ? nil : a.v4[0]

# A cached, unexpired IPv4 answer without querying, or nil.
-> dns_cached(host, part = "")
  a = dns_cache.peek(host, part)
  a == nil || a.v4.size == 0 ? nil : a.v4[0]

-> dns_clear
  dns_cache.clear if DNS_STATE[0] != nil
  nil

+ DnsAnswer
  ro :host, :v4, :v6, :ttl, :expires, :backend, :error
  -> new(@host, @v4, @v6, @ttl, @backend, @error = nil)
    t = @ttl
    if @v4.size == 0 && @v6.size == 0
      t = DNS_NEG_TTL
    else
      t = DNS_TTL_FLOOR if t < DNS_TTL_FLOOR
      t = DNS_TTL_CEIL if t > DNS_TTL_CEIL
    @expires = clock_ms() + t * 1000

  -> expired?
    clock_ms() > @expires

  -> ok?
    @v4.size > 0 || @v6.size > 0

+ DnsCache
  -> new(@resolver)
    @m = Mutex.new
    @map = {}        # host → DnsAnswer
    @flight = {}     # host → Channel the waiters block on (closed when the query ends)

  ro :resolver

  -> peek(host, part = "")
    @m.lock
    a = @map[part.size == 0 ? host : host + "|" + part]
    @m.unlock
    a == nil || a.expired? ? nil : a

  -> clear
    @m.lock
    @map = {}
    @m.unlock
    nil

  # The answer for host: cached, or one query (shared by every thread asking meanwhile).
  # part: the network partition (blade/privacy): answers cached for one top-level site are
  # not visible to another (a cache hit would tell a site where else the user has been).
  -> get(host, part = "")
    lit = ipv4_literal(host)
    return DnsAnswer.new(host, [lit], [], DNS_TTL_CEIL, "literal") if lit != nil
    if host.index(":") != nil
      return DnsAnswer.new(host, [], [host], DNS_TTL_CEIL, "literal")
    mk = part.size == 0 ? host : host + "|" + part
    while true
      @m.lock
      a = @map[mk]
      if a != nil && !a.expired?
        @m.unlock
        dns_note_hit(host)
        return a
      ch = @flight[mk]
      mine = false
      if ch == nil
        ch = Channel.new(2)
        @flight[mk] = ch
        mine = true
      @m.unlock
      if !mine
        # someone is asking already: wait for it, then read the cache
        ch.receive_result(20000)
        @m.lock
        a = @map[mk]
        @m.unlock
        if a != nil
          dns_note_hit(host)
          return a
        next
      t0 = clock_ms()
      ans = nil
      begin
        ans = @resolver.lookup(host)
      rescue e
        ans = DnsAnswer.new(host, [], [], 0, @resolver.backend, e.to_s)
      ms = clock_ms() - t0
      @m.lock
      @map[mk] = ans
      @flight.delete(mk)
      @m.unlock
      ch.close
      if ans.v4.size > 0
        dns_note_query([host, ans.v4[0], "live", ms, t0, ans.backend, ans.v6.size])
      return ans

  -> clear
    @m.lock
    @map = {}
    @m.unlock


# ---- the resolver ----

+ DnsResolver
  ro :backend

  -> new(choice = nil)
    choice = Env.get("BLADE_DNS", "") if choice == nil
    @backend = "upstream"
    @sys = nil
    if choice != "upstream" && dns_system_available?
      @backend = "system"
    @up = nil
    @up = DnsUpstream.new(dns_servers()) if @backend == "upstream"

  # → DnsAnswer (A and AAAA).
  -> lookup(host)
    return dns_system_lookup(host) if @backend == "system"
    @up.lookup(host)

  -> close
    @up.close if @up != nil


# The system resolver (Tungsten core Dns.lookup, branch blade-net 339fb1a7). Until that
# is in the toolchain these two stay stubs and "upstream" serves every lookup; once it is,
# make them:
#   -> dns_system_available?
#     Dns.available?
#   -> dns_system_lookup(host)
#     dns_system_answer(host, Dns.lookup(host, 5000))
-> dns_system_available?
  Dns.available?

-> dns_system_lookup(host)
  dns_system_answer(host, Dns.lookup(host, 5000))

# Core's [v4 strings, v6 strings, ttl] (or nil) → DnsAnswer.
-> dns_system_answer(host, r)
  return DnsAnswer.new(host, [], [], 0, "system", "no answer") if r == nil
  v4 = []
  r[0].each ->(a)
    ip = ipv4_literal(a)
    v4.push(ip) if ip != nil
  DnsAnswer.new(host, v4, r[1], r[2], "system")


# Nameserver IPv4 addresses: /etc/resolv.conf, else scutil --dns, else 8.8.8.8 / 1.1.1.1.
-> dns_servers
  out = []
  begin
    File.read("/etc/resolv.conf").split("\n").each ->(ln)
      t = dns_ws_split(ln)
      if t.size >= 2 && t[0] == "nameserver"
        ip = ipv4_literal(t[1])
        out.push(ip) if ip != nil && !out.include?(ip)
  rescue e
    nil
  if out.size == 0
    begin
      OS.capture("scutil --dns").split("\n").each ->(ln)
        t = dns_ws_split(ln.strip)
        if t.size >= 3 && t[0].starts_with?("nameserver")
          ip = ipv4_literal(t[2])
          out.push(ip) if ip != nil && !out.include?(ip)
    rescue e
      nil
  out = [[8, 8, 8, 8], [1, 1, 1, 1]] if out.size == 0
  out

-> dns_skip_name(b, o)
  while o < b.size
    l = b[o]
    return o + 1 if l == 0
    return o + 2 if l >= 192
    o = o + 1 + l
  o

-> dns_query_packet(id, host, qtype)
  q = ByteArray.new(0)
  bpush16(q, id)
  [1, 0, 0, 1, 0, 0, 0, 0, 0, 0].each ->(x) q.push(x)
  host.split(".").each ->(l)
    if l.size > 0
      q.push(l.size)
      bappend(q, bytes_of(l))
  q.push(0)
  bpush16(q, qtype)
  bpush16(q, 1)
  q

-> dns_v6_string(r, o)
  parts = []
  i = 0
  while i < 8
    parts.push(bget16(r, o + i * 2).to_s(16))
    i += 1
  parts.join(":")

# A response → [rcode, truncated?, [addresses], min ttl]; v4 addresses as [a,b,c,d], v6 as strings.
-> dns_parse(r, qtype)
  return [2, false, [], 0] if r == nil || r.size < 12
  flags = bget16(r, 2)
  rcode = flags & 15
  tc = (flags & 0x0200) != 0
  qd = bget16(r, 4)
  an = bget16(r, 6)
  o = 12
  k = 0
  while k < qd && o < r.size
    o = dns_skip_name(r, o) + 4
    k += 1
  addrs = []
  ttl = 0
  k = 0
  while k < an && o + 10 <= r.size
    o = dns_skip_name(r, o)
    break if o + 10 > r.size
    ty = bget16(r, o)
    t = bget32(r, o + 4)
    rl = bget16(r, o + 8)
    if ty == qtype && o + 10 + rl <= r.size
      if ty == 1 && rl == 4
        addrs.push([r[o + 10], r[o + 11], r[o + 12], r[o + 13]])
        ttl = t if ttl == 0 || t < ttl
      elsif ty == 28 && rl == 16
        addrs.push(dns_v6_string(r, o + 10))
        ttl = t if ttl == 0 || t < ttl
    o = o + 10 + rl
    k += 1
  [rcode, tc, addrs, ttl]

-> dns_reader_main(up)
  up.reader_loop

# Upstream DNS over one UDP socket shared by every query (multiplexed by id).
+ DnsUpstream
  -> new(@servers)
    @m = Mutex.new
    @waiters = {}    # id → Channel
    @next_id = (brand(2)[0] << 8) + 1
    @server = 0
    @sock = UDPSocket.new.connect(ip_string(@servers[0]), 53)
    @tcp = nil
    @tcp_m = Mutex.new
    @closed = false
    @reader = Thread.new -> dns_reader_main(self)

  -> reader_loop
    while !@closed
      d = nil
      begin
        d = @sock.recv_bytes(65536)
      rescue e
        d = nil
        if @closed
          return nil
      if d != nil && d.size >= 12
        id = bget16(d, 0)
        @m.lock
        ch = @waiters.delete(id)
        @m.unlock
        ch.send(d) if ch != nil
    nil

  -> new_id
    @next_id = (@next_id * 1103515245 + 12345) % 65536
    @next_id = 1 if @next_id == 0
    @next_id

  # Several questions about host at once over UDP (TCP for a truncated answer)
  # → raw responses in qtypes order (nil where none came).
  -> ask(host, qtypes)
    out = qtypes.map(->(q) nil)
    tries = 0
    wait = 700
    while tries < 4
      chans = []
      ids = []
      @m.lock
      k = 0
      while k < qtypes.size
        if out[k] == nil
          id = new_id()
          while @waiters.has_key?(id)
            id = new_id()
          ch = Channel.new(2)
          @waiters[id] = ch
          chans.push([k, id, ch])
        k += 1
      sock = @sock
      @m.unlock
      return out if chans.size == 0
      chans.each ->(c)
        begin
          sock.send(dns_query_packet(c[1], host, qtypes[c[0]]))
        rescue e
          nil
      deadline = clock_ms() + wait
      chans.each ->(c)
        left = deadline - clock_ms()
        res = c[2].receive_result(left < 1 ? 1 : left)
        if res.received?
          r = res.value
          r = ask_tcp(host, qtypes[c[0]]) if (bget16(r, 2) & 0x0200) != 0
          out[c[0]] = r
        else
          @m.lock
          @waiters.delete(c[1])
          @m.unlock
      tries += 1
      wait = wait * 2
      # a silent server: the next one (if any) for the remaining tries
      rotate() if tries == 2 && @servers.size > 1 && out.include?(nil)
    out

  -> rotate
    @m.lock
    @server = (@server + 1) % @servers.size
    old = @sock
    @sock = UDPSocket.new.connect(ip_string(@servers[@server]), 53)
    @m.unlock
    # the reader is parked on the old socket: it wakes with an error or the next datagram
    old.close

  # DNS over TCP (RFC 7766) on a connection kept open between truncated answers.
  -> ask_tcp(host, qtype)
    @tcp_m.lock
    r = nil
    begin
      k = 0
      while k < 2 && r == nil
        begin
          if @tcp == nil
            @tcp = Socket.connect(ip_string(@servers[@server]), 53)
            @tcp.set_timeout(4000)
          q = dns_query_packet(new_id(), host, qtype)
          msg = ByteArray.new(0)
          bpush16(msg, q.size)
          bappend(msg, q)
          @tcp.write_bytes(msg)
          buf = ""
          need = -1
          while need < 0 || buf.size < need + 2
            c = @tcp.read(65536)
            raise "DNS: TCP closed" if c == nil
            buf = buf + c
            need = buf.byte_at(0) * 256 + buf.byte_at(1) if need < 0 && buf.size >= 2
          r = bytes_of(buf.slice(2, need))
        rescue e
          begin
            @tcp.close if @tcp != nil
          rescue e2
            nil
          @tcp = nil
        k += 1
    ensure
      @tcp_m.unlock
    r

  # A and AAAA together (both questions in flight at once).
  -> lookup(host)
    rs = ask(host, [1, 28])
    r4 = rs[0]
    r6 = rs[1]
    p4 = dns_parse(r4, 1)
    p6 = dns_parse(r6, 28)
    ttl = p4[3]
    ttl = p6[3] if ttl == 0 || (p6[3] > 0 && p6[3] < ttl)
    err = nil
    err = "no answer" if r4 == nil && r6 == nil
    DnsAnswer.new(host, p4[2], p6[2], ttl, "upstream", err)

  -> close
    @closed = true
    begin
      @sock.close
    rescue e
      nil
