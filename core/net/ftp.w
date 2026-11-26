# core/net/ftp — Pure-Tungsten FTP (RFC 959 / RFC 2428 EPSV/PASV) and
# SFTP (draft-ietf-secsh-filexfer-02 SSH subsystem) client protocol implementations.

use core/crypto/bytes

# ---- FTP (RFC 959 / RFC 2428) ----

+ FtpClient
  ro :host, :port, :banner

  -> new(@host, @port = 21)
    @sock = nil
    @banner = ""

  -> read_reply
    lines = []
    code = 0
    while true
      ln = read_line()
      break if ln == nil
      lines.push(ln)
      if ln.size >= 4 && ln.byte_at(3) == 32 # "NNN text" final line
        code = ln.slice(0, 3).to_i
        break
      elsif ln.size == 3
        code = ln.to_i
        break
    [code, lines.join("\n")]

  -> read_line
    buf = ByteArray.new(0)
    while true
      ch = @sock.recv_bytes(1)
      return buf.size > 0 ? str_of(buf) : nil if ch == nil || ch.size == 0
      b = ch[0]
      break if b == 10
      buf.push(b) if b != 13
    str_of(buf)

  -> cmd(line)
    @sock.send(bytes_of(line + "\r\n"))
    read_reply()

  -> connect(user = "anonymous", pass = "blade@tungsten.dev")
    @sock = Socket.connect(@host, @port)
    r0 = read_reply()
    @banner = r0[1]
    r1 = cmd("USER " + user)
    if r1[0] == 331
      r2 = cmd("PASS " + pass)
      raise "FTP login failed: " + r2[1] if r2[0] >= 400
    elsif r1[0] >= 400
      raise "FTP login failed: " + r1[1]
    cmd("TYPE I") # binary mode
    self

  # Open passive data connection (tries EPSV first, falls back to PASV)
  -> open_data
    r = cmd("EPSV")
    if r[0] == 229
      # 229 Entering Extended Passive Mode (|||port|)
      p1 = r[1].index("(|||")
      if p1 != nil
        p2 = r[1].index("|)", p1 + 4)
        if p2 != nil
          dport = r[1].slice(p1 + 4, p2 - p1 - 4).to_i
          return Socket.connect(@host, dport)
    r = cmd("PASV")
    raise "FTP PASV failed: " + r[1] if r[0] != 227
    l = r[1].index("(")
    ri = r[1].index(")", l == nil ? 0 : l)
    raise "FTP bad PASV reply" if l == nil || ri == nil
    nums = r[1].slice(l + 1, ri - l - 1).split(",")
    dhost = nums[0] + "." + nums[1] + "." + nums[2] + "." + nums[3]
    dport = nums[4].to_i * 256 + nums[5].to_i
    Socket.connect(dhost, dport)

  -> list(path = "/")
    ds = open_data()
    r = cmd("LIST " + path)
    if r[0] >= 400
      ds.close
      raise "FTP LIST failed: " + r[1]
    chunks = []
    while true
      b = ds.recv_bytes(16384)
      break if b == nil || b.size == 0
      chunks.push(b)
    ds.close
    read_reply()
    ftp_parse_list(str_of(bjoin(chunks)))

  -> retr(path)
    ds = open_data()
    r = cmd("RETR " + path)
    if r[0] >= 400
      ds.close
      raise "FTP RETR failed: " + r[1]
    chunks = []
    while true
      b = ds.recv_bytes(65536)
      break if b == nil || b.size == 0
      chunks.push(b)
    ds.close
    read_reply()
    bjoin(chunks)

  -> close
    begin
      cmd("QUIT") if @sock != nil
      @sock.close if @sock != nil
    rescue e
      nil
    @sock = nil

# Parse UNIX (`drwxr-xr-x 2 user grp 4096 Nov 25 12:00 name`) & DOS FTP LIST lines
-> ftp_parse_list(text)
  entries = []
  text.split("\n").each ->(raw)
    ln = raw.strip
    next if ln.size == 0 || ln.starts_with?("total ")
    parts = ln.split(" ").select ->(x) x.size > 0
    if parts.size >= 9 && (parts[0].starts_with?("d") || parts[0].starts_with?("-") || parts[0].starts_with?("l"))
      is_dir = parts[0].starts_with?("d")
      sz = parts[4].to_i
      dt = parts[5] + " " + parts[6] + " " + parts[7]
      nm = parts.slice(8, parts.size - 8).join(" ")
      next if nm == "." || nm == ".."
      entries.push({name: nm, is_dir: is_dir, size: sz, date: dt, perms: parts[0]})
    elsif parts.size >= 4
      is_dir = parts[2] == "<DIR>"
      entries.push({name: parts.slice(3, parts.size - 3).join(" "), is_dir: is_dir, size: is_dir ? 0 : parts[2].to_i, date: parts[0] + " " + parts[1], perms: ""})
  entries

