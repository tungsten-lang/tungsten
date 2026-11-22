# core/codec/text/webvtt — WebVTT (and SubRip) captions: parsing, cue text trees, layout.
#
# Follows W3C WebVTT (https://www.w3.org/TR/webvtt1/):
#   vtt_parse(text)          §6.1 file parser -> VttTrack (cues sorted in text track cue order)
#   vtt_srt_parse(text)      SubRip .srt -> the same VttTrack
#   vtt_cue_nodes(text)      §6.4 cue text parser -> VttNode tree (cue.nodes caches it)
#   vtt_active(track, t)     cues with start <= t < end
#   vtt_layout(cues, t, x, y, w, h, measure)
#                            §7.2 "rules for updating the display", simplified: positioned
#                            VttBox list in page CSS px. measure.call(str, size, bold, italic) -> px.
#
# Times are Float seconds. Percentages are Float 0..100. Settings use symbols:
#   vertical :horizontal/:rl/:lr, line nil(auto) or Float, line_align :start/:center/:end,
#   position nil(auto) or Float, position_align :auto/:line_left/:center/:line_right,
#   align :start/:center/:end/:left/:right.

VTT_FFFD = 0xFFFD.chr
VTT_LINE_HEIGHT = ~1.2          # line box = 1.2 x font size (5vh font -> 6vh lines, as regions assume)
VTT_FONT_VH = ~0.05             # cue font size = 5% of the video height
VTT_BG = "rgba(0,0,0,0.8)"
VTT_FG = "#ffffff"
VTT_FG_FUTURE = "rgba(255,255,255,0.5)"


+ VttRegion
  rw :id, :width, :lines, :anchor_x, :anchor_y, :viewport_x, :viewport_y, :scroll

  -> new(@id = "")
    @width = ~100.0
    @lines = 3
    @anchor_x = ~0.0
    @anchor_y = ~100.0
    @viewport_x = ~0.0
    @viewport_y = ~100.0
    @scroll = nil              # nil or :up


+ VttCue
  rw :id, :start, :end, :text, :vertical, :snap, :line, :line_align, :position, :position_align
  rw :size, :align, :region, :index, :pause_on_exit

  -> new(@id = "")
    @start = ~0.0
    @end = ~0.0
    @text = ""
    @vertical = :horizontal
    @snap = true
    @line = nil
    @line_align = :start
    @position = nil
    @position_align = :auto
    @size = ~100.0
    @align = :center
    @region = nil
    @index = 0
    @pause_on_exit = false
    @nodes = nil

  # The cue text as a VttNode tree (kind :root), parsed once.
  -> nodes
    @nodes = vtt_cue_nodes(@text) if @nodes == nil
    @nodes

  -> active?(t)
    @start <= t && t < @end

  # Text content without markup (entities decoded, tags dropped).
  -> plain_text
    nodes().plain_text


+ VttTrack
  rw :cues, :regions, :region_list, :styles, :errors, :ok

  -> new
    @cues = []
    @regions = {}              # id => VttRegion (the last region defined with that id)
    @region_list = []          # every REGION block in file order
    @styles = []               # STYLE block sources (CSS text)
    @errors = []
    @ok = true                 # false: bad signature, the track fails to load


+ VttNode
  rw :kind, :classes, :annotation, :text, :children, :time, :parent
  # kind: :root :text :c :i :b :u :ruby :rt :v :lang :timestamp

  -> new(@kind, @text = "")
    @classes = []
    @annotation = nil          # <v Speaker> name, <lang en> language tag
    @children = []
    @time = nil                # :timestamp seconds
    @parent = nil

  -> append(n)
    n.parent = self
    @children.push(n)
    n

  -> plain_text
    return @text if @kind == :text
    sb = StringBuffer()
    @children.each ->(c)
      sb.append(c.plain_text) if c.kind != :rt
    sb.to_s


# ---- small byte helpers ----

-> vtt_ws?(b)
  b == 32 || b == 9 || b == 10 || b == 12 || b == 13

-> vtt_digit?(b)
  b >= 48 && b <= 57

-> vtt_alnum?(b)
  (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)

# Split on ASCII whitespace, dropping empty pieces.
-> vtt_split_ws(s)
  out = []
  n = s.size
  i = 0
  while i < n
    while i < n && vtt_ws?(s.byte_at(i))
      i += 1
    j = i
    while j < n && !vtt_ws?(s.byte_at(j))
      j += 1
    out.push(s.slice(i, j - i)) if j > i
    i = j
  out

-> vtt_all_digits?(s)
  return false if s.size == 0
  i = 0
  while i < s.size
    return false if !vtt_digit?(s.byte_at(i))
    i += 1
  true

# "rules for parsing a percentage string": ^\d+(\.\d+)?%$ within 0..100, else nil.
-> vtt_percent(s)
  n = s.size
  return nil if n < 2 || s.byte_at(n - 1) != 37
  i = 0
  while i < n - 1 && vtt_digit?(s.byte_at(i))
    i += 1
  return nil if i == 0
  if i < n - 1
    return nil if s.byte_at(i) != 46
    i += 1
    k = i
    while i < n - 1 && vtt_digit?(s.byte_at(i))
      i += 1
    return nil if i == k || i != n - 1
  v = s.slice(0, n - 1).to_f
  return nil if v > ~100.0
  v

# NULs -> U+FFFD, CRLF and CR -> LF.
-> vtt_normalize(text)
  n = text.size
  sb = nil
  st = 0
  i = 0
  while i < n
    b = text.byte_at(i)
    if b == 0 || b == 13
      sb = StringBuffer() if sb == nil
      sb.append(text.slice(st, i - st)) if i > st
      if b == 0
        sb.append(VTT_FFFD)
      else
        sb.append("\n")
        i += 1 if i + 1 < n && text.byte_at(i + 1) == 10
      st = i + 1
    i += 1
  return text if sb == nil
  sb.append(text.slice(st, n - st)) if n > st
  sb.to_s

# "collect a WebVTT timestamp" from s at pos. Returns [seconds, new_pos] or nil.
-> vtt_timestamp_at(s, pos)
  n = s.size
  return nil if pos >= n || !vtt_digit?(s.byte_at(pos))
  hours = false
  j = pos
  while j < n && vtt_digit?(s.byte_at(j))
    j += 1
  d1 = s.slice(pos, j - pos)
  v1 = d1.size > 12 ? 999999999999 : d1.to_i
  hours = true if d1.size != 2 || v1 > 59
  pos = j
  return nil if pos >= n || s.byte_at(pos) != 58
  pos += 1
  j = pos
  while j < n && vtt_digit?(s.byte_at(j))
    j += 1
  return nil if j - pos != 2
  v2 = s.slice(pos, 2).to_i
  pos = j
  v3 = 0
  if hours || (pos < n && s.byte_at(pos) == 58)
    return nil if pos >= n || s.byte_at(pos) != 58
    pos += 1
    j = pos
    while j < n && vtt_digit?(s.byte_at(j))
      j += 1
    return nil if j - pos != 2
    v3 = s.slice(pos, 2).to_i
    pos = j
  else
    v3 = v2
    v2 = v1
    v1 = 0
  return nil if pos >= n || s.byte_at(pos) != 46
  pos += 1
  j = pos
  while j < n && vtt_digit?(s.byte_at(j))
    j += 1
  return nil if j - pos != 3
  v4 = s.slice(pos, 3).to_i
  pos = j
  return nil if v2 > 59 || v3 > 59
  secs = (v1 * 3600 + v2 * 60 + v3).to_f + v4.to_f / ~1000.0
  [secs, pos]

# Whole-string timestamp (cue text timestamp tags): seconds or nil.
-> vtt_parse_timestamp(s)
  r = vtt_timestamp_at(s, 0)
  return nil if r == nil || r[1] != s.size
  r[0]

-> vtt_pad(v, w)
  s = v.to_s
  while s.size < w
    s = "0" + s
  s

# Seconds -> "hh:mm:ss.ttt" (hours at least two digits).
-> vtt_format_time(t)
  ms = (t * ~1000.0).round
  h = ms / 3600000
  m = (ms / 60000) % 60
  sec = (ms / 1000) % 60
  vtt_pad(h, 2) + ":" + vtt_pad(m, 2) + ":" + vtt_pad(sec, 2) + "." + vtt_pad(ms % 1000, 3)


# ---- the file parser (§6.1) ----

+ VttParser
  -> new(text)
    s = text
    # UTF-8 decode strips one BOM
    if s.size >= 3 && s.byte_at(0) == 0xEF && s.byte_at(1) == 0xBB && s.byte_at(2) == 0xBF
      s = s.slice(3, s.size - 3)
    @s = vtt_normalize(s)
    @n = @s.size
    @pos = 0
    @seen_cue = false
    @track = VttTrack.new
    @count = 0

  -> run
    s = @s
    tr = @track
    if @n < 6 || s.slice(0, 6) != "WEBVTT" || (@n > 6 && s.byte_at(6) != 32 && s.byte_at(6) != 9 && s.byte_at(6) != 10)
      tr.ok = false
      tr.errors.push("missing WEBVTT signature")
      return tr
    collect_line()
    return finish() if @pos >= @n
    @pos += 1 if s.byte_at(@pos) == 10
    return finish() if @pos >= @n
    if s.byte_at(@pos) != 10
      collect_block(true)
    else
      @pos += 1
    skip_lfs()
    while @pos < @n
      blk = collect_block(false)
      if blk != nil
        if blk.is_a?(VttCue)
          blk.index = @count
          @count += 1
          tr.cues.push(blk)
        elsif blk.is_a?(VttRegion)
          tr.region_list.push(blk)
          tr.regions[blk.id] = blk
        else
          tr.styles.push(blk)
      skip_lfs()
    finish()

  -> finish
    @track.cues = vtt_sort_cues(@track.cues)
    @track

  -> collect_line
    j = @s.index("\n", @pos)
    j = @n if j == nil
    line = @s.slice(@pos, j - @pos)
    @pos = j
    line

  -> skip_lfs
    while @pos < @n && @s.byte_at(@pos) == 10
      @pos += 1

  # "collect a WebVTT block": a VttCue, a VttRegion, a String (STYLE source) or nil.
  -> collect_block(in_header)
    line_count = 0
    prev = @pos
    buffer = ""
    seen_eof = false
    seen_arrow = false
    cue = nil
    style = false
    region = nil
    while true
      line = collect_line()
      line_count += 1
      if @pos >= @n
        seen_eof = true
      else
        @pos += 1
      if line.index("-->") != nil
        if !in_header && (line_count == 1 || (line_count == 2 && !seen_arrow))
          seen_arrow = true
          prev = @pos
          cue = VttCue.new(buffer)
          if timings_and_settings(line, cue)
            buffer = ""
            @seen_cue = true
          else
            @track.errors.push("bad cue timing line: " + line)
            cue = nil
        else
          @pos = prev
          break
      elsif line.size == 0
        break
      else
        if !in_header && line_count == 2 && !@seen_cue && cue == nil
          if vtt_keyword_line?(buffer, "STYLE")
            style = true
            buffer = ""
          elsif vtt_keyword_line?(buffer, "REGION")
            region = VttRegion.new
            buffer = ""
        buffer = buffer + "\n" if buffer.size > 0
        buffer = buffer + line
        prev = @pos
      break if seen_eof
    if cue != nil
      cue.text = buffer
      return cue
    return buffer if style
    if region != nil
      region_settings(region, buffer)
      return region
    nil

  # "collect WebVTT cue timings and settings"
  -> timings_and_settings(line, cue)
    n = line.size
    i = 0
    while i < n && vtt_ws?(line.byte_at(i))
      i += 1
    r = vtt_timestamp_at(line, i)
    return false if r == nil
    cue.start = r[0]
    i = r[1]
    while i < n && vtt_ws?(line.byte_at(i))
      i += 1
    return false if i + 3 > n || line.slice(i, 3) != "-->"
    i += 3
    while i < n && vtt_ws?(line.byte_at(i))
      i += 1
    r = vtt_timestamp_at(line, i)
    return false if r == nil
    cue.end = r[0]
    i = r[1]
    cue_settings(line.slice(i, n - i), cue)
    true

  -> cue_settings(rest, cue)
    vtt_split_ws(rest).each ->(setting)
      c = setting.index(":")
      if c != nil && c > 0 && c < setting.size - 1
        name = setting.slice(0, c)
        value = setting.slice(c + 1, setting.size - c - 1)
        cue_setting(cue, name, value)

  -> cue_setting(cue, name, value)
    case name
    when "region"
      cue.region = @track.regions[value]
    when "vertical"
      cue.vertical = :rl if value == "rl"
      cue.vertical = :lr if value == "lr"
    when "line"
      c = value.index(",")
      lpos = c == nil ? value : value.slice(0, c)
      lal = c == nil ? nil : value.slice(c + 1, value.size - c - 1)
      num = vtt_line_number(lpos)
      return nil if num == nil
      la = nil
      if lal != nil
        la = :start if lal == "start"
        la = :center if lal == "center"
        la = :end if lal == "end"
        return nil if la == nil
      cue.line_align = la if la != nil
      cue.line = num
      cue.snap = lpos.byte_at(lpos.size - 1) != 37
    when "position"
      c = value.index(",")
      ppos = c == nil ? value : value.slice(0, c)
      pal = c == nil ? nil : value.slice(c + 1, value.size - c - 1)
      num = vtt_percent(ppos)
      return nil if num == nil
      if pal != nil
        pa = nil
        pa = :line_left if pal == "line-left"
        pa = :center if pal == "center"
        pa = :line_right if pal == "line-right"
        return nil if pa == nil
        cue.position_align = pa
      cue.position = num
    when "size"
      num = vtt_percent(value)
      cue.size = num if num != nil
    when "align"
      cue.align = :start if value == "start"
      cue.align = :center if value == "center"
      cue.align = :end if value == "end"
      cue.align = :left if value == "left"
      cue.align = :right if value == "right"
    nil

  # "collect WebVTT region settings"
  -> region_settings(region, input)
    vtt_split_ws(input).each ->(setting)
      c = setting.index(":")
      if c != nil && c > 0 && c < setting.size - 1
        name = setting.slice(0, c)
        value = setting.slice(c + 1, setting.size - c - 1)
        region_setting(region, name, value)

  -> region_setting(region, name, value)
    case name
    when "id"
      region.id = value if value.index("-->") == nil
    when "width"
      p = vtt_percent(value)
      region.width = p if p != nil
    when "lines"
      if vtt_all_digits?(value)
        v = value.size > 12 ? 999999999999 : value.to_i
        region.lines = v if v <= 4294967295
    when "regionanchor"
      a = vtt_anchor(value)
      if a != nil
        region.anchor_x = a[0]
        region.anchor_y = a[1]
    when "viewportanchor"
      a = vtt_anchor(value)
      if a != nil
        region.viewport_x = a[0]
        region.viewport_y = a[1]
    when "scroll"
      region.scroll = :up if value == "up"
    nil

