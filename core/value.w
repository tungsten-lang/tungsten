# Value — raw WValue bit-level inspection and scene rendering.
+ Value
  HEX_CHARS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
  PACKED_NAMES = ["color", "complex", "rational", "reserved", "date", "ipv4", "body", "location"]
  NUMERIC_NAMES = ["decimal", "currency", "reserved", "quantity"]

  -> to_i
    $value

  -> .hex_n(bits, n)
    b = bits ## i64
    cnt = n ## i64
    out = ""
    i = cnt - 1
    while i >= 0
      d = (b >> (i * 4)) & 0xF
      out = out + HEX_CHARS[d]
      i = i - 1
    out

  -> .bin_n(bits, n)
    b = bits ## i64
    cnt = n ## i64
    out = ""
    i = cnt - 1
    while i >= 0
      if ((b >> i) & 1) != 0
        out = out + "1"
      else
        out = out + "0"
      i = i - 1
    out

  -> .hex16(v)
    Value.hex_n(v$value, 16)

  -> .bin64(v)
    Value.bin_n(v$value, 64)

  -> .signext(v, nbits)
    val = v ## i64
    nb = nbits ## i64
    m = (1 ## i64) << (nb - 1)
    (val ^ m) - m

  -> .ljust(s, w)
    out = s
    while out.size() < w
      out = out + " "
    out

  -> .rstrip(s)
    n = s.size()
    while n > 0 && s.slice(n - 1, 1) == " "
      n = n - 1
    s.slice(0, n)

  -> .fld(label, br, raw, meaning)
    line = "  " + Value.ljust(label, 8)
    if br != "" || raw != ""
      line = line + " " + Value.ljust(br, 11) + " " + Value.ljust(raw, 8)
    if meaning != ""
      line = line + "  " + meaning
    Value.rstrip(line) + "\n"

  -> .hdr(label, value)
    "  " + Value.ljust(label, 8) + " " + value + "\n"

  -> .fields(vv)
    bits = vv$value ## i64
    tag = ((bits >> 48) & 0xFFFF) ## i64

    if bits >= 0 && bits <= 3
      nm = bits == 0 ? "nil" : (bits == 1 ? "false" : (bits == 2 ? "true" : "undef"))
      out = Value.fld("space", "bits 63..48", "0x" + Value.hex_n(tag, 4), "singleton / sentinel")
      out = out + Value.fld("value", "bits 3..0", "0x" + HEX_CHARS[bits & 0xF], nm)
      return out

    if tag >= 1 && (tag < 0xFFF1 || (tag == 0xFFF1 && (bits & 0xFFFFFFFFFFFF) == 0))
      bias = (1 ## i64) << 48
      ieee = (bits - bias) ## i64
      out = Value.fld("space", "bits 63..48", "0x" + Value.hex_n(tag, 4), "biased double")
      out = out + Value.fld("bias", "", "0x" + Value.hex_n(bias, 16), "subtract to recover IEEE-754 bits")
      out = out + Value.fld("ieee", "bits 63..0", "0x" + Value.hex_n(ieee, 16), "unbiased IEEE-754 payload")
      out = out + Value.fld("decoded", "", "", vv.to_s())
      out = out + Value.fld("note", "", "", "exact immediate encoding")
      return out

    if tag == 0xFFFB
      pl = (bits & 0x7FFFFFFFFFFF) ## i64
      sbit = ((bits >> 47) & 1) != 0 ? "1" : "0"
      out = Value.fld("tag", "bits 63..48", "0xFFFB", "bigint")
      out = out + Value.fld("pointer", "bits 46..0", "0x" + Value.hex_n(pl, 12), "WBigint*")
      out = out + Value.fld("sign bit", "bit 47", sbit, "reserved for tag-sign")
      return out

    if tag == 0xFFFA
      pl = (bits & 0xFFFFFFFFFFFF) ## i64
      out = Value.fld("tag", "bits 63..48", "0xFFFA", "48-bit signed integer")
      out = out + Value.fld("payload", "bits 47..0", "0x" + Value.hex_n(pl, 12), "int48 payload")
      out = out + Value.fld("decoded", "", "", Value.signext(pl, 48).to_s())
      out = out + Value.fld("note", "", "", "exact immediate encoding")
      return out

    if tag == 0xFFFE
      sub = ((bits >> 45) & 0x7) ## i64
      out = Value.fld("tag", "bits 63..48", "0xFFFE", "packed")
      out = out + Value.fld("subtype", "bits 47..45", sub.to_s(), PACKED_NAMES[sub])
      if sub == 0
        out = out + Value.fld("r", "bits 43..36", "0x" + Value.hex_n((bits >> 36) & 0xFF, 2), "")
        out = out + Value.fld("g", "bits 35..28", "0x" + Value.hex_n((bits >> 28) & 0xFF, 2), "")
        out = out + Value.fld("b", "bits 27..20", "0x" + Value.hex_n((bits >> 20) & 0xFF, 2), "")
        out = out + Value.fld("a", "bits 19..12", "0x" + Value.hex_n((bits >> 12) & 0xFF, 2), "")
        out = out + Value.fld("flags", "bits 11..0", "0x" + Value.hex_n(bits & 0xFFF, 3), "colorspace / flags")
      elsif sub == 2
        out = out + Value.fld("num", "bits 43..22", Value.signext((bits >> 22) & 0x3FFFFF, 22).to_s(), "numerator")
        out = out + Value.fld("den", "bits 21..0", (bits & 0x3FFFFF).to_s(), "denominator")
      elsif sub == 4
        yr = (((bits >> 33) & 0xFFF) - 1024) ## i64
        mo = ((bits >> 29) & 0xF) ## i64
        dy = ((bits >> 24) & 0x1F) ## i64
        hr = ((bits >> 19) & 0x1F) ## i64
        mn = ((bits >> 13) & 0x3F) ## i64
        sc = ((bits >> 7) & 0x3F) ## i64
        raw_tz = (bits & 0x7F) ## i64
        tz = (raw_tz == 63 ? 20 : ((raw_tz >= 64 ? raw_tz - 128 : raw_tz) * 15)) ## i64
        out = out + Value.fld("year", "bits 44..33", yr.to_s(), "civil year (stored as year+1024)")
        out = out + Value.fld("month", "bits 32..29", mo.to_s(), "")
        out = out + Value.fld("day", "bits 28..24", dy.to_s(), "")
        out = out + Value.fld("hour", "bits 23..19", hr.to_s(), "")
        out = out + Value.fld("minute", "bits 18..13", mn.to_s(), "")
        out = out + Value.fld("second", "bits 12..7", sc.to_s(), "")
        out = out + Value.fld("tz", "bits 6..0", tz.to_s(), "minutes east of UTC")
      elsif sub == 5
        addr = ((bits >> 12) & 0xFFFFFFFF) ## i64
        ipl = ((addr >> 24) & 0xFF).to_s() + "." + ((addr >> 16) & 0xFF).to_s() + "." + ((addr >> 8) & 0xFF).to_s() + "." + (addr & 0xFF).to_s()
        out = out + Value.fld("addr", "bits 43..12", "0x" + Value.hex_n(addr, 8), ipl)
        out = out + Value.fld("cidr", "bits 11..6", ((bits >> 6) & 0x3F).to_s(), "")
        out = out + Value.fld("flags", "bits 5..0", "0x" + Value.hex_n(bits & 0x3F, 2), "")
      out = out + Value.fld("note", "", "", "exact immediate encoding")
      return out

    if tag == 0xFFFD
      sub = ((bits >> 46) & 0x3) ## i64
      out = Value.fld("tag", "bits 63..48", "0xFFFD", "numeric")
      out = out + Value.fld("subtype", "bits 47..46", sub.to_s(), NUMERIC_NAMES[sub])
      if sub == 0
        out = out + Value.fld("sig", "bits 45..7", Value.signext((bits >> 7) & 0x7FFFFFFFFF, 39).to_s(), "39-bit significand")
        out = out + Value.fld("scale", "bits 6..0", Value.signext(bits & 0x7F, 7).to_s(), "decimal scale")
      out = out + Value.fld("note", "", "", "exact immediate encoding")
      return out

    if tag == 0xFFF9
      mode = ((bits >> 1) & 0x7) ## i64
      is_sym = (bits & 1) == 1
      out = Value.fld("tag", "bits 63..48", "0xFFF9", "string / symbol")
      out = out + Value.fld("kind", "bit 0", is_sym ? "1" : "0", is_sym ? "symbol" : "string")
      mode_label = mode == 6 ? "slab interned" : (mode == 7 ? "heap" : "inline SSO")
      out = out + Value.fld("mode", "bits 3..1", mode.to_s(), mode_label)
      if mode <= 5
        txt = vv.to_s()
        q = is_sym ? (":" + txt) : ("\"" + txt + "\"")
        out = out + Value.fld("decoded", "", "", q)
      elsif mode == 6
        out = out + Value.fld("slab", "bits 27..4", "0x" + Value.hex_n((bits >> 4) & 0xFFFFFF, 6), "slab index")
      else
        out = out + Value.fld("heap", "bits 47..4", "", "masked WString* / WSymbol*")
      out = out + Value.fld("note", "", "", "exact immediate encoding")
      return out

    if tag == 0
      ptr = (bits & -16) ## i64
      out = Value.fld("space", "bits 63..48", "0x0000", "heap object / singleton space")
      out = out + Value.fld("pointer", "bits 63..4", "0x" + Value.hex_n(ptr, 16), "16-byte aligned pointer payload")
      out = out + Value.fld("subtag", "bits 3..0", "0x" + HEX_CHARS[bits & 0xF], "")
      return out

    Value.fld("tag", "bits 63..48", "0x" + Value.hex_n(tag, 4), "unknown")

  -> .swatch(r, g, b, text)
    lum = 0.299 * r.to_f() + 0.587 * g.to_f() + 0.114 * b.to_f()
    fg = lum > 128.0 ? "38;2;0;0;0" : "38;2;255;255;255"
    "\e\[48;2;" + r.to_s() + ";" + g.to_s() + ";" + b.to_s() + "m\e\[" + fg + "m" + text + "\e\[0m"

  -> .rgb_to_hsl(r, g, b)
    rd = r.to_f() / 255.0
    gd = g.to_f() / 255.0
    bd = b.to_f() / 255.0
    mx = rd > gd ? (rd > bd ? rd : bd) : (gd > bd ? gd : bd)
    mn = rd < gd ? (rd < bd ? rd : bd) : (gd < bd ? gd : bd)
    l = (mx + mn) / 2.0
    if mx == mn
      return [0.0, 0.0, l]
    d = mx - mn
    s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
    hue = 0.0
    if mx == rd
      hue = ((gd - bd) / d + (gd < bd ? 6.0 : 0.0)) / 6.0
    elsif mx == gd
      hue = ((bd - rd) / d + 2.0) / 6.0
    else
      hue = ((rd - gd) / d + 4.0) / 6.0
    [hue * 360.0, s, l]

  -> .hue_ch(p, q, t)
    tt = t
    if tt < 0.0
      tt = tt + 1.0
    if tt > 1.0
      tt = tt - 1.0
    if tt < 1.0 / 6.0
      return p + (q - p) * 6.0 * tt
    if tt < 0.5
      return q
    if tt < 2.0 / 3.0
      return p + (q - p) * (2.0 / 3.0 - tt) * 6.0
    p

  -> .clampb(v)
    if v < 0
      return 0
    if v > 255
      return 255
    v

  -> .hsl_to_rgb(h, s, l)
    hh = h
    while hh < 0.0
      hh = hh + 360.0
    while hh >= 360.0
      hh = hh - 360.0
    hh = hh / 360.0
    if s == 0.0
      v = (l * 255.0 + 0.5).to_i()
      return [v, v, v]
    q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
    p = 2.0 * l - q
    r = Value.clampb((Value.hue_ch(p, q, hh + 1.0 / 3.0) * 255.0 + 0.5).to_i())
    g = Value.clampb((Value.hue_ch(p, q, hh) * 255.0 + 0.5).to_i())
    b = Value.clampb((Value.hue_ch(p, q, hh - 1.0 / 3.0) * 255.0 + 0.5).to_i())
    [r, g, b]

  -> .palette_line(hdrlabel, name, hues, s, l)
    chips = ""
    i = 0
    while i < hues.size()
      rgb = Value.hsl_to_rgb(hues[i], s, l)
      r = rgb[0]
      g = rgb[1]
      b = rgb[2]
      sw = Value.swatch(r, g, b, "  ")
      hex = "#" + Value.hex_n(r, 2) + Value.hex_n(g, 2) + Value.hex_n(b, 2)
      if i > 0
        chips = chips + "  "
      chips = chips + sw + " " + hex
      i = i + 1
    Value.hdr(hdrlabel, Value.ljust(name, 10) + " " + chips)

  -> .color_bar(v)
    filled = (v.to_f() / 255.0 * 16.0 + 0.5).to_i()
    out = ""
    i = 0
    while i < filled
      out = out + "█"
      i = i + 1
    i = 0
    while i < 16 - filled
      out = out + "░"
      i = i + 1
    out

  -> .color_scene(vv)
    bits = vv$value ## i64
    r = ((bits >> 36) & 0xFF) ## i64
    g = ((bits >> 28) & 0xFF) ## i64
    b = ((bits >> 20) & 0xFF) ## i64
    a = ((bits >> 12) & 0xFF) ## i64

    sw = Value.swatch(r, g, b, "    ")
    out = Value.hdr("swatch", sw + " " + sw + " " + sw)
    out = out + Value.hdr("rgba", r.to_s() + ", " + g.to_s() + ", " + b.to_s() + ", " + a.to_s())

    hsl = Value.rgb_to_hsl(r, g, b)
    h = hsl[0]
    s = hsl[1]
    l = hsl[2]
    h_int = (h + 0.5).to_i()
    s_int = (s * 100.0 + 0.5).to_i()
    l_int = (l * 100.0 + 0.5).to_i()
    out = out + Value.hdr("hsl", h_int.to_s() + "° " + s_int.to_s() + "% " + l_int.to_s() + "%")

    lum = 0.299 * r.to_f() + 0.587 * g.to_f() + 0.114 * b.to_f()
    lum10 = (lum * 10.0 + 0.5).to_i()
    lum_str = (lum10 / 10).to_s() + "." + (lum10 % 10).to_s()
    lum_txt = lum > 128.0 ? "black text" : "white text"
    out = out + Value.hdr("luma", lum_str + " · " + lum_txt)

    out = out + Value.hdr("red", Value.color_bar(r) + " " + r.to_s())
    out = out + Value.hdr("green", Value.color_bar(g) + " " + g.to_s())
    out = out + Value.hdr("blue", Value.color_bar(b) + " " + b.to_s())
    out = out + Value.hdr("alpha", Value.color_bar(a) + " " + a.to_s())

    out = out + Value.palette_line("palette", "complement", [h + 180.0], s, l)
    out = out + Value.palette_line("", "triad", [h + 120.0, h + 240.0], s, l)
    out = out + Value.palette_line("", "analogous", [h - 30.0, h + 30.0], s, l)
    out

  -> .ip4_scene(vv)
    bits = vv$value ## i64
    addr = ((bits >> 12) & 0xFFFFFFFF) ## i64
    o0 = ((addr >> 24) & 0xFF) ## i64
    o1 = ((addr >> 16) & 0xFF) ## i64
    o2 = ((addr >> 8) & 0xFF) ## i64
    o3 = (addr & 0xFF) ## i64

    priv = o0 == 10 || (o0 == 172 && o1 >= 16 && o1 <= 31) || (o0 == 192 && o1 == 168)
    cls = "Class C public"
    if priv
      cls = "private RFC1918"
    elsif o0 == 127
      cls = "loopback"
    elsif o0 == 169 && o1 == 254
      cls = "link-local"
    elsif o0 >= 224 && o0 <= 239
      cls = "multicast"
    elsif o0 >= 240
      cls = "reserved"
    elsif o0 < 128
      cls = "Class A public"
    elsif o0 < 192
      cls = "Class B public"

    out = Value.hdr("class", cls)
    out = out + Value.hdr("hex", "0x" + Value.hex_n(addr, 8))
    bin = Value.bin_n(o0, 8) + "." + Value.bin_n(o1, 8) + "." + Value.bin_n(o2, 8) + "." + Value.bin_n(o3, 8)
    out = out + Value.hdr("binary", bin)
    out = out + Value.hdr("ptr", o3.to_s() + "." + o2.to_s() + "." + o1.to_s() + "." + o0.to_s() + ".in-addr.arpa")
    out
