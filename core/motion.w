# Motion — motion graphics on top of Svg: easing curves, timing windows,
# colour mixing, partial strokes along polylines, curved arcs with arrowheads,
# number formatting, and narration timelines (script segments plus clip
# durations give scene starts, sentence cues and SRT captions).
#
#   e = Ease.out_cubic(Motion.ramp(t, ~1.0, ~0.8))   # 0 → 1 between t = 1.0 s and 1.8 s
#   a = Motion.window(t, ~2.0, ~6.0)                 # fade in at 2 s, fade out by 6 s
#   c = Paint.mix("#4fd1ff", "#ffc24b", e)           # a colour part of the way along
#   s.polyline(Motion.partial(route, e), {stroke: c, width: 4, opacity: a})
#
#   n = Narration.load("video", ~0.6)                # script.txt + audio/durations.csv
#   i = n.scene_at(t)                                # which narration segment is playing
#   n.local(i, t)  n.cue(i, 2)  n.total  n.write_srt("video/captions.srt")
#
# Times are seconds (Float). Every easing function clamps its input to [0, 1],
# so `Ease.out_cubic(Motion.ramp(...))` is safe before and after the ramp.

+ Ease
  -> .linear(t)
    Motion.clamp01(t)

  # smoothstep: zero slope at both ends
  -> .smooth(t)
    x = Motion.clamp01(t)
    x * x * (~3.0 - ~2.0 * x)

  # smootherstep: zero slope and curvature at both ends
  -> .smoother(t)
    x = Motion.clamp01(t)
    x * x * x * (x * (x * ~6.0 - ~15.0) + ~10.0)

  -> .in_quad(t)
    x = Motion.clamp01(t)
    x * x

  -> .out_quad(t)
    x = Motion.clamp01(t)
    ~1.0 - (~1.0 - x) * (~1.0 - x)

  -> .in_out_quad(t)
    x = Motion.clamp01(t)
    if x < ~0.5
      return ~2.0 * x * x
    y = ~2.0 - ~2.0 * x
    ~1.0 - y * y / ~2.0

  -> .in_cubic(t)
    x = Motion.clamp01(t)
    x * x * x

  -> .out_cubic(t)
    x = ~1.0 - Motion.clamp01(t)
    ~1.0 - x * x * x

  -> .in_out_cubic(t)
    x = Motion.clamp01(t)
    if x < ~0.5
      return ~4.0 * x * x * x
    y = ~2.0 - ~2.0 * x
    ~1.0 - y * y * y / ~2.0

  -> .out_quart(t)
    x = ~1.0 - Motion.clamp01(t)
    ~1.0 - x * x * x * x

  -> .out_expo(t)
    x = Motion.clamp01(t)
    if x >= ~1.0
      return ~1.0
    ~1.0 - Math.exp(~-6.931471805599453 * x)

  -> .in_out_sine(t)
    x = Motion.clamp01(t)
    ~0.5 - ~0.5 * Math.cos(~3.141592653589793 * x)

  # overshoots by about 10% before settling (Penner's back, s = 1.70158)
  -> .out_back(t)
    x = Motion.clamp01(t) - ~1.0
    s = ~1.70158
    ~1.0 + x * x * ((s + ~1.0) * x + s)