-> vtt_keyword_line?(buffer, kw)
  return false if buffer.size < kw.size || buffer.slice(0, kw.size) != kw
  i = kw.size
  while i < buffer.size
    return false if !vtt_ws?(buffer.byte_at(i))
    i += 1
  true

-> vtt_anchor(value)
  c = value.index(",")
  return nil if c == nil
  ax = vtt_percent(value.slice(0, c))
  ay = vtt_percent(value.slice(c + 1, value.size - c - 1))
  return nil if ax == nil || ay == nil
  [ax, ay]

# A line setting position: "N%" (percentage) or a signed real number of lines.
-> vtt_line_number(s)
  n = s.size
  return nil if n == 0
  has_digit = false
  i = 0
  while i < n
    has_digit = true if vtt_digit?(s.byte_at(i))
    i += 1
  return nil if !has_digit
  if s.byte_at(n - 1) == 37
    return vtt_percent(s)
  dots = 0
  i = 0
  while i < n
    b = s.byte_at(i)
    return nil if !(vtt_digit?(b) || b == 45 || b == 46)
    return nil if b == 45 && i > 0
    if b == 46
      dots += 1
      return nil if i == 0 || i == n - 1 || !vtt_digit?(s.byte_at(i - 1)) || !vtt_digit?(s.byte_at(i + 1))
    i += 1
  return nil if dots > 1
  v = s.to_f
  return nil if v - v != ~0.0        # out of double range
  v = ~0.0 if v == ~0.0              # -0 -> 0
  v

# Text track cue order: start ascending, then end descending, then file order (stable).
-> vtt_cue_before?(a, b)
  return a.start < b.start if a.start != b.start
  return a.end > b.end if a.end != b.end
  a.index < b.index

-> vtt_sort_cues(cues)
  out = cues.dup
  i = 1
  while i < out.size
    c = out[i]
    j = i - 1
    while j >= 0 && vtt_cue_before?(c, out[j])
      out[j + 1] = out[j]
      j -= 1
    out[j + 1] = c
    i += 1
  out

-> vtt_parse(text)
  VttParser.new(text).run

-> vtt_active(track, t)
  cues = track.is_a?(VttTrack) ? track.cues : track
  cues.select(->(c) c.start <= t && t < c.end)


# ---- SubRip ----

# "hh:mm:ss,mmm" (also "." and missing hours / short fields). [seconds, new_pos] or nil.
-> vtt_srt_time_at(s, pos)
  n = s.size
  parts = []
  frac = 0
  fdig = 0
  i = pos
  while i < n && vtt_ws?(s.byte_at(i)) && s.byte_at(i) != 10
    i += 1
  while true
    j = i
    while j < n && vtt_digit?(s.byte_at(j))
      j += 1
    return nil if j == i
    parts.push(s.slice(i, j - i).to_i)
    i = j
    if i < n && s.byte_at(i) == 58 && parts.size < 3
      i += 1
    else
      break
  return nil if parts.size < 2
  if i < n && (s.byte_at(i) == 44 || s.byte_at(i) == 46)
    i += 1
    j = i
    while j < n && vtt_digit?(s.byte_at(j))
      j += 1
    fs = s.slice(i, j - i)
    fs = fs.slice(0, 3) if fs.size > 3
    while fs.size < 3
      fs = fs + "0"
    frac = fs.to_i
    i = j
  h = parts.size == 3 ? parts[0] : 0
  m = parts[parts.size - 2]
  sec = parts[parts.size - 1]
  [(h * 3600 + m * 60 + sec).to_f + frac.to_f / ~1000.0, i]

-> vtt_srt_parse(text)
  s = text
  s = s.slice(3, s.size - 3) if s.size >= 3 && s.byte_at(0) == 0xEF && s.byte_at(1) == 0xBB && s.byte_at(2) == 0xBF
  s = vtt_normalize(s)
  tr = VttTrack.new
  lines = s.split("\n")
  i = 0
  count = 0
  while i < lines.size
    line = lines[i]
    if line.index("-->") == nil
      i += 1
    else
      cue = VttCue.new("")
      prev = i > 0 ? lines[i - 1].strip : ""
      cue.id = prev if prev.size > 0 && vtt_all_digits?(prev)
      a = vtt_srt_time_at(line, 0)
      ar = line.index("-->")
      b = vtt_srt_time_at(line, ar + 3)
      i += 1
      body = []
      while i < lines.size && lines[i].strip.size > 0
        body.push(lines[i])
        i += 1
      if a == nil || b == nil
        tr.errors.push("bad SubRip timing line: " + line)
      else
        cue.start = a[0]
        cue.end = b[0]
        vtt_srt_text(cue, body.join("\n"))
        cue.index = count
        count += 1
        tr.cues.push(cue)
  tr.cues = vtt_sort_cues(tr.cues)
  tr

# SubRip text: drop {\...} override blocks ({\an8} = top-centre placement), map <font color>.
-> vtt_srt_text(cue, raw)
  sb = StringBuffer()
  n = raw.size
  i = 0
  while i < n
    b = raw.byte_at(i)
    if b == 123 && i + 1 < n && raw.byte_at(i + 1) == 92
      e = raw.index("}", i)
      e = n - 1 if e == nil
      tag = raw.slice(i + 2, e - i - 2)
      if tag.size == 3 && tag.slice(0, 2) == "an"
        an = tag.slice(2, 1).to_i
        if an >= 7
          cue.line = ~0.0
        elsif an >= 4
          cue.line = ~50.0
          cue.snap = false
          cue.line_align = :center
        cue.align = :left if an == 1 || an == 4 || an == 7
        cue.align = :right if an == 3 || an == 6 || an == 9
      i = e + 1
    else
      j = i
      while j < n && !(raw.byte_at(j) == 123 && j + 1 < n && raw.byte_at(j + 1) == 92)
        j += 1
      sb.append(raw.slice(i, j - i))
      i = j
  cue.text = sb.to_s


# ---- cue text parser (§6.4) ----

-> vtt_entity_table
  h = {}
  vtt_split_ws(VTT_ENTITY_DATA).each ->(e)
    k = e.index("=")
    sb = StringBuffer()
    e.slice(k + 1, e.size - k - 1).split(".").each ->(hx)
      sb.append(hx.to_i(16).chr)
    h[e.slice(0, k)] = sb.to_s
  h

# Windows-1252 replacements for numeric references 0x80..0x9F.
VTT_C1 = [0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, 0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178]

# HTML character reference at s[i] (just past '&'). Returns [text, new_i]; on no match
# the text is "&" and new_i == i.
-> vtt_char_ref(s, i, n, attr)
  return ["&", i] if i >= n
  b = s.byte_at(i)
  if b == 35
    j = i + 1
    hex = j < n && (s.byte_at(j) == 120 || s.byte_at(j) == 88)
    j += 1 if hex
    k = j
    cp = 0
    while k < n
      c = s.byte_at(k)
      d = -1
      d = c - 48 if c >= 48 && c <= 57
      if hex
        d = c - 87 if c >= 97 && c <= 102
        d = c - 55 if c >= 65 && c <= 70
      break if d < 0
      cp = cp * (hex ? 16 : 10) + d
      cp = 0x110000 if cp > 0x10FFFF
      k += 1
    return ["&", i] if k == j
    k += 1 if k < n && s.byte_at(k) == 59
    if cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      cp = 0xFFFD
    elsif cp >= 0x80 && cp <= 0x9F
      cp = VTT_C1[cp - 0x80]
    return [cp.chr, k]
  return ["&", i] if !vtt_alnum?(b)
  j = i
  while j < n && j - i < 32 && vtt_alnum?(s.byte_at(j))
    j += 1
  j += 1 if j < n && s.byte_at(j) == 59
  len = j - i
  while len > 0
    name = s.slice(i, len)
    v = VTT_ENT[name]
    if v != nil
      e = i + len
      if attr && name.byte_at(len - 1) != 59 && e < n && (vtt_alnum?(s.byte_at(e)) || s.byte_at(e) == 61)
        return ["&", i]
      return [v, e]
    len -= 1
  ["&", i]

# Collapse ASCII whitespace runs to one space and trim.
-> vtt_collapse_ws(s)
  vtt_split_ws(s).join(" ")

# Tokenizer: returns [type, value, classes, annotation, new_pos] or nil at end.
# type: :text, :start, :end, :timestamp
-> vtt_cue_token(s, i, n)
  return nil if i >= n
  if s.byte_at(i) != 60
    sb = StringBuffer()
    st = i
    while i < n && s.byte_at(i) != 60
      if s.byte_at(i) == 38
        sb.append(s.slice(st, i - st)) if i > st
        r = vtt_char_ref(s, i + 1, n, false)
        sb.append(r[0])
        i = r[1]
        st = i
      else
        i += 1
    sb.append(s.slice(st, i - st)) if i > st
    return [:text, sb.to_s, nil, nil, i]
  # '<': tag state
  i += 1
  return [:start, "", [], "", i] if i >= n
  b = s.byte_at(i)
  if b == 47
    i += 1
    j = i
    while j < n && s.byte_at(j) != 62
      j += 1
    v = s.slice(i, j - i)
    j += 1 if j < n
    return [:end, v, nil, nil, j]
  if vtt_digit?(b)
    j = i
    while j < n && s.byte_at(j) != 62
      j += 1
    v = s.slice(i, j - i)
    j += 1 if j < n
    return [:timestamp, v, nil, nil, j]
  if b == 62
    return [:start, "", [], "", i + 1]
  # start tag name
  j = i
  while j < n
    c = s.byte_at(j)
    break if c == 9 || c == 10 || c == 12 || c == 32 || c == 46 || c == 62
    j += 1
  name = s.slice(i, j - i)
  classes = []
  ann = StringBuffer()
  i = j
  if i < n && s.byte_at(i) == 46
    i += 1
    cb = i
    while i < n
      c = s.byte_at(i)
      if c == 46
        classes.push(s.slice(cb, i - cb))
        cb = i + 1
      elsif c == 9 || c == 10 || c == 12 || c == 32 || c == 62
        break
      i += 1
    classes.push(s.slice(cb, i - cb))
  if i < n && s.byte_at(i) != 62
    # annotation (the whitespace that switched state is collapsed away anyway)
    st = i
    while i < n && s.byte_at(i) != 62
      if s.byte_at(i) == 38
        ann.append(s.slice(st, i - st)) if i > st
        r = vtt_char_ref(s, i + 1, n, true)
        ann.append(r[0])
        i = r[1]
        st = i
      else
        i += 1
    ann.append(s.slice(st, i - st)) if i > st
  i += 1 if i < n
  [:start, name, classes.select(->(c) c.size > 0), vtt_collapse_ws(ann.to_s), i]

