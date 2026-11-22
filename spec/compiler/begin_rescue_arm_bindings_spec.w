# begin/rescue arms that end in return/raise must not leak their variable
# bindings into the landing pad or begin.end. lower_begin defers a local's
# store while its arm runs; an arm that ends in `return` never flushed it,
# and the next block's materialize_bindings stored the arm's register where
# it does not dominate: "Instruction does not dominate all uses!" from LLVM,
# a whole-method compile failure. Minimal case (`minimal_return_in_try`):
# a local first assigned inside `begin`, an unconditional `return` in the
# try body, and a read of the local after the begin. The same leak hit a
# terminating rescue arm (`rescue_arm_returns`) and the rescue-fail pad an
# ensure clause adds (`rescue_arm_raises_with_ensure`). `Net#https_request`
# is the shape it was found in: two begin/rescue blocks in one method, the
# first nested in an `if`, returns inside both, a while/break loop, and
# locals assigned in both blocks.
#
# Run: `bin/tungsten spec/compiler/begin_rescue_arm_bindings_spec.w`
#      `bin/tungsten run --interpret spec/compiler/begin_rescue_arm_bindings_spec.w`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> boom(q)
  raise "boom" if q == nil
  q + 1

-> minimal_return_in_try(q)
  r = 0
  begin
    r = boom(q)
    return r * 10
  rescue e
    r = -1
  r

-> rescue_arm_returns(q)
  begin
    r = boom(q)
  rescue e
    s = 5
    return s
  r

-> rescue_arm_raises_with_ensure(q, log)
  begin
    begin
      r = boom(q)
      return r
    rescue e
      s = q
      raise "again"
    ensure
      log.push("ensure")
  rescue e2
    log.push(e2.to_s)
  log.size

check("minimal.try_returns", minimal_return_in_try(1), 20)
check("minimal.rescued", minimal_return_in_try(nil), -1)
check("rescue_returns.normal", rescue_arm_returns(2), 3)
check("rescue_returns.rescued", rescue_arm_returns(nil), 5)
log = []
check("rescue_raises.normal", rescue_arm_raises_with_ensure(4, log), 5)
check("rescue_raises.normal_log", log, ["ensure"])
log = []
check("rescue_raises.rescued", rescue_arm_raises_with_ensure(nil, log), 2)
check("rescue_raises.rescued_log", log, ["ensure", "again"])

# -- The shape the bug was found in (blade's Net#https_request) --

+ Quic
  ro :tls
  -> new(@fail)
    @tls = {verified: true}
  -> fetch(m)
    raise "quic down" if @fail
    Reply.new(200, "h3 " + m)

+ Tls
  ro :alpn, :tls
  -> new(@alpn, @chunks)
    @tls = {verified: false}
  -> read
    @chunks.shift
  -> close
    nil

+ Reply
  rw :status, :body, :protocol
  -> new(@status, @body)
    @protocol = nil

+ Net
  -> new(@force, @quic_fail, @alpn, @chunks)
    @h3_origins = {"o": true}

  -> finish(s, b, p, v)
    s.to_s + " " + b + " " + p + " " + v.to_s

  -> https_request(origin, method)
    if @force == "h3" || (@force == nil && @h3_origins.has_key?(origin))
      begin
        q = Quic.new(@quic_fail)
        r = q.fetch(method)
        return finish(r.status, r.body, "h3", q.tls[:verified])
      rescue e
        return "h3 failed: " + e.to_s if @force == "h3"
        @h3_origins.delete(origin)
    begin
      c = Tls.new(@alpn, @chunks)
      if c.alpn == "h2"
        r = Reply.new(200, "h2 " + method)
        c.close
        return finish(r.status, r.body, "h2", c.tls[:verified])
      body = ""
      while true
        d = c.read()
        break if d == nil
        body = body + d
      c.close
      r = Reply.new(200, body)
      r.protocol = "http/1.1"
      r.protocol + " " + r.body
    rescue e
      "failed: " + e.to_s

check("https.h3", Net.new(nil, false, "h2", []).https_request("o", "GET"), "200 h3 GET h3 true")
check("https.h3_forced_fail", Net.new("h3", true, "h2", []).https_request("o", "GET"), "h3 failed: quic down")
check("https.h3_fallback_h2", Net.new(nil, true, "h2", []).https_request("o", "GET"), "200 h2 GET h2 false")
check("https.h2", Net.new("h2", false, "h2", []).https_request("x", "GET"), "200 h2 GET h2 false")
check("https.h1", Net.new("h1", false, "http/1.1", ["a", "b"]).https_request("x", "GET"), "http/1.1 ab")
check("https.h1_fail", Net.new("h1", false, "http/1.1", nil).https_request("x", "GET").starts_with?("failed: "), true)
