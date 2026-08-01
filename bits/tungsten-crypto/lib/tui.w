# Live mining display.
#
# The performance rule: NOTHING here runs inside the hash loop. Workers never
# print, never lock, and never touch a shared counter per candidate. The only
# per-candidate cost in the whole design is a single register compare in
# `sha256_hw.c` that maintains the best-so-far value — measured at ~1% against
# the pre-change baseline, which is inside this machine's run-to-run spread.
#
# How the update happens instead: the search is cut into chunks of a few tens
# of millions of nonces. A chunk is a normal full-speed parallel scan; when it
# returns, the main thread — which was only joining, never hashing — redraws.
# Chunk size sets the frame rate, so a slower machine draws less often rather
# than paying more per hash.
#
# Rendering is done with ANSI cursor movement rather than clearing the screen,
# so the display updates in place without flicker and without scrolling the
# terminal history away.

use bitcoin

# Move the cursor up n lines and clear from there down, so the next draw
# overwrites the previous frame exactly.
-> tui_rewind(n)
  if n > 0
    print("\e[" + n.to_s + "A\e[J")
  0

-> tui_hide_cursor
  print("\e[?25l")

-> tui_show_cursor
  print("\e[?25h")

# Leading zero BITS of a 32-bit word. The miner tracks the top 32 bits of the
# hash value, so this is the number of leading zero bits of the whole 256-bit
# hash, saturating at 32 (which already exceeds difficulty 1).
-> tui_clz32(v) (i64) i64
  if v == 0
    return 32
  n = 0 ## i64
  x = v & 0xFFFFFFFF ## i64
  while (x & 0x80000000) == 0
    x = (x << 1) & 0xFFFFFFFF
    n += 1
  n

# A hash rate in human units. Integer-only: floats print with six digits and
# no round-trip, so they are avoided for anything displayed.
-> tui_rate(hs)
  if hs >= 1000000000
    return (hs / 1000000000).to_s + "." + tui_pad2((hs % 1000000000) / 10000000) + " GH/s"
  if hs >= 1000000
    return (hs / 1000000).to_s + "." + tui_pad2((hs % 1000000) / 10000) + " MH/s"
  if hs >= 1000
    return (hs / 1000).to_s + "." + tui_pad2((hs % 1000) / 10) + " KH/s"
  hs.to_s + " H/s"

-> tui_pad2(n)
  if n < 10
    return "0" + n.to_s
  n.to_s

-> tui_commas(n)
  s = n.to_s
  out = ""
  i = 0
  while i < s.size
    if i > 0 && (s.size - i) % 3 == 0
      out = out + ","
    out = out + s.slice(i, 1)
    i += 1
  out

-> tui_dur(ms)
  sec = ms / 1000
  if sec < 60
    return sec.to_s + "s"
  if sec < 3600
    return (sec / 60).to_s + "m " + (sec % 60).to_s + "s"
  (sec / 3600).to_s + "h " + ((sec % 3600) / 60).to_s + "m"

# A proportional bar. `width` cells, filled by num/den.
-> tui_bar(num, den, width)
  if den <= 0
    return ""
  fill = num * width / den
  if fill > width
    fill = width
  out = ""
  i = 0
  while i < width
    if i < fill
      out = out + "█"
    else
      out = out + "░"
    i += 1
  out

# How many leading zero bits the target itself demands — the finish line.
-> tui_target_zeros(target)
  n = 0 ## i64
  i = 0 ## i64
  while i < 8
    w = target[i] & 0xFFFFFFFF
    if w != 0
      return n + tui_clz32(w)
    n += 32
    i += 1
  256

# The full 256-bit target as 64 hex digits, display (byte-reversed) order —
# the same orientation a block hash is printed in, so the two lines can be
# compared digit by digit.
-> tui_target_hex(target)
  digits = "0123456789abcdef"
  out = ""
  i = 0 ## i64
  while i < 8
    w = target[i] & 0xFFFFFFFF
    sh = 28 ## i64
    while sh >= 0
      out = out + digits.slice((w >> sh) & 0xF, 1)
      sh -= 4
    i += 1
  out

