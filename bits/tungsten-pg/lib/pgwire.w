# PgWire — pure-Tungsten PostgreSQL wire-protocol (v3) client. No libpq.
#
#   use tungsten-pg/pgwire
#   c = PgWire.connect("postgres:///mydb")
#   c.exec("SELECT 1") -> (row) << row[0]
#   c.exec_params("SELECT $1::int + 1", ["41"])
#   c.copy_start("COPY t FROM STDIN")
#   c.copy_write("1\thello\n")
#   c.copy_finish
#   c.close
#
# TCP only: postgres:///db and host-less URLs connect to 127.0.0.1:5432
# (there is no unix-socket surface in the runtime). Text format everywhere.
# Auth: trust, cleartext, md5, SCRAM-SHA-256 (RFC 7677; ASCII passwords —
# SASLprep is not implemented).
#
# Every helper below is prefixed pgw_ to keep the global namespace clean.

# ---------- byte helpers ----------

-> pgw_be16(b, off)
  (b[off] << 8) | b[off + 1]

-> pgw_be32(b, off)
  (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]

# Signed 32-bit read (cell length -1 arrives as 0xFFFFFFFF).
-> pgw_be32s(b, off)
  v = pgw_be32(b, off)
  if v > 0x7FFFFFFF
    v = v - 0x100000000
  v

# String → fresh ByteArray (String#bytes is already byte-indexed; copy so
# callers can mutate/concat freely).
-> pgw_str_to_bytes(s)
  bs = s.bytes
  out = u8[bs.size]
  i = 0
  while i < bs.size
    out[i] = bs[i]
    i += 1
  out

-> pgw_to_bytes(x)
  if type(x) == "String"
    return pgw_str_to_bytes(x)
  x