# ---- SFTP v3 Packet Framing (SSH_FXP_*) + SSH Subsystem Transport ----

SFTP_FXP_INIT     = 1
SFTP_FXP_VERSION  = 2
SFTP_FXP_OPEN     = 3
SFTP_FXP_CLOSE    = 4
SFTP_FXP_READ     = 5
SFTP_FXP_WRITE    = 6
SFTP_FXP_OPENDIR  = 11
SFTP_FXP_READDIR  = 12
SFTP_FXP_STATUS   = 101
SFTP_FXP_HANDLE   = 102
SFTP_FXP_DATA     = 103
SFTP_FXP_NAME     = 104

-> sftp_u32_be(n)
  b = ByteArray.new(4)
  b[0] = (n >> 24) & 255
  b[1] = (n >> 16) & 255
  b[2] = (n >> 8) & 255
  b[3] = n & 255
  b

-> sftp_read_u32(b, off)
  (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]

-> sftp_pack_string(s)
  bs = s.is_a?(ByteArray) ? s : bytes_of(s)
  bcat(sftp_u32_be(bs.size), bs)

-> sftp_pack_packet(ptype, payload)
  body = ByteArray.new(1 + payload.size)
  body[0] = ptype & 255
  bmove(body, 1, payload, 0, payload.size) if payload.size > 0
  bcat(sftp_u32_be(body.size), body)

-> sftp_encode_init(version = 3)
  sftp_pack_packet(SFTP_FXP_INIT, sftp_u32_be(version))

-> sftp_encode_opendir(req_id, path)
  sftp_pack_packet(SFTP_FXP_OPENDIR, bcat(sftp_u32_be(req_id), sftp_pack_string(path)))

-> sftp_encode_open_read(req_id, path)
  # flags = SSH_FXF_READ (0x00000001), attrs flags = 0
  p = bcat(sftp_u32_be(req_id), sftp_pack_string(path))
  p = bcat(p, sftp_u32_be(1))
  p = bcat(p, sftp_u32_be(0))
  sftp_pack_packet(SFTP_FXP_OPEN, p)

-> sftp_decode_packet(raw)
  return nil if raw.size < 5
  ln = sftp_read_u32(raw, 0)
  return nil if raw.size < 4 + ln
  ptype = raw[4]
  payload = bslice(raw, 5, ln - 1)
  {type: ptype, payload: payload}

# Render an FTP or SFTP directory listing as clean HTML
-> ftp_render_dir_html(url_str, entries, proto = "FTP")
  sb = StringBuffer()
  sb << '<!doctype html><html><head><meta charset="utf-8"><title>Index of ' << url_str << '</title>'
  sb << '<style>body{font:14px/1.5 -apple-system,sans-serif;max-width:860px;margin:28px auto;padding:0 18px;}'
  sb << 'h1{font-size:20px;border-bottom:1px solid #e2e8f0;padding-bottom:8px;}'
  sb << 'table{width:100%;border-collapse:collapse;}th,td{text-align:left;padding:6px 10px;border-bottom:1px solid #f1f5f9;}'
  sb << 'a{color:#2563eb;text-decoration:none;}a:hover{text-decoration:underline;}</style></head><body>'
  sb << '<h1>' << proto << ' Directory: ' << url_str << '</h1><table><tr><th>Name</th><th>Size</th><th>Modified</th></tr>'
  base = url_str.ends_with?("/") ? url_str : (url_str + "/")
  entries.each ->(e)
    nm = e[:name] + (e[:is_dir] ? "/" : "")
    sb << '<tr><td><a href="' << base << nm << '">' << nm << '</a></td><td>' << (e[:is_dir] ? "-" : e[:size].to_s) << '</td><td>' << e[:date].to_s << '</td></tr>'
  sb << '</table></body></html>'
  sb.to_s