# Expected hashes for one solution: 2**(leading zero bits demanded). More
# useful on a display than a "difficulty" number, because it converts
# directly into an ETA at the observed rate.
-> tui_expected_hashes(need)
  if need >= 63
    return "2^" + need.to_s
  v = 1 ## i64
  i = 0 ## i64
  while i < need
    v = v * 2
    i += 1
  tui_commas(v)

# Time to find one block at the observed rate, as a human string.
-> tui_eta(need, rate)
  if rate <= 0
    return "-"
  # Above 2**62 the hash count no longer fits an i64, so divide first: work
  # out the seconds as 2**(need-k) * (2**k / rate) with k chosen to keep both
  # factors in range, then fall back to a log-scale statement.
  if need >= 63
    yrs_log = need - 63
    base = 9223372036854775807 / rate / 31536000
    if yrs_log < 40
      y = base ## i64
      i = 0 ## i64
      while i < yrs_log && y < 1000000000000000000
        y = y * 2
        i += 1
      if i == yrs_log
        if y > 1000000
          return tui_commas(y / 1000000) + " million years"
        return tui_commas(y) + " years"
    return "~2^" + need.to_s + " hashes — effectively never"
  v = 1 ## i64
  i = 0 ## i64
  while i < need
    v = v * 2
    i += 1
  sec = v / rate
  if sec < 60
    return sec.to_s + "s"
  if sec < 3600
    return (sec / 60).to_s + "m"
  if sec < 86400
    return (sec / 3600).to_s + "h"
  if sec < 31536000
    return (sec / 86400).to_s + " days"
  yrs = sec / 31536000
  if yrs > 1000000
    return (yrs / 1000000).to_s + " million years"
  tui_commas(yrs) + " years"

# Render one frame. Returns the number of lines drawn so the caller can
# rewind exactly that many next time.
# Inner width of the frame, in display cells. A full block hash is 64 hex
# digits and the label column is 9, so 74 is the minimum that shows a hash
# and a target on one line each without truncation.
TUI_INNER = 74

-> tui_repeat(ch, n)
  out = ""
  i = 0 ## i64
  while i < n
    out = out + ch
    i += 1
  out

# "├─ label ───...───┤". Widths are generated, never hand-counted, so the
# frame cannot drift when a label changes.
-> tui_rule(left, right, label)
  head = "─ " + label + " "
  cells = 2 + label.size + 1
  left + head + tui_repeat("─", TUI_INNER - cells) + right

-> tui_plain_rule(left, right)
  left + tui_repeat("─", TUI_INNER) + right

-> tui_row(label, value)
  "  │ " + tui_field(label, 9) + tui_field(value, TUI_INNER - 10) + "│"