+ Motion
  -> .clamp01(x)
    if x < ~0.0
      return ~0.0
    if x > ~1.0
      return ~1.0
    x + ~0.0

  -> .clamp(x, lo, hi)
    if x < lo
      return lo
    if x > hi
      return hi
    x

  -> .lerp(a, b, t)
    a + (b - a) * t

  # 0 before a, rising linearly to 1 at a + w
  -> .ramp(t, a, w)
    if w <= ~0.0
      if t >= a
        return ~1.0
      return ~0.0
    Motion.clamp01((t - a) / w)

  # visible from a (fading in over fin) until b (faded out by b, over fout)
  -> .window(t, a, b, fin = ~0.5, fout = ~0.5)
    Motion.ramp(t, a, fin) * (~1.0 - Motion.ramp(t, b - fout, fout))

  # the i-th of a staggered sequence: starts at a + i * step, lasts w
  -> .stagger(t, a, i, step, w)
    Motion.ramp(t, a + i * step, w)

  # a 0 → 1 → 0 pulse with the given period
  -> .pulse(t, period)
    ~0.5 - ~0.5 * Math.cos(~6.283185307179586 * t / period)

  -> .mix_point(p, q, t)
    [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]

  -> .dist(p, q)
    dx = q[0] - p[0]
    dy = q[1] - p[1]
    Math.sqrt(dx * dx + dy * dy)

  # total length of a polyline [[x, y], ...]
  -> .length(pts)
    total = ~0.0
    i = 1
    while i < pts.size
      total = total + Motion.dist(pts[i - 1], pts[i])
      i += 1
    total

  # the point a fraction f of the way along a polyline (by arc length)
  -> .point_at(pts, f)
    if pts.size == 0
      return [~0.0, ~0.0]
    if pts.size == 1 || f <= ~0.0
      return [pts[0][0] + ~0.0, pts[0][1] + ~0.0]
    goal = Motion.length(pts) * Motion.clamp01(f)
    acc = ~0.0
    i = 1
    while i < pts.size
      seg = Motion.dist(pts[i - 1], pts[i])
      if acc + seg >= goal && seg > ~0.0
        return Motion.mix_point(pts[i - 1], pts[i], (goal - acc) / seg)
      acc = acc + seg
      i += 1
    last = pts[pts.size - 1]
    [last[0] + ~0.0, last[1] + ~0.0]

  # unit direction of travel a fraction f of the way along a polyline
  -> .heading_at(pts, f)
    if pts.size < 2
      return [~1.0, ~0.0]
    goal = Motion.length(pts) * Motion.clamp01(f)
    acc = ~0.0
    i = 1
    while i < pts.size
      seg = Motion.dist(pts[i - 1], pts[i])
      if (acc + seg >= goal || i == pts.size - 1) && seg > ~0.0
        return [(pts[i][0] - pts[i - 1][0]) / seg, (pts[i][1] - pts[i - 1][1]) / seg]
      acc = acc + seg
      i += 1
    [~1.0, ~0.0]

  # the drawn-so-far prefix of a polyline: its first fraction f by arc length
  -> .partial(pts, f)
    out = []
    if pts.size == 0
      return out
    out.push(pts[0])
    if f <= ~0.0
      return out
    goal = Motion.length(pts) * Motion.clamp01(f)
    acc = ~0.0
    i = 1
    while i < pts.size
      seg = Motion.dist(pts[i - 1], pts[i])
      if acc + seg >= goal
        if seg > ~0.0
          out.push(Motion.mix_point(pts[i - 1], pts[i], (goal - acc) / seg))
        return out
      out.push(pts[i])
      acc = acc + seg
      i += 1
    out

  # the piece of a polyline between fractions f0 < f1 (a moving dash)
  -> .slice(pts, f0, f1)
    a = Motion.clamp01(f0)
    b = Motion.clamp01(f1)
    out = []
    if pts.size < 2 || b <= a
      return out
    total = Motion.length(pts)
    g0 = total * a
    g1 = total * b
    out.push(Motion.point_at(pts, a))
    acc = ~0.0
    i = 1
    while i < pts.size
      seg = Motion.dist(pts[i - 1], pts[i])
      acc = acc + seg
      if acc > g0 && acc < g1
        out.push(pts[i])
      i += 1
    out.push(Motion.point_at(pts, b))
    out

  # move the endpoints of p → q inward by r0 and r1 (e.g. node radii)
  -> .shorten(p, q, r0, r1)
    d = Motion.dist(p, q)
    if d <= r0 + r1
      m = Motion.mix_point(p, q, ~0.5)
      return [m, m]
    [Motion.mix_point(p, q, r0 / d), Motion.mix_point(p, q, ~1.0 - r1 / d)]

  # a quadratic Bézier from p to q bowed sideways by bend × |pq|, sampled at n + 1 points
  -> .curve(p, q, bend, n = 24)
    d = Motion.dist(p, q)
    mx = (p[0] + q[0]) / ~2.0
    my = (p[1] + q[1]) / ~2.0
    cx = mx
    cy = my
    if d > ~0.0
      cx = mx - (q[1] - p[1]) / d * bend * d
      cy = my + (q[0] - p[0]) / d * bend * d
    out = []
    k = 0
    while k <= n
      u = k * ~1.0 / n
      v = ~1.0 - u
      out.push([v * v * p[0] + ~2.0 * v * u * cx + u * u * q[0], v * v * p[1] + ~2.0 * v * u * cy + u * u * q[1]])
      k += 1
    out

  # arrowhead polygon whose tip is at `tip`, pointing along unit direction dir
  -> .arrow(tip, dir, size, spread = ~0.55)
    bx = tip[0] - dir[0] * size
    by = tip[1] - dir[1] * size
    nx = ~0.0 - dir[1] * size * spread
    ny = dir[0] * size * spread
    [[tip[0], tip[1]], [bx + nx, by + ny], [bx - nx, by - ny]]

  # points of a circle (for washes and halos drawn as polygons)
  -> .circle_points(cx, cy, r, n = 48)
    out = []
    k = 0
    while k < n
      a = k * ~6.283185307179586 / n
      out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)])
      k += 1
    out

  # integer with thousands separators: 1234567 → "1,234,567"
  -> .commas(n)
    s = n.to_s
    neg = ""
    if s.size > 0 && s[0] == "-"
      neg = "-"
      s = s.slice(1, s.size - 1)
    out = ""
    i = 0
    while i < s.size
      if i > 0 && (s.size - i) % 3 == 0
        out = out + ","
      out = out + s[i]
      i += 1
    neg + out

  # a Float rounded to `places` decimals, printed without float noise
  -> .fixed(x, places)
    scale = 1
    k = 0
    while k < places
      scale = scale * 10
      k += 1
    v = x + ~0.0
    neg = v < ~0.0
    if neg
      v = ~0.0 - v
    n = (v * scale + ~0.5).floor.to_i
    whole = (n / scale).to_s
    frac = (n % scale).to_s
    while frac.size < places
      frac = "0" + frac
    s = whole
    if places > 0
      s = whole + "." + frac
    if neg && n != 0
      s = "-" + s
    s

  -> .pad(n, width)
    s = n.to_s
    while s.size < width
      s = "0" + s
    s