VTT_TAG_KINDS = {"c" => :c, "i" => :i, "b" => :b, "u" => :u, "ruby" => :ruby, "rt" => :rt, "v" => :v, "lang" => :lang}

# "WebVTT cue text parsing rules" -> VttNode(:root)
-> vtt_cue_nodes(text)
  s = vtt_normalize(text)
  n = s.size
  root = VttNode.new(:root)
  cur = root
  i = 0
  while i < n
    tok = vtt_cue_token(s, i, n)
    break if tok == nil
    i = tok[4]
    ty = tok[0]
    if ty == :text
      cur.append(VttNode.new(:text, tok[1])) if tok[1].size > 0
    elsif ty == :start
      k = VTT_TAG_KINDS[tok[1]]
      if k != nil && (k != :rt || cur.kind == :ruby)
        node = VttNode.new(k)
        node.classes = tok[2]
        node.annotation = tok[3] if k == :v || k == :lang
        cur.append(node)
        cur = node
    elsif ty == :end
      k = VTT_TAG_KINDS[tok[1]]
      if k != nil && cur.kind == k
        cur = cur.parent
      elsif k == :ruby && cur.kind == :rt
        cur = cur.parent.parent
    else
      t = vtt_parse_timestamp(tok[1])
      if t != nil
        node = VttNode.new(:timestamp)
        node.time = t
        cur.append(node)
  root


# ---- layout (§7.2, simplified) ----

+ VttRun
  rw :text, :x, :y, :w, :top, :h, :size, :bold, :italic, :underline, :color, :background, :future, :ruby
  # x: left edge, y: baseline, w: advance; top/h: the line box (background rect: x, top, w, h)

  -> new(@text, @x, @y, @w, @top, @h, @size)
    @bold = false
    @italic = false
    @underline = false
    @color = VTT_FG
    @background = VTT_BG
    @future = false
    @ruby = false              # ruby annotation text (no background, drawn above its base)


+ VttBox
  rw :x, :y, :w, :h, :lines, :cue, :vertical, :region

  -> new(@x, @y, @w, @h)
    @lines = []                # [[VttRun, ...], ...] one array per line (per column when vertical)
    @cue = nil
    @vertical = :horizontal
    @region = nil


VTT_CLASS_COLORS = {"white" => "#ffffff", "lime" => "#00ff00", "cyan" => "#00ffff", "red" => "#ff0000", "yellow" => "#ffff00", "magenta" => "#ff00ff", "blue" => "#0000ff", "black" => "#000000"}

# Inline style while flattening the cue tree.
+ VttStyle
  rw :bold, :italic, :underline, :future, :color, :background

  -> new
    @bold = false
    @italic = false
    @underline = false
    @future = false
    @color = nil
    @background = nil

  -> copy
    s = VttStyle.new
    s.bold = @bold
    s.italic = @italic
    s.underline = @underline
    s.future = @future
    s.color = @color
    s.background = @background
    s

  -> same?(o)
    @bold == o.bold && @italic == o.italic && @underline == o.underline && @future == o.future && @color == o.color && @background == o.background


# Flattens a cue tree into atoms: [:word, segs] / [:space, style] / [:br].
# A seg is [text, style] or [:ruby, base_segs, rt_segs].
+ VttFlattener
  rw :atoms

  -> new(@now)
    @atoms = []
    @word = []
    @future = false

  -> flush
    if @word.size > 0
      @atoms.push([:word, @word])
      @word = []

  -> walk(node, st)
    node.children.each ->(c)
      visit(c, st)

  -> visit(c, st)
    k = c.kind
    if k == :text
      add_text(c.text, st)
    elsif k == :timestamp
      @future = c.time > @now
    elsif k == :ruby
      base = []
      rt = []
      collect_ruby(c, styled(c, st), base, rt, false)
      @word.push([:ruby, base, rt]) if base.size > 0 || rt.size > 0
    elsif k == :rt
      walk(c, styled(c, st))
    else
      walk(c, styled(c, st))

  -> styled(c, st)
    s = st.copy
    s.bold = true if c.kind == :b
    s.italic = true if c.kind == :i
    s.underline = true if c.kind == :u
    c.classes.each ->(cl)
      if VTT_CLASS_COLORS.has_key?(cl)
        s.color = VTT_CLASS_COLORS[cl]
      elsif cl.size > 3 && cl.slice(0, 3) == "bg_" && VTT_CLASS_COLORS.has_key?(cl.slice(3, cl.size - 3))
        s.background = VTT_CLASS_COLORS[cl.slice(3, cl.size - 3)]
    s

  # Ruby bases and annotations become plain segment lists (whitespace collapsed).
  -> collect_ruby(node, st, base, rt, in_rt)
    node.children.each ->(c)
      if c.kind == :text
        t = vtt_collapse_ws(c.text)
        if t.size > 0
          s = st.copy
          s.future = @future
          (in_rt ? rt : base).push([t, s])
      elsif c.kind == :timestamp
        @future = c.time > @now
      else
        collect_ruby(c, styled(c, st), base, rt, in_rt || c.kind == :rt)

  -> add_text(t, st)
    s = st.copy
    s.future = @future
    n = t.size
    i = 0
    while i < n
      b = t.byte_at(i)
      if b == 10
        flush()
        @atoms.push([:br])
        i += 1
      elsif b == 32 || b == 9 || b == 12
        flush()
        @atoms.push([:space, s]) if @atoms.size == 0 || @atoms.last[0] != :space
        i += 1
      else
        j = i
        while j < n
          c = t.byte_at(j)
          break if c == 10 || c == 32 || c == 9 || c == 12
          j += 1
        @word.push([t.slice(i, j - i), s])
        i = j