# Render one frame. The lines are collected into a list and then printed, so
# the returned count is derived from what was actually emitted rather than
# hand-maintained. A hand-counted constant drifted the display down one line
# per refresh the first time around.
-> tui_frame(st)
  best = st[:best] ## i64
  zeros = tui_clz32(best)
  need = st[:need]
  elapsed = st[:elapsed]
  rate = 0
  if elapsed > 0
    rate = st[:scanned] * 1000 / elapsed

  lines = []
  lines.push("  " + tui_rule("┌", "┐", "tungsten-miner"))
  lines.push(tui_row("payout", st[:payout]))
  lines.push("  " + tui_rule("├", "┤", "network"))
  lines.push(tui_row("chain", st[:chain]))
  lines.push(tui_row("tip", st[:tip]))
  lines.push(tui_row("height", st[:height].to_s + "     nBits 0x" + st[:bits_hex]))
  lines.push(tui_row("work", need.to_s + " zero bits   ~" + tui_expected_hashes(need) + " hashes/block"))
  # Label this precisely. It is the expected time to solve THE TARGET THIS
  # MINER IS CONFIGURED WITH, which in demo mode is a toy difficulty. Calling
  # it "solo ETA" implied real-network solo mining and was wrong by about
  # twelve orders of magnitude.
  lines.push(tui_row("ETA", tui_eta(need, rate) + "   (at nBits 0x" + st[:bits_hex] + ")"))
  lines.push(tui_row("mainnet", "would need ~2^78 hashes = " + tui_eta(78, rate) + " at this rate"))
  lines.push("  " + tui_rule("├", "┤", "mining"))
  lines.push(tui_row("rate", tui_rate(rate) + "   " + st[:engine]))
  lines.push(tui_row("hashes", tui_commas(st[:scanned])))
  lines.push(tui_row("elapsed", tui_dur(elapsed) + "   extranonce " + st[:extra].to_s))
  lines.push("  " + tui_rule("├", "┤", "best so far"))
  lines.push(tui_row("hash", tui_full_hex(st[:best_hash])))
  lines.push(tui_row("target", st[:target_hex]))
  # Say how much work REMAINS, not just the bit count. A bar at 31 of 40
  # bits looks 78% done and is actually 1/512th of the way, because each
  # additional zero bit doubles the expected work. Showing the multiplier
  # is the only honest framing.
  gap = need - zeros
  if gap <= 0
    lines.push(tui_row("", zeros.to_s + " of " + need.to_s + " zero bits — TARGET MET"))
  else
    lines.push(tui_row("", zeros.to_s + " of " + need.to_s + " zero bits   still " + tui_expected_hashes(gap) + "x more work"))
  # One cell per bit where that fits, so the bar reads as a bit count rather
  # than a percentage — it must not imply linear progress. Mainnet needs 78
  # bits, which is wider than the frame, so cap the cells and let the bar
  # scale; the exact numbers are on the line above it either way.
  bar_cells = need
  if bar_cells > TUI_INNER - 2
    bar_cells = TUI_INNER - 2
  lines.push("  │ " + tui_field_cells(tui_bar(zeros, need, bar_cells), bar_cells, TUI_INNER - 1) + "│")
  lines.push("  " + tui_plain_rule("└", "┘"))

  i = 0
  while i < lines.size
    << lines[i]
    i += 1
  lines.size

# A full 8-word digest in Bitcoin display order.
-> tui_full_hex(d)
  if d == nil
    return "(none yet)"
  digits = "0123456789abcdef"
  out = ""
  i = 7 ## i64
  while i >= 0
    w = d[i] & 0xFFFFFFFF
    b = 0 ## i64
    while b < 4
      byte = (w >> (b * 8)) & 0xFF
      out = out + digits.slice((byte >> 4) & 0xF, 1)
      out = out + digits.slice(byte & 0xF, 1)
      b += 1
    i -= 1
  out

# The best value rendered as the leading 8 hex digits of a block hash, with
# the rest elided — this is the shape a miner recognizes at a glance.
-> tui_best_hex(best)
  digits = "0123456789abcdef"
  out = ""
  sh = 28 ## i64
  while sh >= 0
    out = out + digits.slice((best >> sh) & 0xF, 1)
    sh -= 4
  out + "…"

# Pad content whose display width is KNOWN, rather than measured. String#size
# counts BYTES, and every box-drawing glyph here is 3 bytes, so measuring
# would truncate a 40-cell bar to 19 cells and break the frame. Callers that
# emit non-ASCII pass the cell count explicitly.
-> tui_field_cells(s, cells, width)
  out = s
  i = cells
  while i < width
    out = out + " "
    i += 1
  out

# Pad or truncate ASCII content, where bytes and cells coincide.
-> tui_field(s, width)
  t = s
  if t.size > width
    t = t.slice(0, width)
  out = t
  i = t.size
  while i < width
    out = out + " "
    i += 1
  out