-> pgw_concat(a, b)
  out = u8[a.size + b.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  j = 0
  while j < b.size
    out[a.size + j] = b[j]
    j += 1
  out

-> pgw_bytes_str(b)
  ccall("w_string_from_byte_array", b)

# Poly int array → u8[]
-> pgw_pack(vals)
  buf = u8[vals.size]
  i = 0
  while i < vals.size
    buf[i] = vals[i]
    i += 1
  buf

# ---------- message writer (poly array of byte ints) ----------

-> pgw_w_i32(out, v)
  out.push((v >> 24) & 0xFF)
  out.push((v >> 16) & 0xFF)
  out.push((v >> 8) & 0xFF)
  out.push(v & 0xFF)

-> pgw_w_i16(out, v)
  out.push((v >> 8) & 0xFF)
  out.push(v & 0xFF)

# Raw string bytes, no terminator.
-> pgw_w_raw(out, s)
  bs = s.bytes
  i = 0
  while i < bs.size
    out.push(bs[i])
    i += 1

# NUL-terminated cstring.
-> pgw_w_str(out, s)
  pgw_w_raw(out, s)
  out.push(0)

-> pgw_w_bytes(out, b)
  i = 0
  while i < b.size
    out.push(b[i])
    i += 1

# Frame a typed message: type byte + i32 length (len includes itself) + payload.
-> pgw_frame(ty, payload)
  msg = []
  msg.push(ty)
  pgw_w_i32(msg, payload.size + 4)
  i = 0
  while i < payload.size
    msg.push(payload[i])
    i += 1
  pgw_pack(msg)

# Parse a NUL-terminated string at off; returns [string, next_off].
-> pgw_cstr_at(b, off)
  end_ = off
  while end_ < b.size && b[end_] != 0
    end_ += 1
  cell = u8[end_ - off]
  i = off
  while i < end_
    cell[i - off] = b[i]
    i += 1
  [pgw_bytes_str(cell), end_ + 1]

# ---------- auth helpers ----------
# HMAC / PBKDF2 / SCRAM live in core: Crypto:HMAC, Crypto:PBKDF2,
# Crypto:ScramSha256 (core/crypto/{hmac,pbkdf2,scram}.w). Only the
# PG-specific md5 construction remains here.

# md5 auth response: "md5" + md5hex(md5hex(password + user) + salt4)
-> pgw_md5_auth(user, password, salt4)
  inner = Crypto.md5(password + user)
  "md5" + Crypto.md5(pgw_concat(pgw_str_to_bytes(inner), salt4))

# ---------- the client ----------

+ PgWire
  -> new(@host, @port, @user, @password, @db)
    @sock = nil
    @params = {}
    @notices = []
    @last_error = ""
    @command_tag = ""
    @in_txn = false
    @pid = 0
    @secret = 0
    @closed = true
    @copying = false
    @auth_method = "trust"

  # postgres://user:pass@host:port/db — every part optional.
  # postgres:///db → 127.0.0.1:5432. TCP only. (Values are not
  # percent-decoded; passwords with ':' or '@' must come via PGPASSWORD.)
  -> .connect(url)
    rest = url
    scheme_parts = url.split("://")
    rest = scheme_parts[1] if scheme_parts.size == 2
    slash_parts = rest.split("/")
    authority = slash_parts[0]
    db = ""
    db = slash_parts[1] if slash_parts.size >= 2
    user = ""
    password = ""
    hostport = authority
    if authority.index("@") != nil
      at_parts = authority.split("@")
      creds = at_parts[0]
      hostport = at_parts[1]
      cred_parts = creds.split(":")
      user = cred_parts[0]
      password = cred_parts[1] if cred_parts.size >= 2
    host = "127.0.0.1"
    port = 5432
    if hostport != ""
      hp = hostport.split(":")
      host = hp[0] if hp[0] != "" && hp[0] != "localhost"
      port = hp[1].to_i if hp.size >= 2
    if user == ""
      user = env("PGUSER")
      user = env("USER") if user == nil || user == ""
      user = "postgres" if user == nil || user == ""
    if password == ""
      pw_env = env("PGPASSWORD")
      password = pw_env if pw_env != nil
    db = user if db == ""
    conn = PgWire.new(host, port, user, password, db)
    conn.open()
    conn

  -> open
    @sock = Socket.connect(@host, @port)
    @closed = false
    payload = []
    pgw_w_i32(payload, 196608)
    pgw_w_str(payload, "user")
    pgw_w_str(payload, @user)
    pgw_w_str(payload, "database")
    pgw_w_str(payload, @db)
    pgw_w_str(payload, "application_name")
    pgw_w_str(payload, "pgwire")
    payload.push(0)
    msg = []
    pgw_w_i32(msg, payload.size + 4)
    i = 0
    while i < payload.size
      msg.push(payload[i])
      i += 1
    @sock.write_bytes(pgw_pack(msg))
    self.auth_loop()
    self

  -> read_msg
    t = @sock.read_exact(1)
    if t == nil
      @closed = true
      raise "PG: connection closed by server"
    lnb = @sock.read_exact(4)
    raise "PG: connection closed mid-frame" if lnb == nil
    n = pgw_be32(lnb, 0)
    body = u8[0]
    if n > 4
      body = @sock.read_exact(n - 4)
      raise "PG: connection closed mid-frame" if body == nil
    [t[0], body]

  -> parse_error_fields(b)
    fields = {}
    off = 0
    while off < b.size && b[off] != 0
      code = b[off]
      r = pgw_cstr_at(b, off + 1)
      fields[code] = r[0]
      off = r[1]
    fields

  -> format_error(b)
    f = self.parse_error_fields(b)
    sev = f[83]
    code = f[67]
    msg = f[77]
    sev = "ERROR" if sev == nil
    code = "?????" if code == nil
    msg = "(no message)" if msg == nil
    "PG: " + sev + " " + code + " " + msg

  # Handle the async messages every read loop must tolerate.
  # Returns true if consumed.
  -> handle_async(t, b)
    if t == 83                       # 'S' ParameterStatus
      name_r = pgw_cstr_at(b, 0)
      val_r = pgw_cstr_at(b, name_r[1])
      @params[name_r[0]] = val_r[0]
      return true
    if t == 78                       # 'N' NoticeResponse
      f = self.parse_error_fields(b)
      m = f[77]
      m = "(notice)" if m == nil
      @notices.push(m)
      return true
    if t == 75                       # 'K' BackendKeyData
      @pid = pgw_be32(b, 0)
      @secret = pgw_be32(b, 4)
      return true
    if t == 65                       # 'A' NotificationResponse — ignore
      return true
    if t == 118                      # 'v' NegotiateProtocolVersion — ignore
      return true
    false

  -> auth_loop
    scram = nil
    while true
      m = self.read_msg()
      t = m[0]
      b = m[1]
      if self.handle_async(t, b)
        t = t                        # consumed async message; keep reading
      elsif t == 82                  # 'R' Authentication*
        code = pgw_be32(b, 0)
        if code == 0
          # ok
          code = 0
        elsif code == 3
          @auth_method = "cleartext"
          @sock.write_bytes(pgw_frame(112, self.cstr_payload(@password)))
        elsif code == 5
          @auth_method = "md5"
          salt4 = u8[4]
          salt4[0] = b[4]
          salt4[1] = b[5]
          salt4[2] = b[6]
          salt4[3] = b[7]
          @sock.write_bytes(pgw_frame(112, self.cstr_payload(pgw_md5_auth(@user, @password, salt4))))
        elsif code == 10             # SASL: pick SCRAM-SHA-256
          @auth_method = "scram-sha-256"
          mechs = []
          off = 4
          while off < b.size && b[off] != 0
            r = pgw_cstr_at(b, off)
            mechs.push(r[0])
            off = r[1]
          found = false
          mi = 0
          while mi < mechs.size
            found = true if mechs[mi] == "SCRAM-SHA-256"
            mi += 1
          raise "PG: server offers no SCRAM-SHA-256 (mechanisms: [mechs])" if !found
          scram = Crypto:ScramSha256.new("", @password)
          initial = scram.client_first
          payload = []
          pgw_w_str(payload, "SCRAM-SHA-256")
          pgw_w_i32(payload, initial.bytes.size)
          pgw_w_raw(payload, initial)
          @sock.write_bytes(pgw_frame(112, payload))
        elsif code == 11             # SASL continue
          server_first = pgw_bytes_str(self.body_from(b, 4))
          payload = []
          pgw_w_raw(payload, scram.client_final(server_first))
          @sock.write_bytes(pgw_frame(112, payload))
        elsif code == 12             # SASL final: verify server signature
          final = pgw_bytes_str(self.body_from(b, 4))
          raise "PG: server signature mismatch — not the server we authenticated" if !scram.verify_server_final(final)
        else
          raise "PG: unsupported auth method [code] (supported: trust, cleartext, md5, SCRAM-SHA-256)"
      elsif t == 90                  # 'Z'
        @in_txn = b[0] != 73
        return nil
      elsif t == 69                  # 'E'
        @last_error = self.format_error(b)
        @closed = true
        raise @last_error
      # anything else during startup: ignore

  -> cstr_payload(s)
    payload = []
    pgw_w_str(payload, s)
    payload

  -> body_from(b, off)
    out = u8[b.size - off]
    i = off
    while i < b.size
      out[i - off] = b[i]
      i += 1
    out

  -> parse_data_row(b)
    ncols = pgw_be16(b, 0)
    off = 2
    row = []
    c = 0
    while c < ncols
      ln = pgw_be32s(b, off)
      off += 4
      if ln < 0
        row.push(nil)
      else
        cell = u8[ln]
        i = 0
        while i < ln
          cell[i] = b[off + i]
          i += 1
        off += ln
        row.push(pgw_bytes_str(cell))
      c += 1
    row

  # Drain the stream to ReadyForQuery, collecting result sets. Returns the
  # LAST completed statement's rows; raises (after the drain) on error.
  -> consume_results
    current = []
    last = []
    err = ""
    saw_result = false
    while true
      m = self.read_msg()
      t = m[0]
      b = m[1]
      if self.handle_async(t, b)
        t = t                        # consumed async message; keep reading
      elsif t == 68                  # 'D'
        current.push(self.parse_data_row(b))
      elsif t == 67                  # 'C' CommandComplete
        r = pgw_cstr_at(b, 0)
        @command_tag = r[0]
        last = current
        current = []
        saw_result = true
      elsif t == 84                  # 'T' RowDescription — positional; skip
        t = t
      elsif t == 49 || t == 50 || t == 51 || t == 115 || t == 110
        # '1' ParseComplete, '2' BindComplete, '3' CloseComplete,
        # 's' PortalSuspended, 'n' NoData
        t = t
      elsif t == 73                  # 'I' EmptyQueryResponse
        last = current
        current = []
      elsif t == 71                  # 'G' CopyInResponse to a plain exec:
        # refuse the transfer, then keep draining.
        fail_payload = []
        pgw_w_str(fail_payload, "COPY not allowed via exec — use copy_start")
        @sock.write_bytes(pgw_frame(102, fail_payload))   # 'f' CopyFail
      elsif t == 72 || t == 100 || t == 99                # 'H'/'d'/'c' CopyOut
        err = "PG: COPY TO STDOUT is not supported" if err == ""
      elsif t == 69                  # 'E'
        err = self.format_error(b) if err == ""
        @last_error = err
      elsif t == 90                  # 'Z'
        @in_txn = b[0] != 73
        raise err if err != ""
        return last
      else
        raise "PG: unexpected message type [t] — protocol desync"

  -> guard_open
    raise "PG: connection is closed" if @closed
    raise "PG: COPY in progress — finish it first" if @copying

  # Simple query. Multi-statement strings run all statements; the LAST
  # result set is returned (command_tag reflects the last statement).
  -> exec(sql)
    self.guard_open()
    @sock.write_bytes(pgw_frame(81, self.cstr_payload(sql)))
    self.consume_results()

  # Extended protocol: Parse/Bind/Execute/Sync, unnamed statement/portal,
  # text format both directions. params: poly array of String or nil.
  -> exec_params(sql, params)
    self.guard_open()
    p = []
    pgw_w_str(p, "")
    pgw_w_str(p, sql)
    pgw_w_i16(p, 0)
    parse_msg = pgw_frame(80, p)                 # 'P'
    bnd = []
    pgw_w_str(bnd, "")
    pgw_w_str(bnd, "")
    pgw_w_i16(bnd, 0)
    pgw_w_i16(bnd, params.size)
    params -> (prm)
      if prm == nil
        pgw_w_i32(bnd, 0 - 1)
      else
        pb = prm.bytes
        pgw_w_i32(bnd, pb.size)
        i = 0
        while i < pb.size
          bnd.push(pb[i])
          i += 1
    pgw_w_i16(bnd, 0)
    bind_msg = pgw_frame(66, bnd)                # 'B'
    ex = []
    pgw_w_str(ex, "")
    pgw_w_i32(ex, 0)
    exec_msg = pgw_frame(69, ex)                 # 'E'
    sync_msg = pgw_frame(83, [])                 # 'S'
    all = pgw_concat(pgw_concat(parse_msg, bind_msg), pgw_concat(exec_msg, sync_msg))
    @sock.write_bytes(all)
    self.consume_results()

  # COPY FROM STDIN sub-protocol.
  -> copy_start(sql)
    self.guard_open()
    @sock.write_bytes(pgw_frame(81, self.cstr_payload(sql)))
    err = ""
    while true
      m = self.read_msg()
      t = m[0]
      b = m[1]
      if self.handle_async(t, b)
        t = t                        # consumed async message; keep reading
      elsif t == 71                  # 'G' CopyInResponse
        @copying = true
        return true
      elsif t == 69
        err = self.format_error(b) if err == ""
        @last_error = err
      elsif t == 90
        @in_txn = b[0] != 73
        raise err if err != ""
        raise "PG: statement did not start a COPY"
      elsif t == 67 || t == 84 || t == 68
        # a non-COPY statement slipped through — drain and report
        err = "PG: statement did not start a COPY" if err == ""

  # chunk: String of COPY text rows; boundaries need not align with rows.
  -> copy_write(chunk)
    raise "PG: no COPY in progress" if !@copying
    header = []
    header.push(100)                 # 'd'
    pgw_w_i32(header, chunk.bytes.size + 4)
    @sock.write_bytes(pgw_pack(header))
    @sock.write(chunk)
    nil

  -> copy_finish
    raise "PG: no COPY in progress" if !@copying
    @copying = false
    @sock.write_bytes(pgw_frame(99, []))          # 'c' CopyDone
    self.consume_results()
    @command_tag

  -> command_tag
    @command_tag

  # Which authentication path the server demanded during startup:
  # "trust" | "cleartext" | "md5" | "scram-sha-256".
  -> auth_method
    @auth_method

  -> notices
    @notices

  -> in_txn
    @in_txn

  -> last_error
    @last_error

  -> param_status(name)
    @params[name]

  -> close
    if !@closed
      begin
        @sock.write_bytes(pgw_frame(88, []))      # 'X' Terminate
      rescue e
        @closed = true
      @sock.close
      @closed = true
    nil