+ VttLayout
  -> new(@vx, @vy, @vw, @vh, @measure, @now)
    @fs = @vh * VTT_FONT_VH
    @lh = @fs * VTT_LINE_HEIGHT
    @cache = {}
    @out = []

  -> width_of(text, size, st)
    key = text + (st.bold ? "|b" : "|") + (st.italic ? "i|" : "|") + size.to_s
    w = @cache[key]
    if w == nil
      w = @measure.call(text, size, st.bold, st.italic) * ~1.0
      @cache[key] = w
    w

  -> seg_width(seg)
    if seg[0] == :ruby
      bw = ~0.0
      seg[1].each ->(p)
        bw += width_of(p[0], @fs, p[1])
      rw = ~0.0
      seg[2].each ->(p)
        rw += width_of(p[0], @fs * ~0.5, p[1])
      return bw > rw ? bw : rw
    width_of(seg[0], @fs, seg[1])

  -> word_width(segs)
    w = ~0.0
    segs.each ->(sg)
      w += seg_width(sg)
    w

  # UTF-8 character boundaries of s.
  -> char_cuts(s)
    cuts = []
    i = 0
    while i < s.size
      cuts.push(i) if (s.byte_at(i) & 0xC0) != 0x80
      i += 1
    cuts.push(s.size)
    cuts

  # Breaks an over-long word into pieces no wider than maxw (characters, ruby kept whole).
  -> split_word(segs, maxw)
    out = []
    cur = []
    cw = ~0.0
    segs.each ->(sg)
      if sg[0] == :ruby
        w = seg_width(sg)
        if cur.size > 0 && cw + w > maxw
          out.push(cur)
          cur = []
          cw = ~0.0
        cur.push(sg)
        cw += w
      else
        text = sg[0]
        cuts = char_cuts(text)
        a = 0
        k = 1
        while k < cuts.size
          piece = text.slice(cuts[a], cuts[k] - cuts[a])
          w = width_of(piece, @fs, sg[1])
          if cw + w > maxw && (k - a > 1 || cur.size > 0)
            if k - a > 1
              cur.push([text.slice(cuts[a], cuts[k - 1] - cuts[a]), sg[1]])
              a = k - 1
            out.push(cur)
            cur = []
            cw = ~0.0
          else
            k += 1
        if cuts[a] < text.size
          piece = text.slice(cuts[a], text.size - cuts[a])
          cur.push([piece, sg[1]])
          cw += width_of(piece, @fs, sg[1])
    out.push(cur) if cur.size > 0
    out

  # Greedy line breaking: Array of lines, each [[:word, segs] | [:space, style], ...].
  -> break_lines(atoms, maxw)
    lines = []
    cur = []
    cw = ~0.0
    space = nil
    atoms.each ->(a)
      if a[0] == :br
        lines.push(cur)
        cur = []
        cw = ~0.0
        space = nil
      elsif a[0] == :space
        space = a[1] if cur.size > 0
      else
        w = word_width(a[1])
        sw = space == nil ? ~0.0 : width_of(" ", @fs, space)
        if cur.size > 0 && cw + sw + w > maxw
          lines.push(cur)
          cur = []
          cw = ~0.0
          space = nil
          sw = ~0.0
        if cur.size == 0 && w > maxw && maxw > ~0.0
          parts = split_word(a[1], maxw)
          pi = 0
          while pi < parts.size - 1
            lines.push([[:word, parts[pi]]])
            pi += 1
          cur = [[:word, parts.last]]
          cw = word_width(parts.last)
        else
          if space != nil
            cur.push([:space, space])
            cw += sw
          cur.push([:word, a[1]])
          cw += w
        space = nil
    lines.push(cur) if cur.size > 0 || lines.size == 0
    lines

  -> line_width(line)
    w = ~0.0
    line.each ->(it)
      w += it[0] == :space ? width_of(" ", @fs, it[1]) : word_width(it[1])
    w

  -> new_run(text, x, base, top, w, size, st)
    r = VttRun.new(text, x, base, w, top, @lh, size)
    r.bold = st.bold
    r.italic = st.italic
    r.underline = st.underline
    r.future = st.future
    r.color = st.color != nil ? st.color : (st.future ? VTT_FG_FUTURE : VTT_FG)
    r.background = st.background != nil ? st.background : VTT_BG
    r

  # Runs for one horizontal line whose box starts at (x, top); adjacent same-style text merges.
  -> line_runs(line, x, top)
    runs = []
    base = top + (@lh - @fs) / ~2.0 + @fs * ~0.8
    last = nil
    last_st = nil
    pen = x
    line.each ->(it)
      segs = it[0] == :space ? [[" ", it[1]]] : it[1]
      segs.each ->(sg)
        if sg[0] == :ruby
          bw = ~0.0
          sg[1].each ->(p)
            bw += width_of(p[0], @fs, p[1])
          rw = ~0.0
          sg[2].each ->(p)
            rw += width_of(p[0], @fs * ~0.5, p[1])
          tw = bw > rw ? bw : rw
          bx = pen + (tw - bw) / ~2.0
          if bx > pen && sg[1].size > 0
            pad = new_run("", pen, base, top, bx - pen, @fs, sg[1][0][1])
            runs.push(pad)
          sg[1].each ->(p)
            w = width_of(p[0], @fs, p[1])
            runs.push(new_run(p[0], bx, base, top, w, @fs, p[1]))
            bx += w
          if pen + tw > bx && sg[1].size > 0
            runs.push(new_run("", bx, base, top, pen + tw - bx, @fs, sg[1][0][1]))
          rx = pen + (tw - rw) / ~2.0
          sg[2].each ->(p)
            w = width_of(p[0], @fs * ~0.5, p[1])
            r = new_run(p[0], rx, top + @fs * ~0.12, top - @fs * ~0.5, w, @fs * ~0.5, p[1])
            r.h = @fs * ~0.5
            r.ruby = true
            r.background = nil
            runs.push(r)
            rx += w
          pen += tw
          last = nil
        else
          w = width_of(sg[0], @fs, sg[1])
          if last != nil && last_st.same?(sg[1])
            last.text = last.text + sg[0]
            last.w = last.w + w
          else
            last = new_run(sg[0], pen, base, top, w, @fs, sg[1])
            last_st = sg[1]
            runs.push(last)
          pen += w
    runs

  -> text_align(cue)
    a = cue.align
    return :left if a == :start || a == :left
    return :right if a == :end || a == :right
    :center

  -> atoms_for(cue)
    f = VttFlattener.new(@now)
    f.walk(cue.nodes, VttStyle.new)
    f.flush
    f.atoms

  -> overlaps?(x, y, w, h)
    @out.each ->(b)
      return true if x < b.x + b.w && b.x < x + w && y < b.y + b.h && b.y < y + h
    false

  -> run_all(cues)
    regions = []
    by_region = {}
    cues.each ->(cue)
      reg = cue.region
      if reg != nil && cue.vertical == :horizontal && cue.line == nil && cue.size == ~100.0
        if !by_region.has_key?(reg)
          by_region[reg] = []
          regions.push(reg)
        by_region[reg].push(cue)
      elsif cue.vertical == :horizontal
        place_horizontal(cue)
      else
        place_vertical(cue)
    regions.each ->(reg)
      place_region(reg, by_region[reg])
    @out

  # Horizontal cue outside a region (§7.2 "apply WebVTT cue settings").
  -> place_horizontal(cue)
    pos = cue.position
    if pos == nil
      pos = ~50.0
      pos = ~0.0 if cue.align == :left || cue.align == :start
      pos = ~100.0 if cue.align == :right || cue.align == :end
    pa = cue.position_align
    if pa == :auto
      pa = :center
      pa = :line_left if cue.align == :left || cue.align == :start
      pa = :line_right if cue.align == :right || cue.align == :end
    maxs = pa == :line_left ? ~100.0 - pos : (pa == :line_right ? pos : (pos <= ~50.0 ? pos * ~2.0 : (~100.0 - pos) * ~2.0))
    size = cue.size < maxs ? cue.size : maxs
    xp = pa == :line_left ? pos : (pa == :line_right ? pos - size : pos - size / ~2.0)
    bw = size / ~100.0 * @vw
    bx = @vx + xp / ~100.0 * @vw
    lines = break_lines(atoms_for(cue), bw)
    bh = lines.size * @lh
    by = @vy
    if cue.snap
      by = snap_position(cue, bx, bh, bw, true)
    else
      lp = cue.line == nil ? ~100.0 : cue.line
      by = @vy + lp / ~100.0 * @vh
      by -= bh / ~2.0 if cue.line_align == :center
      by -= bh if cue.line_align == :end
      by = @vy + @vh - bh if by + bh > @vy + @vh
      by = @vy if by < @vy
    box = VttBox.new(bx, by, bw, bh)
    box.cue = cue
    ta = text_align(cue)
    li = 0
    lines.each ->(line)
      lw = line_width(line)
      lx = bx
      lx = bx + (bw - lw) / ~2.0 if ta == :center
      lx = bx + bw - lw if ta == :right
      box.lines.push(line_runs(line, lx, by + li * @lh))
      li += 1
    @out.push(box)
    box

  # Snap-to-lines placement along the block axis; returns the box top (or left when vertical).
  -> snap_position(cue, cross, ext, cross_ext, horiz)
    full = horiz ? @vh : @vw
    origin = horiz ? @vy : @vx
    step = @lh
    maxl = (full / step).ceil + 1
    line = cue.line == nil ? -1 : cue.line.round
    line = maxl if line > maxl
    line = 0 - maxl if line < 0 - maxl
    # vertical rl counts lines from the right edge (a mirror image of lr)
    rl = !horiz && cue.vertical == :rl
    pos = step * line
    dir = ~1.0
    if line < 0
      pos += full
      dir = ~-1.0
    start = rl ? origin + full - pos - step : origin + pos
    dir = ~0.0 - dir if rl
    best = start
    best_score = nil
    switched = false
    cur = start
    guard = 0
    while guard < maxl * 4 + 8
      guard += 1
      inside = cur >= origin - ~0.01 && cur + ext <= origin + full + ~0.01
      ov = horiz ? overlaps?(cross, cur, cross_ext, ext) : overlaps?(cur, cross, ext, cross_ext)
      return cur if inside && !ov
      outside = ~0.0
      outside += origin - cur if cur < origin
      outside += cur + ext - origin - full if cur + ext > origin + full
      outside = outside + ~1000000.0 if ov
      if best_score == nil || outside < best_score
        best = cur
        best_score = outside
      cur += dir * step
      # moved past the title area: switch direction once, then settle for the best spot
      gone = dir > ~0.0 ? cur + ext > origin + full + ~0.01 : cur < origin - ~0.01
      if gone
        return best if switched
        switched = true
        cur = start
        dir = ~0.0 - dir
    best

  # Cues sharing a region: stacked bottom-up inside the region rect, clipped to its lines.
  -> place_region(reg, cues)
    rw = reg.width / ~100.0 * @vw
    rh = reg.lines * @lh
    rx = @vx + reg.viewport_x / ~100.0 * @vw - reg.anchor_x / ~100.0 * rw
    ry = @vy + reg.viewport_y / ~100.0 * @vh - reg.anchor_y / ~100.0 * rh
    laid = []
    total = 0
    cues.each ->(cue)
      ls = break_lines(atoms_for(cue), rw)
      laid.push([cue, ls])
      total += ls.size
    y = ry + rh - total * @lh
    laid.each ->(pair)
      cue = pair[0]
      ls = pair[1]
      ta = text_align(cue)
      box = nil
      ls.each ->(line)
        if y >= ry - ~0.01
          if box == nil
            box = VttBox.new(rx, y, rw, ~0.0)
            box.cue = cue
            box.region = reg
          lw = line_width(line)
          lx = rx
          lx = rx + (rw - lw) / ~2.0 if ta == :center
          lx = rx + rw - lw if ta == :right
          box.lines.push(line_runs(line, lx, y))
          box.h = box.h + @lh
        y += @lh
      @out.push(box) if box != nil

  # Vertical cue (best effort): characters stacked upright in columns of width lh.
  -> place_vertical(cue)
    pos = cue.position
    if pos == nil
      pos = ~50.0
      pos = ~0.0 if cue.align == :left || cue.align == :start
      pos = ~100.0 if cue.align == :right || cue.align == :end
    pa = cue.position_align
    if pa == :auto
      pa = :center
      pa = :line_left if cue.align == :left || cue.align == :start
      pa = :line_right if cue.align == :right || cue.align == :end
    maxs = pa == :line_left ? ~100.0 - pos : (pa == :line_right ? pos : (pos <= ~50.0 ? pos * ~2.0 : (~100.0 - pos) * ~2.0))
    size = cue.size < maxs ? cue.size : maxs
    yp = pa == :line_left ? pos : (pa == :line_right ? pos - size : pos - size / ~2.0)
    bh = size / ~100.0 * @vh
    by = @vy + yp / ~100.0 * @vh
    adv = @fs * ~1.1
    per = (bh / adv).floor
    per = 1 if per < 1
    # columns of [char, style]
    cols = [[]]
    atoms_for(cue).each ->(a)
      if a[0] == :br
        cols.push([])
      elsif a[0] == :space
        cols.last.push([" ", a[1]]) if cols.last.size > 0 && cols.last.size < per
      else
        a[1].each ->(sg)
          segs = sg[0] == :ruby ? sg[1] : [sg]
          segs.each ->(p)
            cuts = char_cuts(p[0])
            k = 0
            while k < cuts.size - 1
              cols.push([]) if cols.last.size >= per
              cols.last.push([p[0].slice(cuts[k], cuts[k + 1] - cuts[k]), p[1]])
              k += 1
    bw = cols.size * @lh
    bx = @vx
    if cue.snap
      bx = snap_position(cue, by, bw, bh, false)
    else
      lp = cue.line == nil ? ~100.0 : cue.line
      bx = @vx + lp / ~100.0 * @vw
      bx -= bw / ~2.0 if cue.line_align == :center
      bx -= bw if cue.line_align == :end
      bx = @vx + @vw - bw if bx + bw > @vx + @vw
      bx = @vx if bx < @vx
    box = VttBox.new(bx, by, bw, bh)
    box.cue = cue
    box.vertical = cue.vertical
    ta = text_align(cue)
    ci = 0
    cols.each ->(col)
      # rl: first column on the right
      cx = cue.vertical == :rl ? bx + bw - (ci + 1) * @lh : bx + ci * @lh
      colh = col.size * adv
      cy = by
      cy = by + (bh - colh) / ~2.0 if ta == :center
      cy = by + bh - colh if ta == :right
      runs = []
      col.each ->(ch)
        w = width_of(ch[0], @fs, ch[1])
        r = new_run(ch[0], cx + (@lh - w) / ~2.0, cy + @fs * ~0.9, cy, w, @fs, ch[1])
        r.h = adv
        runs.push(r)
        cy += adv
      box.lines.push(runs)
      ci += 1
    @out.push(box)
    box

# Lays out the given cues for the video content rect (x, y, w, h) at time t. Returns
# Array of VttBox in page CSS px; earlier cues claim space first (pass vtt_active output).
-> vtt_layout(cues, t, x, y, w, h, measure)
  return [] if h <= 0 || w <= 0
  VttLayout.new(x * ~1.0, y * ~1.0, w * ~1.0, h * ~1.0, measure, t * ~1.0).run_all(cues)


