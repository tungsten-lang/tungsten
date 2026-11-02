in Av

+ Text
  -> .timestamp(value)
    parts = value.replace(",", ":").replace(".", ":").split(":")
    raise "invalid subtitle timestamp" if parts.size != 4 || parts[1].to_i >= 60 || parts[2].to_i >= 60
    parts[0].to_i * 3600 + parts[1].to_i * 60 + parts[2].to_i + parts[3].to_f / 1000

  -> .captions(path)
    raise "subtitle file exceeds 16 MiB" if File.stat(path).size > 16777216
    content = File.read(path).replace("\r\n", "\n").replace("\uFEFF", "")
    result = []
    previous = ~-1.0
    blocks = []
    buffer = []
    content.split("\n").each ->(line)
      if line.strip == ""
        blocks.push(buffer) if buffer.size > 0
        buffer = []
      else
        buffer.push(line)
    blocks.push(buffer) if buffer.size > 0
    blocks.each ->(lines)
      lines.shift if Regex.new("\\A\\d+\\z").match?(lines[0])
      raise "subtitle cue needs a timestamp and text" if lines.size < 2
      match = Regex.new("\\A(\\d{2,}:\\d{2}:\\d{2}\[,.]\\d{3})\\s+-->\\s+(\\d{2,}:\\d{2}:\\d{2}\[,.]\\d{3})\\z").match_data(lines.shift)
      raise "invalid SRT timestamp" if match == nil
      start = timestamp(match[1])
      finish = timestamp(match[2])
      raise "subtitle times must be ordered with positive duration" if start < previous || finish <= start
      previous = start
      result.push({"start": start, "end": finish, "text": lines.join("\n")})
    result

  -> .shape(text, font, size)
    shaped = ccall("w_cg_font_shape", font, text, size)
    {"advance": shaped[0], "bounds": shaped[1], "paths": shaped[2]}

  -> .luminance(colour)
    raise "text colours require #rrggbb" if !Regex.new("\\A#\[0-9a-fA-F]{6}\\z").match?(colour)
    values = []
    [1, 3, 5].each ->(i)
      digits = "0123456789abcdef"
      x = (digits.index(colour.slice(i, 1).downcase) * 16 + digits.index(colour.slice(i + 1, 1).downcase)) / ~255.0
      values.push(x <= ~0.04045 ? x / ~12.92 : Math.pow((x + ~0.055) / ~1.055, ~2.4))
    values[0] * ~0.2126 + values[1] * ~0.7152 + values[2] * ~0.0722

  -> .layout(cues, settings, width, height, font)
    size = Util.get(settings, "size", 48)
    safe = Util.get(settings, "safe_area", ~0.05)
    box = Util.get(settings, "box", [safe, ~0.7, 1 - 2 * safe, ~0.25])
    raise "caption box violates safe area" if safe >= ~0.5 || box[0] < safe || box[1] < safe || box[0] + box[2] > 1 - safe + ~1e-9 || box[1] + box[3] > 1 - safe + ~1e-9
    foreground = luminance(Util.get(settings, "foreground", "#ffffff"))
    background = luminance(Util.get(settings, "background", "#000000"))
    contrast = (Util.max(foreground, background) + ~0.05) / (Util.min(foreground, background) + ~0.05)
    issues = []
    index = 0
    cues.each ->(cue)
      index += 1
      widths = cue["text"].split("\n").map ->(line)
        shaped = Text.shape(line, font, size)
        bounds = shaped["bounds"]
        Util.max(shaped["advance"], bounds[0] + bounds[2]) - Util.min(0, bounds[0])
      max_width = 0
      widths.each ->(w)
        max_width = Util.max(max_width, w)
      if size < Util.get(settings, "minimum_size", 24) || max_width > box[2] * width || widths.size * size * ~1.3 > box[3] * height
        issues.push({"cue": index, "problem": "text does not fit at configured size"})
    {"ok": issues.size == 0 && contrast >= Util.get(settings, "minimum_contrast", ~4.5), "issues": issues, "contrast": contrast, "font": font, "size": size, "box": box, "cues": cues.size}

  -> .outlines(cues, settings, width, height, font)
    report = layout(cues, settings, width, height, font)
    raise "caption layout fails before rendering" if !report["ok"]
    size = report["size"]
    box = report["box"]
    result = []
    cues.each ->(cue)
      lines = []
      texts = cue["text"].split("\n")
      i = 0
      texts.each ->(text)
        if text.strip != ""
          shape = Text.shape(text, font, size)
          b = shape["bounds"]
          lines.push({"x": box[0] * width + (box[2] * width - b[2]) / 2 - b[0], "y": box[1] * height + (box[3] * height - texts.size * size * ~1.3) / 2 + i * size * ~1.3 - b[1], "paths": shape["paths"]})
        i += 1
      result.push({"start_ms": Math.round(cue["start"] * 1000).to_i, "end_ms": Math.round(cue["end"] * 1000).to_i, "lines": lines, "box": [Math.round(box[0] * width).to_i, Math.round(box[1] * height).to_i, Math.round(box[2] * width).to_i, Math.round(box[3] * height).to_i], "foreground": Util.get(settings, "foreground", "#ffffff"), "background": Util.get(settings, "background", "#000000")})
    result
