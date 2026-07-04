+ Color
  # Convert hue (0-359) to [r, g, b] array at full saturation
  -> .hue_components(h)
    h = h % 360
    s = h / 60
    f = (h % 60) * 255 / 60
    if s == 0
      return [255, f, 0]
    if s == 1
      return [255 - f, 255, 0]
    if s == 2
      return [0, 255, f]
    if s == 3
      return [0, 255 - f, 255]
    if s == 4
      return [f, 0, 255]
    [255, 0, 255 - f]

  # Convert hue (0-359) to Color value
  -> .hue_rgb(h)
    Color.from(Color.hue_components(h))

  # Desaturate: blend RGB toward gray by (100-pct)%
  -> .desat(rgb, pct)
    r = rgb[0] + (128 - rgb[0]) * (100 - pct) / 100
    g = rgb[1] + (128 - rgb[1]) * (100 - pct) / 100
    b = rgb[2] + (128 - rgb[2]) * (100 - pct) / 100
    Color.from([r, g, b])

  # Darken: scale RGB toward black
  -> .darken(rgb, pct)
    r = rgb[0] * pct / 100
    g = rgb[1] * pct / 100
    b = rgb[2] * pct / 100
    Color.from([r, g, b])

  -> .rgb(r, g, b)
    ccall("w_color_raw", r, g, b, 255)

  -> .from(arr)
    ccall("w_color_raw", arr[0], arr[1], arr[2], 255)

  -> .bg(r, g, b)
    "\e[48;2;[r];[g];[b]m \e[0m"

  -> .demo
    << ""
    << "  \e[1mColor Palette\e[0m"
    << ""

    # Saturation gradient: 100% → 10%
    s = 100
    while s >= 10
      row = "  "
      h = 0
      while h < 360
        c = Color.desat(Color.hue_components(h), s)
        row = row + "\e[48;2;[c[0]];[c[1]];[c[2]]m \e[0m"
        h = h + 6
      << row + "  sat [s]%"
      s = s - 10

    << ""

    # Brightness gradient: 100% → 10%
    b = 100
    while b >= 10
      row = "  "
      h = 0
      while h < 360
        c = Color.darken(Color.hue_components(h), b)
        row = row + "\e[48;2;[c[0]];[c[1]];[c[2]]m \e[0m"
        h = h + 6
      << row + "  lum [b]%"
      b = b - 10

    << ""

    # Named swatches
    names  = ["Ruby",  "Ember", "Gold",  "Jade",  "Azure", "Violet","Rose",  "Slate"]
    colors = [[224,17,95],[255,107,53],[255,215,0],[0,180,108],[0,127,255],[138,43,226],[255,0,127],[112,128,144]]

    row = "  "
    lbl = "  "
    i = 0
    while i < names.size()
      c = colors[i]
      row = row + "\e[48;2;[c[0]];[c[1]];[c[2]]m      \e[0m "
      n = names[i]
      while n.size() < 7
        n = n + " "
      lbl = lbl + n
      i = i + 1
    << row
    << lbl
    << ""

  -> .logo(name, bg, fg, symbol)
    # Render a 22×5 colored badge with symbol and name
    b = "\e[48;2;[bg[0]];[bg[1]];[bg[2]]m"
    f = "\e[38;2;[fg[0]];[fg[1]];[fg[2]]m"
    r = "\e[0m"
    label = " " + symbol + " " + name
    while label.size() < 22
      label = label + " "
    << "  " + b + f + label + r

  -> .polyglot
    << ""
    << "  \e[1mPolyglot\e[0m — languages in their brand colors"
    << ""
    Color.logo("Ruby",       [204,52,45],   [255,230,230], "◆")
    Color.logo("Python",     [55,118,171],  [255,215,59],  "🐍")
    Color.logo("Go",         [0,173,216],   [255,255,255], "⬡")
    Color.logo("Rust",       [183,65,14],   [255,200,150], "⚙")
    Color.logo("JavaScript", [247,223,30],  [50,50,50],    "{ }")
    Color.logo("Swift",      [250,115,67],  [255,255,255], "🐦")
    Color.logo("Elixir",     [110,74,126],  [220,200,240], "💧")
    Color.logo("Haskell",    [94,80,134],   [200,200,230], "λ")
    Color.logo("C",          [0,90,156],    [200,220,240], "/*")
    Color.logo("Zig",        [247,164,29],  [50,30,0],     "⚡")
    Color.logo("OCaml",      [238,122,0],   [255,255,255], "🐫")
    Color.logo("Tungsten",   [105,95,126],  [220,218,230], "W")
    << ""

  -> .tungsten
    # "TUNGSTEN" — 16 rows tall, monochromatic tungsten palette
    # Each letter is 10 wide × 16 tall, 8 letters = 80 cols
    # '#' = lit, '.' = dark — vertical gradient from bright to warm
    art = [
      "########..##....##..##....##...######....######..########..########..##....##..",
      "########..##....##..##....##...######....######..########..########..##....##..",
      "...##.....##....##..###...##..##....##..##....##....##.....##........###...##..",
      "...##.....##....##..###...##..##....##..##....##....##.....##........###...##..",
      "...##.....##....##..####..##..##........##..........##.....##........####..##..",
      "...##.....##....##..####..##..##........##..........##.....##........####..##..",
      "...##.....##....##..##.##.##..##.####....######.....##.....######....##.##.##..",
      "...##.....##....##..##.##.##..##.####....######.....##.....######....##.##.##..",
      "...##.....##....##..##..####..##...###........##....##.....##........##..####..",
      "...##.....##....##..##..####..##...###........##....##.....##........##..####..",
      "...##.....##....##..##...###..##....##..##....##....##.....##........##...###..",
      "...##.....##....##..##...###..##....##..##....##....##.....##........##...###..",
      "...##.....##....##..##....##..##....##..##....##....##.....##........##....##..",
      "...##.....##....##..##....##..##....##..##....##....##.....##........##....##..",
      "...##......######...##....##...######....######.....##.....########..##....##..",
      "...##......######...##....##...######....######.....##.....########..##....##.."
    ]

    # Vertical gradient: bright silver → deep slate-purple
    grad = [
      [220, 218, 230],
      [205, 202, 218],
      [190, 186, 206],
      [178, 172, 196],
      [165, 158, 185],
      [152, 144, 174],
      [140, 130, 162],
      [128, 118, 150],
      [116, 106, 138],
      [105, 95, 126],
      [94, 84, 115],
      [84, 74, 104],
      [74, 65, 94],
      [65, 56, 84],
      [56, 48, 74],
      [48, 40, 65]
    ]

    bg = [14, 12, 20]

    << ""
    row = 0
    while row < 16
      c = grad[row]
      line = "  "
      i = 0
      while i < art[row].size()
        ch = art[row][i]
        if ch == "#"
          line = line + "\e[48;2;[c[0]];[c[1]];[c[2]]m \e[0m"
        else
          line = line + "\e[48;2;[bg[0]];[bg[1]];[bg[2]]m \e[0m"
        i = i + 1
      << line
      row = row + 1
    << ""