# HTML named character references (WHATWG table), "name=hex[.hex]" separated by spaces.
VTT_ENTITY_DATA = "AElig=c6 AElig;=c6 AMP=26 AMP;=26 Aacute=c1 Aacute;=c1 Abreve;=102 Acirc=c2 Acirc;=c2 Acy;=410 " +
  "Afr;=1d504 Agrave=c0 Agrave;=c0 Alpha;=391 Amacr;=100 And;=2a53 Aogon;=104 Aopf;=1d538 " +
  "ApplyFunction;=2061 Aring=c5 Aring;=c5 Ascr;=1d49c Assign;=2254 Atilde=c3 Atilde;=c3 Auml=c4 " +
  "Auml;=c4 Backslash;=2216 Barv;=2ae7 Barwed;=2306 Bcy;=411 Because;=2235 Bernoullis;=212c Beta;=392 " +
  "Bfr;=1d505 Bopf;=1d539 Breve;=2d8 Bscr;=212c Bumpeq;=224e CHcy;=427 COPY=a9 COPY;=a9 Cacute;=106 " +
  "Cap;=22d2 CapitalDifferentialD;=2145 Cayleys;=212d Ccaron;=10c Ccedil=c7 Ccedil;=c7 Ccirc;=108 " +
  "Cconint;=2230 Cdot;=10a Cedilla;=b8 CenterDot;=b7 Cfr;=212d Chi;=3a7 CircleDot;=2299 " +
  "CircleMinus;=2296 CirclePlus;=2295 CircleTimes;=2297 ClockwiseContourIntegral;=2232 " +
  "CloseCurlyDoubleQuote;=201d CloseCurlyQuote;=2019 Colon;=2237 Colone;=2a74 Congruent;=2261 " +
  "Conint;=222f ContourIntegral;=222e Copf;=2102 Coproduct;=2210 CounterClockwiseContourIntegral;=2233 " +
  "Cross;=2a2f Cscr;=1d49e Cup;=22d3 CupCap;=224d DD;=2145 DDotrahd;=2911 DJcy;=402 DScy;=405 " +
  "DZcy;=40f Dagger;=2021 Darr;=21a1 Dashv;=2ae4 Dcaron;=10e Dcy;=414 Del;=2207 Delta;=394 Dfr;=1d507 " +
  "DiacriticalAcute;=b4 DiacriticalDot;=2d9 DiacriticalDoubleAcute;=2dd DiacriticalGrave;=60 " +
  "DiacriticalTilde;=2dc Diamond;=22c4 DifferentialD;=2146 Dopf;=1d53b Dot;=a8 DotDot;=20dc " +
  "DotEqual;=2250 DoubleContourIntegral;=222f DoubleDot;=a8 DoubleDownArrow;=21d3 " +
  "DoubleLeftArrow;=21d0 DoubleLeftRightArrow;=21d4 DoubleLeftTee;=2ae4 DoubleLongLeftArrow;=27f8 " +
  "DoubleLongLeftRightArrow;=27fa DoubleLongRightArrow;=27f9 DoubleRightArrow;=21d2 " +
  "DoubleRightTee;=22a8 DoubleUpArrow;=21d1 DoubleUpDownArrow;=21d5 DoubleVerticalBar;=2225 " +
  "DownArrow;=2193 DownArrowBar;=2913 DownArrowUpArrow;=21f5 DownBreve;=311 DownLeftRightVector;=2950 " +
  "DownLeftTeeVector;=295e DownLeftVector;=21bd DownLeftVectorBar;=2956 DownRightTeeVector;=295f " +
  "DownRightVector;=21c1 DownRightVectorBar;=2957 DownTee;=22a4 DownTeeArrow;=21a7 Downarrow;=21d3 " +
  "Dscr;=1d49f Dstrok;=110 ENG;=14a ETH=d0 ETH;=d0 Eacute=c9 Eacute;=c9 Ecaron;=11a Ecirc=ca Ecirc;=ca " +
  "Ecy;=42d Edot;=116 Efr;=1d508 Egrave=c8 Egrave;=c8 Element;=2208 Emacr;=112 EmptySmallSquare;=25fb " +
  "EmptyVerySmallSquare;=25ab Eogon;=118 Eopf;=1d53c Epsilon;=395 Equal;=2a75 EqualTilde;=2242 " +
  "Equilibrium;=21cc Escr;=2130 Esim;=2a73 Eta;=397 Euml=cb Euml;=cb Exists;=2203 ExponentialE;=2147 " +
  "Fcy;=424 Ffr;=1d509 FilledSmallSquare;=25fc FilledVerySmallSquare;=25aa Fopf;=1d53d ForAll;=2200 " +
  "Fouriertrf;=2131 Fscr;=2131 GJcy;=403 GT=3e GT;=3e Gamma;=393 Gammad;=3dc Gbreve;=11e Gcedil;=122 " +
  "Gcirc;=11c Gcy;=413 Gdot;=120 Gfr;=1d50a Gg;=22d9 Gopf;=1d53e GreaterEqual;=2265 " +
  "GreaterEqualLess;=22db GreaterFullEqual;=2267 GreaterGreater;=2aa2 GreaterLess;=2277 " +
  "GreaterSlantEqual;=2a7e GreaterTilde;=2273 Gscr;=1d4a2 Gt;=226b HARDcy;=42a Hacek;=2c7 Hat;=5e " +
  "Hcirc;=124 Hfr;=210c HilbertSpace;=210b Hopf;=210d HorizontalLine;=2500 Hscr;=210b Hstrok;=126 " +
  "HumpDownHump;=224e HumpEqual;=224f IEcy;=415 IJlig;=132 IOcy;=401 Iacute=cd Iacute;=cd Icirc=ce " +
  "Icirc;=ce Icy;=418 Idot;=130 Ifr;=2111 Igrave=cc Igrave;=cc Im;=2111 Imacr;=12a ImaginaryI;=2148 " +
  "Implies;=21d2 Int;=222c Integral;=222b Intersection;=22c2 InvisibleComma;=2063 InvisibleTimes;=2062 " +
  "Iogon;=12e Iopf;=1d540 Iota;=399 Iscr;=2110 Itilde;=128 Iukcy;=406 Iuml=cf Iuml;=cf Jcirc;=134 " +
  "Jcy;=419 Jfr;=1d50d Jopf;=1d541 Jscr;=1d4a5 Jsercy;=408 Jukcy;=404 KHcy;=425 KJcy;=40c Kappa;=39a " +
  "Kcedil;=136 Kcy;=41a Kfr;=1d50e Kopf;=1d542 Kscr;=1d4a6 LJcy;=409 LT=3c LT;=3c Lacute;=139 " +
  "Lambda;=39b Lang;=27ea Laplacetrf;=2112 Larr;=219e Lcaron;=13d Lcedil;=13b Lcy;=41b " +
  "LeftAngleBracket;=27e8 LeftArrow;=2190 LeftArrowBar;=21e4 LeftArrowRightArrow;=21c6 " +
  "LeftCeiling;=2308 LeftDoubleBracket;=27e6 LeftDownTeeVector;=2961 LeftDownVector;=21c3 " +
  "LeftDownVectorBar;=2959 LeftFloor;=230a LeftRightArrow;=2194 LeftRightVector;=294e LeftTee;=22a3 " +
  "LeftTeeArrow;=21a4 LeftTeeVector;=295a LeftTriangle;=22b2 LeftTriangleBar;=29cf " +
  "LeftTriangleEqual;=22b4 LeftUpDownVector;=2951 LeftUpTeeVector;=2960 LeftUpVector;=21bf " +
  "LeftUpVectorBar;=2958 LeftVector;=21bc LeftVectorBar;=2952 Leftarrow;=21d0 Leftrightarrow;=21d4 " +
  "LessEqualGreater;=22da LessFullEqual;=2266 LessGreater;=2276 LessLess;=2aa1 LessSlantEqual;=2a7d " +
  "LessTilde;=2272 Lfr;=1d50f Ll;=22d8 Lleftarrow;=21da Lmidot;=13f LongLeftArrow;=27f5 " +
  "LongLeftRightArrow;=27f7 LongRightArrow;=27f6 Longleftarrow;=27f8 Longleftrightarrow;=27fa " +
  "Longrightarrow;=27f9 Lopf;=1d543 LowerLeftArrow;=2199 LowerRightArrow;=2198 Lscr;=2112 Lsh;=21b0 " +
  "Lstrok;=141 Lt;=226a Map;=2905 Mcy;=41c MediumSpace;=205f Mellintrf;=2133 Mfr;=1d510 " +
  "MinusPlus;=2213 Mopf;=1d544 Mscr;=2133 Mu;=39c NJcy;=40a Nacute;=143 Ncaron;=147 Ncedil;=145 " +
  "Ncy;=41d NegativeMediumSpace;=200b NegativeThickSpace;=200b NegativeThinSpace;=200b " +
  "NegativeVeryThinSpace;=200b NestedGreaterGreater;=226b NestedLessLess;=226a NewLine;=a Nfr;=1d511 " +
  "NoBreak;=2060 NonBreakingSpace;=a0 Nopf;=2115 Not;=2aec NotCongruent;=2262 NotCupCap;=226d " +
  "NotDoubleVerticalBar;=2226 NotElement;=2209 NotEqual;=2260 NotEqualTilde;=2242.338 NotExists;=2204 " +
  "NotGreater;=226f NotGreaterEqual;=2271 NotGreaterFullEqual;=2267.338 NotGreaterGreater;=226b.338 " +
  "NotGreaterLess;=2279 NotGreaterSlantEqual;=2a7e.338 NotGreaterTilde;=2275 NotHumpDownHump;=224e.338 " +
  "NotHumpEqual;=224f.338 NotLeftTriangle;=22ea NotLeftTriangleBar;=29cf.338 " +
  "NotLeftTriangleEqual;=22ec NotLess;=226e NotLessEqual;=2270 NotLessGreater;=2278 " +
  "NotLessLess;=226a.338 NotLessSlantEqual;=2a7d.338 NotLessTilde;=2274 " +
  "NotNestedGreaterGreater;=2aa2.338 NotNestedLessLess;=2aa1.338 NotPrecedes;=2280 " +
  "NotPrecedesEqual;=2aaf.338 NotPrecedesSlantEqual;=22e0 NotReverseElement;=220c " +
  "NotRightTriangle;=22eb NotRightTriangleBar;=29d0.338 NotRightTriangleEqual;=22ed " +
  "NotSquareSubset;=228f.338 NotSquareSubsetEqual;=22e2 NotSquareSuperset;=2290.338 " +
  "NotSquareSupersetEqual;=22e3 NotSubset;=2282.20d2 NotSubsetEqual;=2288 NotSucceeds;=2281 " +
  "NotSucceedsEqual;=2ab0.338 NotSucceedsSlantEqual;=22e1 NotSucceedsTilde;=227f.338 " +
  "NotSuperset;=2283.20d2 NotSupersetEqual;=2289 NotTilde;=2241 NotTildeEqual;=2244 " +
  "NotTildeFullEqual;=2247 NotTildeTilde;=2249 NotVerticalBar;=2224 Nscr;=1d4a9 Ntilde=d1 Ntilde;=d1 " +
  "Nu;=39d OElig;=152 Oacute=d3 Oacute;=d3 Ocirc=d4 Ocirc;=d4 Ocy;=41e Odblac;=150 Ofr;=1d512 " +
  "Ograve=d2 Ograve;=d2 Omacr;=14c Omega;=3a9 Omicron;=39f Oopf;=1d546 OpenCurlyDoubleQuote;=201c " +
  "OpenCurlyQuote;=2018 Or;=2a54 Oscr;=1d4aa Oslash=d8 Oslash;=d8 Otilde=d5 Otilde;=d5 Otimes;=2a37 " +
  "Ouml=d6 Ouml;=d6 OverBar;=203e OverBrace;=23de OverBracket;=23b4 OverParenthesis;=23dc " +
  "PartialD;=2202 Pcy;=41f Pfr;=1d513 Phi;=3a6 Pi;=3a0 PlusMinus;=b1 Poincareplane;=210c Popf;=2119 " +
  "Pr;=2abb Precedes;=227a PrecedesEqual;=2aaf PrecedesSlantEqual;=227c PrecedesTilde;=227e " +
  "Prime;=2033 Product;=220f Proportion;=2237 Proportional;=221d Pscr;=1d4ab Psi;=3a8 QUOT=22 QUOT;=22 " +
  "Qfr;=1d514 Qopf;=211a Qscr;=1d4ac RBarr;=2910 REG=ae REG;=ae Racute;=154 Rang;=27eb Rarr;=21a0 " +
  "Rarrtl;=2916 Rcaron;=158 Rcedil;=156 Rcy;=420 Re;=211c ReverseElement;=220b " +
  "ReverseEquilibrium;=21cb ReverseUpEquilibrium;=296f Rfr;=211c Rho;=3a1 RightAngleBracket;=27e9 " +
  "RightArrow;=2192 RightArrowBar;=21e5 RightArrowLeftArrow;=21c4 RightCeiling;=2309 " +
  "RightDoubleBracket;=27e7 RightDownTeeVector;=295d RightDownVector;=21c2 RightDownVectorBar;=2955 " +
  "RightFloor;=230b RightTee;=22a2 RightTeeArrow;=21a6 RightTeeVector;=295b RightTriangle;=22b3 " +
  "RightTriangleBar;=29d0 RightTriangleEqual;=22b5 RightUpDownVector;=294f RightUpTeeVector;=295c " +
  "RightUpVector;=21be RightUpVectorBar;=2954 RightVector;=21c0 RightVectorBar;=2953 Rightarrow;=21d2 " +
  "Ropf;=211d RoundImplies;=2970 Rrightarrow;=21db Rscr;=211b Rsh;=21b1 RuleDelayed;=29f4 SHCHcy;=429 " +
  "SHcy;=428 SOFTcy;=42c Sacute;=15a Sc;=2abc Scaron;=160 Scedil;=15e Scirc;=15c Scy;=421 Sfr;=1d516 " +
  "ShortDownArrow;=2193 ShortLeftArrow;=2190 ShortRightArrow;=2192 ShortUpArrow;=2191 Sigma;=3a3 " +
  "SmallCircle;=2218 Sopf;=1d54a Sqrt;=221a Square;=25a1 SquareIntersection;=2293 SquareSubset;=228f " +
  "SquareSubsetEqual;=2291 SquareSuperset;=2290 SquareSupersetEqual;=2292 SquareUnion;=2294 " +
  "Sscr;=1d4ae Star;=22c6 Sub;=22d0 Subset;=22d0 SubsetEqual;=2286 Succeeds;=227b SucceedsEqual;=2ab0 " +
  "SucceedsSlantEqual;=227d SucceedsTilde;=227f SuchThat;=220b Sum;=2211 Sup;=22d1 Superset;=2283 " +
  "SupersetEqual;=2287 Supset;=22d1 THORN=de THORN;=de TRADE;=2122 TSHcy;=40b TScy;=426 Tab;=9 " +
  "Tau;=3a4 Tcaron;=164 Tcedil;=162 Tcy;=422 Tfr;=1d517 Therefore;=2234 Theta;=398 " +
  "ThickSpace;=205f.200a ThinSpace;=2009 Tilde;=223c TildeEqual;=2243 TildeFullEqual;=2245 " +
  "TildeTilde;=2248 Topf;=1d54b TripleDot;=20db Tscr;=1d4af Tstrok;=166 Uacute=da Uacute;=da " +
  "Uarr;=219f Uarrocir;=2949 Ubrcy;=40e Ubreve;=16c Ucirc=db Ucirc;=db Ucy;=423 Udblac;=170 Ufr;=1d518 " +
  "Ugrave=d9 Ugrave;=d9 Umacr;=16a UnderBar;=5f UnderBrace;=23df UnderBracket;=23b5 " +
  "UnderParenthesis;=23dd Union;=22c3 UnionPlus;=228e Uogon;=172 Uopf;=1d54c UpArrow;=2191 " +
  "UpArrowBar;=2912 UpArrowDownArrow;=21c5 UpDownArrow;=2195 UpEquilibrium;=296e UpTee;=22a5 " +
  "UpTeeArrow;=21a5 Uparrow;=21d1 Updownarrow;=21d5 UpperLeftArrow;=2196 UpperRightArrow;=2197 " +
  "Upsi;=3d2 Upsilon;=3a5 Uring;=16e Uscr;=1d4b0 Utilde;=168 Uuml=dc Uuml;=dc VDash;=22ab Vbar;=2aeb " +
  "Vcy;=412 Vdash;=22a9 Vdashl;=2ae6 Vee;=22c1 Verbar;=2016 Vert;=2016 VerticalBar;=2223 " +
  "VerticalLine;=7c VerticalSeparator;=2758 VerticalTilde;=2240 VeryThinSpace;=200a Vfr;=1d519 " +
  "Vopf;=1d54d Vscr;=1d4b1 Vvdash;=22aa Wcirc;=174 Wedge;=22c0 Wfr;=1d51a Wopf;=1d54e Wscr;=1d4b2 " +
  "Xfr;=1d51b Xi;=39e Xopf;=1d54f Xscr;=1d4b3 YAcy;=42f YIcy;=407 YUcy;=42e Yacute=dd Yacute;=dd " +
  "Ycirc;=176 Ycy;=42b Yfr;=1d51c Yopf;=1d550 Yscr;=1d4b4 Yuml;=178 ZHcy;=416 Zacute;=179 Zcaron;=17d " +
  "Zcy;=417 Zdot;=17b ZeroWidthSpace;=200b Zeta;=396 Zfr;=2128 Zopf;=2124 Zscr;=1d4b5 aacute=e1 " +
  "aacute;=e1 abreve;=103 ac;=223e acE;=223e.333 acd;=223f acirc=e2 acirc;=e2 acute=b4 acute;=b4 " +
  "acy;=430 aelig=e6 aelig;=e6 af;=2061 afr;=1d51e agrave=e0 agrave;=e0 alefsym;=2135 aleph;=2135 " +
  "alpha;=3b1 amacr;=101 amalg;=2a3f amp=26 amp;=26 and;=2227 andand;=2a55 andd;=2a5c andslope;=2a58 " +
  "andv;=2a5a ang;=2220 ange;=29a4 angle;=2220 angmsd;=2221 angmsdaa;=29a8 angmsdab;=29a9 " +
  "angmsdac;=29aa angmsdad;=29ab angmsdae;=29ac angmsdaf;=29ad angmsdag;=29ae angmsdah;=29af " +
  "angrt;=221f angrtvb;=22be angrtvbd;=299d angsph;=2222 angst;=c5 angzarr;=237c aogon;=105 " +
  "aopf;=1d552 ap;=2248 apE;=2a70 apacir;=2a6f ape;=224a apid;=224b apos;=27 approx;=2248 " +
  "approxeq;=224a aring=e5 aring;=e5 ascr;=1d4b6 ast;=2a asymp;=2248 asympeq;=224d atilde=e3 " +
  "atilde;=e3 auml=e4 auml;=e4 awconint;=2233 awint;=2a11 bNot;=2aed backcong;=224c backepsilon;=3f6 " +
  "backprime;=2035 backsim;=223d backsimeq;=22cd barvee;=22bd barwed;=2305 barwedge;=2305 bbrk;=23b5 " +
  "bbrktbrk;=23b6 bcong;=224c bcy;=431 bdquo;=201e becaus;=2235 because;=2235 bemptyv;=29b0 bepsi;=3f6 " +
  "bernou;=212c beta;=3b2 beth;=2136 between;=226c bfr;=1d51f bigcap;=22c2 bigcirc;=25ef bigcup;=22c3 " +
  "bigodot;=2a00 bigoplus;=2a01 bigotimes;=2a02 bigsqcup;=2a06 bigstar;=2605 bigtriangledown;=25bd " +
  "bigtriangleup;=25b3 biguplus;=2a04 bigvee;=22c1 bigwedge;=22c0 bkarow;=290d blacklozenge;=29eb " +
  "blacksquare;=25aa blacktriangle;=25b4 blacktriangledown;=25be blacktriangleleft;=25c2 " +
  "blacktriangleright;=25b8 blank;=2423 blk12;=2592 blk14;=2591 blk34;=2593 block;=2588 bne;=3d.20e5 " +
  "bnequiv;=2261.20e5 bnot;=2310 bopf;=1d553 bot;=22a5 bottom;=22a5 bowtie;=22c8 boxDL;=2557 " +
  "boxDR;=2554 boxDl;=2556 boxDr;=2553 boxH;=2550 boxHD;=2566 boxHU;=2569 boxHd;=2564 boxHu;=2567 " +
  "boxUL;=255d boxUR;=255a boxUl;=255c boxUr;=2559 boxV;=2551 boxVH;=256c boxVL;=2563 boxVR;=2560 " +
  "boxVh;=256b boxVl;=2562 boxVr;=255f boxbox;=29c9 boxdL;=2555 boxdR;=2552 boxdl;=2510 boxdr;=250c " +
  "boxh;=2500 boxhD;=2565 boxhU;=2568 boxhd;=252c boxhu;=2534 boxminus;=229f boxplus;=229e " +
  "boxtimes;=22a0 boxuL;=255b boxuR;=2558 boxul;=2518 boxur;=2514 boxv;=2502 boxvH;=256a boxvL;=2561 " +
  "boxvR;=255e boxvh;=253c boxvl;=2524 boxvr;=251c bprime;=2035 breve;=2d8 brvbar=a6 brvbar;=a6 " +
  "bscr;=1d4b7 bsemi;=204f bsim;=223d bsime;=22cd bsol;=5c bsolb;=29c5 bsolhsub;=27c8 bull;=2022 " +
  "bullet;=2022 bump;=224e bumpE;=2aae bumpe;=224f bumpeq;=224f cacute;=107 cap;=2229 capand;=2a44 " +
  "capbrcup;=2a49 capcap;=2a4b capcup;=2a47 capdot;=2a40 caps;=2229.fe00 caret;=2041 caron;=2c7 " +
  "ccaps;=2a4d ccaron;=10d ccedil=e7 ccedil;=e7 ccirc;=109 ccups;=2a4c ccupssm;=2a50 cdot;=10b " +
  "cedil=b8 cedil;=b8 cemptyv;=29b2 cent=a2 cent;=a2 centerdot;=b7 cfr;=1d520 chcy;=447 check;=2713 " +
  "checkmark;=2713 chi;=3c7 cir;=25cb cirE;=29c3 circ;=2c6 circeq;=2257 circlearrowleft;=21ba " +
  "circlearrowright;=21bb circledR;=ae circledS;=24c8 circledast;=229b circledcirc;=229a " +
  "circleddash;=229d cire;=2257 cirfnint;=2a10 cirmid;=2aef cirscir;=29c2 clubs;=2663 clubsuit;=2663 " +
  "colon;=3a colone;=2254 coloneq;=2254 comma;=2c commat;=40 comp;=2201 compfn;=2218 complement;=2201 " +
  "complexes;=2102 cong;=2245 congdot;=2a6d conint;=222e copf;=1d554 coprod;=2210 copy=a9 copy;=a9 " +
  "copysr;=2117 crarr;=21b5 cross;=2717 cscr;=1d4b8 csub;=2acf csube;=2ad1 csup;=2ad0 csupe;=2ad2 " +
  "ctdot;=22ef cudarrl;=2938 cudarrr;=2935 cuepr;=22de cuesc;=22df cularr;=21b6 cularrp;=293d " +
  "cup;=222a cupbrcap;=2a48 cupcap;=2a46 cupcup;=2a4a cupdot;=228d cupor;=2a45 cups;=222a.fe00 " +
  "curarr;=21b7 curarrm;=293c curlyeqprec;=22de curlyeqsucc;=22df curlyvee;=22ce curlywedge;=22cf " +
  "curren=a4 curren;=a4 curvearrowleft;=21b6 curvearrowright;=21b7 cuvee;=22ce cuwed;=22cf " +
  "cwconint;=2232 cwint;=2231 cylcty;=232d dArr;=21d3 dHar;=2965 dagger;=2020 daleth;=2138 darr;=2193 " +
  "dash;=2010 dashv;=22a3 dbkarow;=290f dblac;=2dd dcaron;=10f dcy;=434 dd;=2146 ddagger;=2021 " +
  "ddarr;=21ca ddotseq;=2a77 deg=b0 deg;=b0 delta;=3b4 demptyv;=29b1 dfisht;=297f dfr;=1d521 " +
  "dharl;=21c3 dharr;=21c2 diam;=22c4 diamond;=22c4 diamondsuit;=2666 diams;=2666 die;=a8 digamma;=3dd " +
  "disin;=22f2 div;=f7 divide=f7 divide;=f7 divideontimes;=22c7 divonx;=22c7 djcy;=452 dlcorn;=231e " +
  "dlcrop;=230d dollar;=24 dopf;=1d555 dot;=2d9 doteq;=2250 doteqdot;=2251 dotminus;=2238 " +
  "dotplus;=2214 dotsquare;=22a1 doublebarwedge;=2306 downarrow;=2193 downdownarrows;=21ca " +
  "downharpoonleft;=21c3 downharpoonright;=21c2 drbkarow;=2910 drcorn;=231f drcrop;=230c dscr;=1d4b9 " +
  "dscy;=455 dsol;=29f6 dstrok;=111 dtdot;=22f1 dtri;=25bf dtrif;=25be duarr;=21f5 duhar;=296f " +
  "dwangle;=29a6 dzcy;=45f dzigrarr;=27ff eDDot;=2a77 eDot;=2251 eacute=e9 eacute;=e9 easter;=2a6e " +
  "ecaron;=11b ecir;=2256 ecirc=ea ecirc;=ea ecolon;=2255 ecy;=44d edot;=117 ee;=2147 efDot;=2252 " +
  "efr;=1d522 eg;=2a9a egrave=e8 egrave;=e8 egs;=2a96 egsdot;=2a98 el;=2a99 elinters;=23e7 ell;=2113 " +
  "els;=2a95 elsdot;=2a97 emacr;=113 empty;=2205 emptyset;=2205 emptyv;=2205 emsp13;=2004 emsp14;=2005 " +
  "emsp;=2003 eng;=14b ensp;=2002 eogon;=119 eopf;=1d556 epar;=22d5 eparsl;=29e3 eplus;=2a71 epsi;=3b5 " +
  "epsilon;=3b5 epsiv;=3f5 eqcirc;=2256 eqcolon;=2255 eqsim;=2242 eqslantgtr;=2a96 eqslantless;=2a95 " +
  "equals;=3d equest;=225f equiv;=2261 equivDD;=2a78 eqvparsl;=29e5 erDot;=2253 erarr;=2971 escr;=212f " +
  "esdot;=2250 esim;=2242 eta;=3b7 eth=f0 eth;=f0 euml=eb euml;=eb euro;=20ac excl;=21 exist;=2203 " +
  "expectation;=2130 exponentiale;=2147 fallingdotseq;=2252 fcy;=444 female;=2640 ffilig;=fb03 " +
  "fflig;=fb00 ffllig;=fb04 ffr;=1d523 filig;=fb01 fjlig;=66.6a flat;=266d fllig;=fb02 fltns;=25b1 " +
  "fnof;=192 fopf;=1d557 forall;=2200 fork;=22d4 forkv;=2ad9 fpartint;=2a0d frac12=bd frac12;=bd " +
  "frac13;=2153 frac14=bc frac14;=bc frac15;=2155 frac16;=2159 frac18;=215b frac23;=2154 frac25;=2156 " +
  "frac34=be frac34;=be frac35;=2157 frac38;=215c frac45;=2158 frac56;=215a frac58;=215d frac78;=215e " +
  "frasl;=2044 frown;=2322 fscr;=1d4bb gE;=2267 gEl;=2a8c gacute;=1f5 gamma;=3b3 gammad;=3dd gap;=2a86 " +
  "gbreve;=11f gcirc;=11d gcy;=433 gdot;=121 ge;=2265 gel;=22db geq;=2265 geqq;=2267 geqslant;=2a7e " +
  "ges;=2a7e gescc;=2aa9 gesdot;=2a80 gesdoto;=2a82 gesdotol;=2a84 gesl;=22db.fe00 gesles;=2a94 " +
  "gfr;=1d524 gg;=226b ggg;=22d9 gimel;=2137 gjcy;=453 gl;=2277 glE;=2a92 gla;=2aa5 glj;=2aa4 " +
  "gnE;=2269 gnap;=2a8a gnapprox;=2a8a gne;=2a88 gneq;=2a88 gneqq;=2269 gnsim;=22e7 gopf;=1d558 " +
  "grave;=60 gscr;=210a gsim;=2273 gsime;=2a8e gsiml;=2a90 gt=3e gt;=3e gtcc;=2aa7 gtcir;=2a7a " +
  "gtdot;=22d7 gtlPar;=2995 gtquest;=2a7c gtrapprox;=2a86 gtrarr;=2978 gtrdot;=22d7 gtreqless;=22db " +
  "gtreqqless;=2a8c gtrless;=2277 gtrsim;=2273 gvertneqq;=2269.fe00 gvnE;=2269.fe00 hArr;=21d4 " +
  "hairsp;=200a half;=bd hamilt;=210b hardcy;=44a harr;=2194 harrcir;=2948 harrw;=21ad hbar;=210f " +
  "hcirc;=125 hearts;=2665 heartsuit;=2665 hellip;=2026 hercon;=22b9 hfr;=1d525 hksearow;=2925 " +
  "hkswarow;=2926 hoarr;=21ff homtht;=223b hookleftarrow;=21a9 hookrightarrow;=21aa hopf;=1d559 " +
  "horbar;=2015 hscr;=1d4bd hslash;=210f hstrok;=127 hybull;=2043 hyphen;=2010 iacute=ed iacute;=ed " +
  "ic;=2063 icirc=ee icirc;=ee icy;=438 iecy;=435 iexcl=a1 iexcl;=a1 iff;=21d4 ifr;=1d526 igrave=ec " +
  "igrave;=ec ii;=2148 iiiint;=2a0c iiint;=222d iinfin;=29dc iiota;=2129 ijlig;=133 imacr;=12b " +
  "image;=2111 imagline;=2110 imagpart;=2111 imath;=131 imof;=22b7 imped;=1b5 in;=2208 incare;=2105 " +
  "infin;=221e infintie;=29dd inodot;=131 int;=222b intcal;=22ba integers;=2124 intercal;=22ba " +
  "intlarhk;=2a17 intprod;=2a3c iocy;=451 iogon;=12f iopf;=1d55a iota;=3b9 iprod;=2a3c iquest=bf " +
  "iquest;=bf iscr;=1d4be isin;=2208 isinE;=22f9 isindot;=22f5 isins;=22f4 isinsv;=22f3 isinv;=2208 " +
  "it;=2062 itilde;=129 iukcy;=456 iuml=ef iuml;=ef jcirc;=135 jcy;=439 jfr;=1d527 jmath;=237 " +
  "jopf;=1d55b jscr;=1d4bf jsercy;=458 jukcy;=454 kappa;=3ba kappav;=3f0 kcedil;=137 kcy;=43a " +
  "kfr;=1d528 kgreen;=138 khcy;=445 kjcy;=45c kopf;=1d55c kscr;=1d4c0 lAarr;=21da lArr;=21d0 " +
  "lAtail;=291b lBarr;=290e lE;=2266 lEg;=2a8b lHar;=2962 lacute;=13a laemptyv;=29b4 lagran;=2112 " +
  "lambda;=3bb lang;=27e8 langd;=2991 langle;=27e8 lap;=2a85 laquo=ab laquo;=ab larr;=2190 larrb;=21e4 " +
  "larrbfs;=291f larrfs;=291d larrhk;=21a9 larrlp;=21ab larrpl;=2939 larrsim;=2973 larrtl;=21a2 " +
  "lat;=2aab latail;=2919 late;=2aad lates;=2aad.fe00 lbarr;=290c lbbrk;=2772 lbrace;=7b lbrack;=5b " +
  "lbrke;=298b lbrksld;=298f lbrkslu;=298d lcaron;=13e lcedil;=13c lceil;=2308 lcub;=7b lcy;=43b " +
  "ldca;=2936 ldquo;=201c ldquor;=201e ldrdhar;=2967 ldrushar;=294b ldsh;=21b2 le;=2264 " +
  "leftarrow;=2190 leftarrowtail;=21a2 leftharpoondown;=21bd leftharpoonup;=21bc leftleftarrows;=21c7 " +
  "leftrightarrow;=2194 leftrightarrows;=21c6 leftrightharpoons;=21cb leftrightsquigarrow;=21ad " +
  "leftthreetimes;=22cb leg;=22da leq;=2264 leqq;=2266 leqslant;=2a7d les;=2a7d lescc;=2aa8 " +
  "lesdot;=2a7f lesdoto;=2a81 lesdotor;=2a83 lesg;=22da.fe00 lesges;=2a93 lessapprox;=2a85 " +
  "lessdot;=22d6 lesseqgtr;=22da lesseqqgtr;=2a8b lessgtr;=2276 lesssim;=2272 lfisht;=297c " +
  "lfloor;=230a lfr;=1d529 lg;=2276 lgE;=2a91 lhard;=21bd lharu;=21bc lharul;=296a lhblk;=2584 " +
  "ljcy;=459 ll;=226a llarr;=21c7 llcorner;=231e llhard;=296b lltri;=25fa lmidot;=140 lmoust;=23b0 " +
  "lmoustache;=23b0 lnE;=2268 lnap;=2a89 lnapprox;=2a89 lne;=2a87 lneq;=2a87 lneqq;=2268 lnsim;=22e6 " +
  "loang;=27ec loarr;=21fd lobrk;=27e6 longleftarrow;=27f5 longleftrightarrow;=27f7 longmapsto;=27fc " +
  "longrightarrow;=27f6 looparrowleft;=21ab looparrowright;=21ac lopar;=2985 lopf;=1d55d loplus;=2a2d " +
  "lotimes;=2a34 lowast;=2217 lowbar;=5f loz;=25ca lozenge;=25ca lozf;=29eb lpar;=28 lparlt;=2993 " +
  "lrarr;=21c6 lrcorner;=231f lrhar;=21cb lrhard;=296d lrm;=200e lrtri;=22bf lsaquo;=2039 lscr;=1d4c1 " +
  "lsh;=21b0 lsim;=2272 lsime;=2a8d lsimg;=2a8f lsqb;=5b lsquo;=2018 lsquor;=201a lstrok;=142 lt=3c " +
  "lt;=3c ltcc;=2aa6 ltcir;=2a79 ltdot;=22d6 lthree;=22cb ltimes;=22c9 ltlarr;=2976 ltquest;=2a7b " +
  "ltrPar;=2996 ltri;=25c3 ltrie;=22b4 ltrif;=25c2 lurdshar;=294a luruhar;=2966 lvertneqq;=2268.fe00 " +
  "lvnE;=2268.fe00 mDDot;=223a macr=af macr;=af male;=2642 malt;=2720 maltese;=2720 map;=21a6 " +
  "mapsto;=21a6 mapstodown;=21a7 mapstoleft;=21a4 mapstoup;=21a5 marker;=25ae mcomma;=2a29 mcy;=43c " +
  "mdash;=2014 measuredangle;=2221 mfr;=1d52a mho;=2127 micro=b5 micro;=b5 mid;=2223 midast;=2a " +
  "midcir;=2af0 middot=b7 middot;=b7 minus;=2212 minusb;=229f minusd;=2238 minusdu;=2a2a mlcp;=2adb " +
  "mldr;=2026 mnplus;=2213 models;=22a7 mopf;=1d55e mp;=2213 mscr;=1d4c2 mstpos;=223e mu;=3bc " +
  "multimap;=22b8 mumap;=22b8 nGg;=22d9.338 nGt;=226b.20d2 nGtv;=226b.338 nLeftarrow;=21cd " +
  "nLeftrightarrow;=21ce nLl;=22d8.338 nLt;=226a.20d2 nLtv;=226a.338 nRightarrow;=21cf nVDash;=22af " +
  "nVdash;=22ae nabla;=2207 nacute;=144 nang;=2220.20d2 nap;=2249 napE;=2a70.338 napid;=224b.338 " +
  "napos;=149 napprox;=2249 natur;=266e natural;=266e naturals;=2115 nbsp=a0 nbsp;=a0 nbump;=224e.338 " +
  "nbumpe;=224f.338 ncap;=2a43 ncaron;=148 ncedil;=146 ncong;=2247 ncongdot;=2a6d.338 ncup;=2a42 " +
  "ncy;=43d ndash;=2013 ne;=2260 neArr;=21d7 nearhk;=2924 nearr;=2197 nearrow;=2197 nedot;=2250.338 " +
  "nequiv;=2262 nesear;=2928 nesim;=2242.338 nexist;=2204 nexists;=2204 nfr;=1d52b ngE;=2267.338 " +
  "nge;=2271 ngeq;=2271 ngeqq;=2267.338 ngeqslant;=2a7e.338 nges;=2a7e.338 ngsim;=2275 ngt;=226f " +
  "ngtr;=226f nhArr;=21ce nharr;=21ae nhpar;=2af2 ni;=220b nis;=22fc nisd;=22fa niv;=220b njcy;=45a " +
  "nlArr;=21cd nlE;=2266.338 nlarr;=219a nldr;=2025 nle;=2270 nleftarrow;=219a nleftrightarrow;=21ae " +
  "nleq;=2270 nleqq;=2266.338 nleqslant;=2a7d.338 nles;=2a7d.338 nless;=226e nlsim;=2274 nlt;=226e " +
  "nltri;=22ea nltrie;=22ec nmid;=2224 nopf;=1d55f not=ac not;=ac notin;=2209 notinE;=22f9.338 " +
  "notindot;=22f5.338 notinva;=2209 notinvb;=22f7 notinvc;=22f6 notni;=220c notniva;=220c " +
  "notnivb;=22fe notnivc;=22fd npar;=2226 nparallel;=2226 nparsl;=2afd.20e5 npart;=2202.338 " +
  "npolint;=2a14 npr;=2280 nprcue;=22e0 npre;=2aaf.338 nprec;=2280 npreceq;=2aaf.338 nrArr;=21cf " +
  "nrarr;=219b nrarrc;=2933.338 nrarrw;=219d.338 nrightarrow;=219b nrtri;=22eb nrtrie;=22ed nsc;=2281 " +
  "nsccue;=22e1 nsce;=2ab0.338 nscr;=1d4c3 nshortmid;=2224 nshortparallel;=2226 nsim;=2241 nsime;=2244 " +
  "nsimeq;=2244 nsmid;=2224 nspar;=2226 nsqsube;=22e2 nsqsupe;=22e3 nsub;=2284 nsubE;=2ac5.338 " +
  "nsube;=2288 nsubset;=2282.20d2 nsubseteq;=2288 nsubseteqq;=2ac5.338 nsucc;=2281 nsucceq;=2ab0.338 " +
  "nsup;=2285 nsupE;=2ac6.338 nsupe;=2289 nsupset;=2283.20d2 nsupseteq;=2289 nsupseteqq;=2ac6.338 " +
  "ntgl;=2279 ntilde=f1 ntilde;=f1 ntlg;=2278 ntriangleleft;=22ea ntrianglelefteq;=22ec " +
  "ntriangleright;=22eb ntrianglerighteq;=22ed nu;=3bd num;=23 numero;=2116 numsp;=2007 nvDash;=22ad " +
  "nvHarr;=2904 nvap;=224d.20d2 nvdash;=22ac nvge;=2265.20d2 nvgt;=3e.20d2 nvinfin;=29de nvlArr;=2902 " +
  "nvle;=2264.20d2 nvlt;=3c.20d2 nvltrie;=22b4.20d2 nvrArr;=2903 nvrtrie;=22b5.20d2 nvsim;=223c.20d2 " +
  "nwArr;=21d6 nwarhk;=2923 nwarr;=2196 nwarrow;=2196 nwnear;=2927 oS;=24c8 oacute=f3 oacute;=f3 " +
  "oast;=229b ocir;=229a ocirc=f4 ocirc;=f4 ocy;=43e odash;=229d odblac;=151 odiv;=2a38 odot;=2299 " +
  "odsold;=29bc oelig;=153 ofcir;=29bf ofr;=1d52c ogon;=2db ograve=f2 ograve;=f2 ogt;=29c1 ohbar;=29b5 " +
  "ohm;=3a9 oint;=222e olarr;=21ba olcir;=29be olcross;=29bb oline;=203e olt;=29c0 omacr;=14d " +
  "omega;=3c9 omicron;=3bf omid;=29b6 ominus;=2296 oopf;=1d560 opar;=29b7 operp;=29b9 oplus;=2295 " +
  "or;=2228 orarr;=21bb ord;=2a5d order;=2134 orderof;=2134 ordf=aa ordf;=aa ordm=ba ordm;=ba " +
  "origof;=22b6 oror;=2a56 orslope;=2a57 orv;=2a5b oscr;=2134 oslash=f8 oslash;=f8 osol;=2298 " +
  "otilde=f5 otilde;=f5 otimes;=2297 otimesas;=2a36 ouml=f6 ouml;=f6 ovbar;=233d par;=2225 para=b6 " +
  "para;=b6 parallel;=2225 parsim;=2af3 parsl;=2afd part;=2202 pcy;=43f percnt;=25 period;=2e " +
  "permil;=2030 perp;=22a5 pertenk;=2031 pfr;=1d52d phi;=3c6 phiv;=3d5 phmmat;=2133 phone;=260e " +
  "pi;=3c0 pitchfork;=22d4 piv;=3d6 planck;=210f planckh;=210e plankv;=210f plus;=2b plusacir;=2a23 " +
  "plusb;=229e pluscir;=2a22 plusdo;=2214 plusdu;=2a25 pluse;=2a72 plusmn=b1 plusmn;=b1 plussim;=2a26 " +
  "plustwo;=2a27 pm;=b1 pointint;=2a15 popf;=1d561 pound=a3 pound;=a3 pr;=227a prE;=2ab3 prap;=2ab7 " +
  "prcue;=227c pre;=2aaf prec;=227a precapprox;=2ab7 preccurlyeq;=227c preceq;=2aaf precnapprox;=2ab9 " +
  "precneqq;=2ab5 precnsim;=22e8 precsim;=227e prime;=2032 primes;=2119 prnE;=2ab5 prnap;=2ab9 " +
  "prnsim;=22e8 prod;=220f profalar;=232e profline;=2312 profsurf;=2313 prop;=221d propto;=221d " +
  "prsim;=227e prurel;=22b0 pscr;=1d4c5 psi;=3c8 puncsp;=2008 qfr;=1d52e qint;=2a0c qopf;=1d562 " +
  "qprime;=2057 qscr;=1d4c6 quaternions;=210d quatint;=2a16 quest;=3f questeq;=225f quot=22 quot;=22 " +
  "rAarr;=21db rArr;=21d2 rAtail;=291c rBarr;=290f rHar;=2964 race;=223d.331 racute;=155 radic;=221a " +
  "raemptyv;=29b3 rang;=27e9 rangd;=2992 range;=29a5 rangle;=27e9 raquo=bb raquo;=bb rarr;=2192 " +
  "rarrap;=2975 rarrb;=21e5 rarrbfs;=2920 rarrc;=2933 rarrfs;=291e rarrhk;=21aa rarrlp;=21ac " +
  "rarrpl;=2945 rarrsim;=2974 rarrtl;=21a3 rarrw;=219d ratail;=291a ratio;=2236 rationals;=211a " +
  "rbarr;=290d rbbrk;=2773 rbrace;=7d rbrack;=5d rbrke;=298c rbrksld;=298e rbrkslu;=2990 rcaron;=159 " +
  "rcedil;=157 rceil;=2309 rcub;=7d rcy;=440 rdca;=2937 rdldhar;=2969 rdquo;=201d rdquor;=201d " +
  "rdsh;=21b3 real;=211c realine;=211b realpart;=211c reals;=211d rect;=25ad reg=ae reg;=ae " +
  "rfisht;=297d rfloor;=230b rfr;=1d52f rhard;=21c1 rharu;=21c0 rharul;=296c rho;=3c1 rhov;=3f1 " +
  "rightarrow;=2192 rightarrowtail;=21a3 rightharpoondown;=21c1 rightharpoonup;=21c0 " +
  "rightleftarrows;=21c4 rightleftharpoons;=21cc rightrightarrows;=21c9 rightsquigarrow;=219d " +
  "rightthreetimes;=22cc ring;=2da risingdotseq;=2253 rlarr;=21c4 rlhar;=21cc rlm;=200f rmoust;=23b1 " +
  "rmoustache;=23b1 rnmid;=2aee roang;=27ed roarr;=21fe robrk;=27e7 ropar;=2986 ropf;=1d563 " +
  "roplus;=2a2e rotimes;=2a35 rpar;=29 rpargt;=2994 rppolint;=2a12 rrarr;=21c9 rsaquo;=203a " +
  "rscr;=1d4c7 rsh;=21b1 rsqb;=5d rsquo;=2019 rsquor;=2019 rthree;=22cc rtimes;=22ca rtri;=25b9 " +
  "rtrie;=22b5 rtrif;=25b8 rtriltri;=29ce ruluhar;=2968 rx;=211e sacute;=15b sbquo;=201a sc;=227b " +
  "scE;=2ab4 scap;=2ab8 scaron;=161 sccue;=227d sce;=2ab0 scedil;=15f scirc;=15d scnE;=2ab6 " +
  "scnap;=2aba scnsim;=22e9 scpolint;=2a13 scsim;=227f scy;=441 sdot;=22c5 sdotb;=22a1 sdote;=2a66 " +
  "seArr;=21d8 searhk;=2925 searr;=2198 searrow;=2198 sect=a7 sect;=a7 semi;=3b seswar;=2929 " +
  "setminus;=2216 setmn;=2216 sext;=2736 sfr;=1d530 sfrown;=2322 sharp;=266f shchcy;=449 shcy;=448 " +
  "shortmid;=2223 shortparallel;=2225 shy=ad shy;=ad sigma;=3c3 sigmaf;=3c2 sigmav;=3c2 sim;=223c " +
  "simdot;=2a6a sime;=2243 simeq;=2243 simg;=2a9e simgE;=2aa0 siml;=2a9d simlE;=2a9f simne;=2246 " +
  "simplus;=2a24 simrarr;=2972 slarr;=2190 smallsetminus;=2216 smashp;=2a33 smeparsl;=29e4 smid;=2223 " +
  "smile;=2323 smt;=2aaa smte;=2aac smtes;=2aac.fe00 softcy;=44c sol;=2f solb;=29c4 solbar;=233f " +
  "sopf;=1d564 spades;=2660 spadesuit;=2660 spar;=2225 sqcap;=2293 sqcaps;=2293.fe00 sqcup;=2294 " +
  "sqcups;=2294.fe00 sqsub;=228f sqsube;=2291 sqsubset;=228f sqsubseteq;=2291 sqsup;=2290 sqsupe;=2292 " +
  "sqsupset;=2290 sqsupseteq;=2292 squ;=25a1 square;=25a1 squarf;=25aa squf;=25aa srarr;=2192 " +
  "sscr;=1d4c8 ssetmn;=2216 ssmile;=2323 sstarf;=22c6 star;=2606 starf;=2605 straightepsilon;=3f5 " +
  "straightphi;=3d5 strns;=af sub;=2282 subE;=2ac5 subdot;=2abd sube;=2286 subedot;=2ac3 submult;=2ac1 " +
  "subnE;=2acb subne;=228a subplus;=2abf subrarr;=2979 subset;=2282 subseteq;=2286 subseteqq;=2ac5 " +
  "subsetneq;=228a subsetneqq;=2acb subsim;=2ac7 subsub;=2ad5 subsup;=2ad3 succ;=227b succapprox;=2ab8 " +
  "succcurlyeq;=227d succeq;=2ab0 succnapprox;=2aba succneqq;=2ab6 succnsim;=22e9 succsim;=227f " +
  "sum;=2211 sung;=266a sup1=b9 sup1;=b9 sup2=b2 sup2;=b2 sup3=b3 sup3;=b3 sup;=2283 supE;=2ac6 " +
  "supdot;=2abe supdsub;=2ad8 supe;=2287 supedot;=2ac4 suphsol;=27c9 suphsub;=2ad7 suplarr;=297b " +
  "supmult;=2ac2 supnE;=2acc supne;=228b supplus;=2ac0 supset;=2283 supseteq;=2287 supseteqq;=2ac6 " +
  "supsetneq;=228b supsetneqq;=2acc supsim;=2ac8 supsub;=2ad4 supsup;=2ad6 swArr;=21d9 swarhk;=2926 " +
  "swarr;=2199 swarrow;=2199 swnwar;=292a szlig=df szlig;=df target;=2316 tau;=3c4 tbrk;=23b4 " +
  "tcaron;=165 tcedil;=163 tcy;=442 tdot;=20db telrec;=2315 tfr;=1d531 there4;=2234 therefore;=2234 " +
  "theta;=3b8 thetasym;=3d1 thetav;=3d1 thickapprox;=2248 thicksim;=223c thinsp;=2009 thkap;=2248 " +
  "thksim;=223c thorn=fe thorn;=fe tilde;=2dc times=d7 times;=d7 timesb;=22a0 timesbar;=2a31 " +
  "timesd;=2a30 tint;=222d toea;=2928 top;=22a4 topbot;=2336 topcir;=2af1 topf;=1d565 topfork;=2ada " +
  "tosa;=2929 tprime;=2034 trade;=2122 triangle;=25b5 triangledown;=25bf triangleleft;=25c3 " +
  "trianglelefteq;=22b4 triangleq;=225c triangleright;=25b9 trianglerighteq;=22b5 tridot;=25ec " +
  "trie;=225c triminus;=2a3a triplus;=2a39 trisb;=29cd tritime;=2a3b trpezium;=23e2 tscr;=1d4c9 " +
  "tscy;=446 tshcy;=45b tstrok;=167 twixt;=226c twoheadleftarrow;=219e twoheadrightarrow;=21a0 " +
  "uArr;=21d1 uHar;=2963 uacute=fa uacute;=fa uarr;=2191 ubrcy;=45e ubreve;=16d ucirc=fb ucirc;=fb " +
  "ucy;=443 udarr;=21c5 udblac;=171 udhar;=296e ufisht;=297e ufr;=1d532 ugrave=f9 ugrave;=f9 " +
  "uharl;=21bf uharr;=21be uhblk;=2580 ulcorn;=231c ulcorner;=231c ulcrop;=230f ultri;=25f8 umacr;=16b " +
  "uml=a8 uml;=a8 uogon;=173 uopf;=1d566 uparrow;=2191 updownarrow;=2195 upharpoonleft;=21bf " +
  "upharpoonright;=21be uplus;=228e upsi;=3c5 upsih;=3d2 upsilon;=3c5 upuparrows;=21c8 urcorn;=231d " +
  "urcorner;=231d urcrop;=230e uring;=16f urtri;=25f9 uscr;=1d4ca utdot;=22f0 utilde;=169 utri;=25b5 " +
  "utrif;=25b4 uuarr;=21c8 uuml=fc uuml;=fc uwangle;=29a7 vArr;=21d5 vBar;=2ae8 vBarv;=2ae9 " +
  "vDash;=22a8 vangrt;=299c varepsilon;=3f5 varkappa;=3f0 varnothing;=2205 varphi;=3d5 varpi;=3d6 " +
  "varpropto;=221d varr;=2195 varrho;=3f1 varsigma;=3c2 varsubsetneq;=228a.fe00 " +
  "varsubsetneqq;=2acb.fe00 varsupsetneq;=228b.fe00 varsupsetneqq;=2acc.fe00 vartheta;=3d1 " +
  "vartriangleleft;=22b2 vartriangleright;=22b3 vcy;=432 vdash;=22a2 vee;=2228 veebar;=22bb " +
  "veeeq;=225a vellip;=22ee verbar;=7c vert;=7c vfr;=1d533 vltri;=22b2 vnsub;=2282.20d2 " +
  "vnsup;=2283.20d2 vopf;=1d567 vprop;=221d vrtri;=22b3 vscr;=1d4cb vsubnE;=2acb.fe00 " +
  "vsubne;=228a.fe00 vsupnE;=2acc.fe00 vsupne;=228b.fe00 vzigzag;=299a wcirc;=175 wedbar;=2a5f " +
  "wedge;=2227 wedgeq;=2259 weierp;=2118 wfr;=1d534 wopf;=1d568 wp;=2118 wr;=2240 wreath;=2240 " +
  "wscr;=1d4cc xcap;=22c2 xcirc;=25ef xcup;=22c3 xdtri;=25bd xfr;=1d535 xhArr;=27fa xharr;=27f7 " +
  "xi;=3be xlArr;=27f8 xlarr;=27f5 xmap;=27fc xnis;=22fb xodot;=2a00 xopf;=1d569 xoplus;=2a01 " +
  "xotime;=2a02 xrArr;=27f9 xrarr;=27f6 xscr;=1d4cd xsqcup;=2a06 xuplus;=2a04 xutri;=25b3 xvee;=22c1 " +
  "xwedge;=22c0 yacute=fd yacute;=fd yacy;=44f ycirc;=177 ycy;=44b yen=a5 yen;=a5 yfr;=1d536 yicy;=457 " +
  "yopf;=1d56a yscr;=1d4ce yucy;=44e yuml=ff yuml;=ff zacute;=17a zcaron;=17e zcy;=437 zdot;=17c " +
  "zeetrf;=2128 zeta;=3b6 zfr;=1d537 zhcy;=436 zigrarr;=21dd zopf;=1d56b zscr;=1d4cf zwj;=200d " +
  "zwnj;=200c "

VTT_ENT = vtt_entity_table()