+ Paint
  -> .hex2(v)
    digits = "0123456789abcdef"
    x = v
    if x < 0
      x = 0
    if x > 255
      x = 255
    digits[x / 16] + digits[x % 16]

  # channels may be Int or Float; Floats round to the nearest level
  -> .hex(r, g, b)
    "#" + Paint.hex2((r + ~0.0).round.to_i) + Paint.hex2((g + ~0.0).round.to_i) + Paint.hex2((b + ~0.0).round.to_i)

  -> .nibble(ch)
    "0123456789abcdef".index(ch.downcase)

  # "#rrggbb" (or "#rgb") → [r, g, b]
  -> .rgb(color)
    s = color
    if s[0] == "#"
      s = s.slice(1, s.size - 1)
    if s.size == 3
      return [Paint.nibble(s[0]) * 17, Paint.nibble(s[1]) * 17, Paint.nibble(s[2]) * 17]
    [Paint.nibble(s[0]) * 16 + Paint.nibble(s[1]), Paint.nibble(s[2]) * 16 + Paint.nibble(s[3]), Paint.nibble(s[4]) * 16 + Paint.nibble(s[5])]

  # the colour a fraction f of the way from c0 to c1
  -> .mix(c0, c1, f)
    a = Paint.rgb(c0)
    b = Paint.rgb(c1)
    t = Motion.clamp01(f)
    Paint.hex(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)

  # a colour sampled from a ramp of stops spaced evenly over [0, 1]
  -> .ramp(stops, f)
    if stops.size == 1
      return stops[0]
    t = Motion.clamp01(f) * (stops.size - 1)
    i = t.floor.to_i
    if i >= stops.size - 1
      return stops[stops.size - 1]
    Paint.mix(stops[i], stops[i + 1], t - i)

+ Narration
  ro :ids, :texts, :durations, :starts, :lengths, :total, :pause

  # `dir` holds script.txt (segments headed "## id") and audio/durations.csv
  # ("segment,seconds" then one row per clip). Each scene lasts its clip plus `pause`.
  -> .load(dir, pause = ~0.6)
    n = Narration.new(pause)
    n.read_script(File.read(dir + "/script.txt"))
    n.read_durations(File.read(dir + "/audio/durations.csv"))
    n

  -> new(@pause)
    @ids = []
    @texts = []
    @durations = []
    @starts = []
    @lengths = []
    @total = ~0.0

  -> read_script(src)
    lines = src.split("\n")
    cur = ""
    i = 0
    while i < lines.size
      l = lines[i]
      if l.size > 3 && l[0] == "#" && l[1] == "#" && l[2] == " "
        if @ids.size > 0
          @texts.push(cur.strip)
        @ids.push(l.slice(3, l.size - 3).strip)
        cur = ""
      elsif @ids.size > 0
        cur = cur + " " + l
      i += 1
    if @ids.size > 0
      @texts.push(cur.strip)
    self

  -> read_durations(src)
    lines = src.split("\n")
    t = ~0.0
    i = 1
    while i < lines.size
      if lines[i].size > 0
        d = lines[i].split(",")[1].to_f
        @durations.push(d)
        @starts.push(t)
        @lengths.push(d + @pause)
        t = t + d + @pause
      i += 1
    @total = t
    self

  -> count
    @starts.size

  -> start(i)
    @starts[i]

  -> length(i)
    @lengths[i]

  -> duration(i)
    @durations[i]

  # index of the segment playing at absolute time t
  -> scene_at(t)
    i = 0
    while i + 1 < @starts.size && t >= @starts[i + 1]
      i += 1
    i

  -> local(i, t)
    t - @starts[i]

  -> index_of(id)
    i = 0
    while i < @ids.size
      if @ids[i] == id
        return i
      i += 1
    -1

  # the sentences of segment i
  -> sentences(i)
    Narration.split_sentences(@texts[i])

  # local time (seconds into segment i) at which its j-th sentence starts,
  # estimated by that sentence's share of the clip's characters
  -> cue(i, j)
    sent = sentences(i)
    if j >= sent.size
      return @durations[i]
    total = @texts[i].size
    acc = ~0.0
    k = 0
    while k < j
      acc = acc + sent[k].size + 1
      k += 1
    @durations[i] * acc / total

  # local time at which the first occurrence of `word` is spoken in segment i
  -> word_cue(i, word)
    text = @texts[i]
    at = text.index(word)
    if at == nil
      return ~0.0
    @durations[i] * at / text.size

  -> .split_sentences(text)
    out = []
    cur = ""
    cs = text.chars
    i = 0
    n = cs.size
    while i < n
      ch = cs[i]
      cur = cur + ch
      if (ch == "." || ch == "?" || ch == "!") && i + 1 < n && cs[i + 1] == " "
        out.push(cur.strip)
        cur = ""
      i += 1
    if cur.strip.size > 0
      out.push(cur.strip)
    out

  -> .srt_time(t)
    ms = (t * ~1000.0).round.to_i
    h = ms / 3600000
    m = (ms / 60000) % 60
    s = (ms / 1000) % 60
    r = ms % 1000
    Motion.pad(h, 2) + ":" + Motion.pad(m, 2) + ":" + Motion.pad(s, 2) + "," + Motion.pad(r, 3)

  # a sentence longer than `limit` characters is split at the clause break
  # (", " ": " "; " " — ") nearest its middle, repeatedly
  -> .caption_pieces(sents, limit = 84)
    out = []
    todo = []
    i = sents.size - 1
    while i >= 0
      todo.push(sents[i])
      i -= 1
    while todo.size > 0
      s = todo.pop
      cs = s.chars
      if cs.size <= limit
        out.push(s)
      else
        mid = cs.size / 2
        best = -1
        k = 1
        while k + 1 < cs.size
          if (cs[k] == "," || cs[k] == ":" || cs[k] == ";") && cs[k + 1] == " "
            if best < 0 || (k - mid).abs < (best - mid).abs
              best = k
          k += 1
        if best < 0
          out.push(s)
        else
          todo.push(cs.slice(best + 2, cs.size - best - 2).join(""))
          todo.push(cs.slice(0, best + 1).join(""))
    out

  # break a caption longer than `limit` characters into two lines at the space nearest its middle
  -> .wrap2(s, limit = 60)
    if s.size <= limit
      return s
    cs = s.chars
    mid = cs.size / 2
    best = -1
    i = 0
    while i < cs.size
      if cs[i] == " "
        if best < 0 || (i - mid).abs < (best - mid).abs
          best = i
      i += 1
    if best < 0
      return s
    cs.slice(0, best).join("") + "\n" + cs.slice(best + 1, cs.size - best - 1).join("")

  # SubRip captions, one per sentence piece, timed by character share within each clip
  -> srt
    out = []
    n = 1
    i = 0
    while i < @ids.size
      pieces = Narration.caption_pieces(sentences(i))
      total = @texts[i].size
      acc = ~0.0
      j = 0
      while j < pieces.size
        s = pieces[j]
        a = @starts[i] + @durations[i] * acc / total
        acc = acc + s.size + 1
        b = @starts[i] + @durations[i] * acc / total
        out.push(n.to_s + "\n" + Narration.srt_time(a) + " --> " + Narration.srt_time(b) + "\n" + Narration.wrap2(s) + "\n")
        n += 1
        j += 1
      i += 1
    out.join("\n")

  -> write_srt(path)
    File.write(path, srt)
    path
