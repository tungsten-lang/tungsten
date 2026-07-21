# flame_svg.w — Render folded stacks as an interactive SVG flame graph.
#
# This is the tool's namesake output: it turns folded-stack text
# ("root;mid;leaf <count>" per line, the same format PerfScript.collapse
# and XctraceXml.collapse produce) into a self-contained SVG flame graph
# that any browser or SVG viewer can open.
#
# Layout follows the canonical (Brendan Gregg) convention:
#   - Frames are laid out bottom-up: the first frame of each stack sits on
#     the bottom row, the stack grows upward.
#   - A frame's width is proportional to its inclusive sample count.
#   - Children are left-aligned within their parent's span and sorted by
#     name, so identical prefixes across stacks merge into one wide frame
#     and the picture is deterministic.
#   - A frame wider than the sum of its children shows the exposed strip as
#     self time — no synthetic "all" root is inserted (faithful to
#     flamegraph.pl: the bottom row is the real base frames).
#
# Interactivity is self-contained, no external assets:
#   - Every frame carries a native <title> tooltip (function, sample count,
#     percentage) — works on hover in any viewer, JS or not.
#   - An embedded script gives click-to-zoom (a frame fills the width, its
#     subtree rescales, everything else hides) and click-to-reset. Each
#     frame stores its sample-space bounds in data-x0/data-x1 so the script
#     recomputes pixel geometry without re-parsing the tree. The static
#     positions Tungsten emits already match zoom(0,1), so the graph is
#     correct with scripting disabled.

in Tungsten:Flame

+ FlameSvg

  # ---- Public entry points ----

  # Render folded-stack text to a complete SVG document string.
  -> .render(folded_text, title)
    self.render_sized(folded_text, title, 1200)

  -> .render_sized(folded_text, title, width)
    root = self.build_tree(folded_text)
    total = root[:count]
    margin = 10
    frame_h = 16
    header = 48
    footer = 26
    plot_w = width - margin * 2

    if total == 0
      h = header + footer
      out = []
      out.push(self.svg_open(width, h))
      out.push(self.svg_style)
      out.push(self.bg(width, h))
      out.push(self.title_text(title, width))
      out.push("<text x=\"" + (width / 2).to_s() + "\" y=\"" + (header + 8).to_s() + "\" text-anchor=\"middle\" font-size=\"12px\" fill=\"#666\">no samples</text>")
      out.push("</svg>")
      return out.join("")

    max_d = self.max_depth(root)
    rows = max_d + 1
    top = header
    h = header + rows * frame_h + footer

    out = []
    out.push(self.svg_open(width, h))
    out.push(self.svg_style)
    out.push(self.bg(width, h))
    out.push(self.title_text(title, width))
    out.push("<g id=\"frames\">")
    out.push(self.emit_children(root, 0, total, plot_w, margin, max_d, frame_h, top))
    out.push("</g>")
    out.push("<text id=\"details\" x=\"" + margin.to_s() + "\" y=\"" + (h - 9).to_s() + "\"> </text>")
    out.push("<text id=\"info\" x=\"" + (width - margin).to_s() + "\" y=\"" + (h - 9).to_s() + "\" text-anchor=\"end\" font-size=\"12px\" fill=\"#666\">" + total.to_s() + " samples</text>")
    out.push(self.svg_script(margin, plot_w))
    out.push("</svg>")
    out.join("")

  # ---- Tree construction ----

  # Parse folded text into a frame tree. Root is a virtual container at
  # depth -1 whose children are the real depth-0 base frames.
  -> .build_tree(folded_text)
    root = { name: "root", count: 0, depth: -1, children: [] }
    lines = folded_text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        stack = line
        count = 0
        if sp != nil
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
        if count > 0
          self.insert_stack(root, stack.split(";"), count)
      i = i + 1
    root

  -> .insert_stack(root, frames, count)
    root[:count] = root[:count] + count
    node = root
    fi = 0
    while fi < frames.size()
      name = frames[fi]
      child = self.find_child(node, name)
      if child == nil
        child = { name: name, count: 0, depth: node[:depth] + 1, children: [] }
        node[:children].push(child)
      child[:count] = child[:count] + count
      node = child
      fi = fi + 1

  -> .find_child(node, name)
    kids = node[:children]
    i = 0
    while i < kids.size()
      if kids[i][:name] == name
        return kids[i]
      i = i + 1
    nil

  # Deepest depth in the subtree rooted at `node`.
  -> .max_depth(node)
    md = node[:depth]
    kids = node[:children]
    i = 0
    while i < kids.size()
      cd = self.max_depth(kids[i])
      if cd > md
        md = cd
      i = i + 1
    md

  # Children sorted by name (stable, deterministic output).
  -> .sort_children(kids)
    arr = []
    i = 0
    while i < kids.size()
      arr.push(kids[i])
      i = i + 1
    j = 1
    while j < arr.size()
      key = arr[j]
      k = j - 1
      while k >= 0 && arr[k][:name] > key[:name]
        arr[k + 1] = arr[k]
        k = k - 1
      arr[k + 1] = key
      j = j + 1
    arr

  # ---- SVG emission ----

  # Emit every child of `node`, laid out left-to-right starting at
  # `x_start` (sample-space). Returns the concatenated SVG fragment.
  -> .emit_children(node, x_start, total, plot_w, margin, max_d, frame_h, top)
    parts = []
    kids = self.sort_children(node[:children])
    cur = x_start
    i = 0
    while i < kids.size()
      child = kids[i]
      parts.push(self.emit_frame(child, cur, total, plot_w, margin, max_d, frame_h, top))
      parts.push(self.emit_children(child, cur, total, plot_w, margin, max_d, frame_h, top))
      cur = cur + child[:count]
      i = i + 1
    parts.join("")

  # One frame: a <g> holding a colored <rect> (with a <title> tooltip) and,
  # when it fits, a truncated <text> label. `x_start` is the frame's left
  # edge in sample units; its span is [x_start, x_start + count).
  -> .emit_frame(node, x_start, total, plot_w, margin, max_d, frame_h, top)
    name = node[:name]
    count = node[:count]
    px = margin + (x_start * plot_w / total)
    pw = count * plot_w / total
    if pw < 1
      pw = 1
    y = top + (max_d - node[:depth]) * frame_h

    dx0 = self.frac_str(x_start, total)
    dx1 = self.frac_str(x_start + count, total)
    esc = self.xml_escape(name)
    pct = self.fmt_pct(count, total)
    color = self.color_for(name)

    g = "<g class=\"frame\" data-x0=\"" + dx0 + "\" data-x1=\"" + dx1 + "\" data-name=\"" + esc + "\">"
    rect = "<rect x=\"" + px.to_s() + "\" y=\"" + y.to_s() + "\" width=\"" + pw.to_s() + "\" height=\"" + (frame_h - 1).to_s() + "\" fill=\"" + color + "\" rx=\"2\" ry=\"2\"><title>" + esc + " (" + count.to_s() + " samples, " + pct + "%)</title></rect>"
    label = self.fit_label(name, pw)
    txt = ""
    if label != ""
      txt = "<text x=\"" + (px + 3).to_s() + "\" y=\"" + (y + frame_h - 5).to_s() + "\" font-size=\"12px\">" + self.xml_escape(label) + "</text>"
    g + rect + txt + "</g>"

  # ---- Formatting helpers ----

  # Longest prefix of `name` that fits a `pw`-pixel-wide frame (~7px/char
  # at 12px Verdana, minus a little padding). Empty string when nothing
  # legible fits. Truncated names get a ".." suffix.
  -> .fit_label(name, pw)
    max = (pw - 6) / 7
    if max < 3
      return ""
    if name.size() <= max
      return name
    keep = max - 2
    if keep < 1
      return ""
    name.slice(0, keep) + ".."

  # Percentage with one decimal, via integer math (no BigDecimal notation).
  -> .fmt_pct(n, total)
    pct_x10 = n * 1000 / total
    whole = pct_x10 / 10
    frac = pct_x10 - whole * 10
    whole.to_s() + "." + frac.to_s()

  # value/total as a decimal string in [0, 1], six fractional digits — the
  # sample-space bound the zoom script parses back with parseFloat.
  -> .frac_str(value, total)
    if value >= total
      return "1"
    if value <= 0
      return "0"
    micro = value * 1000000 / total
    s = micro.to_s()
    while s.size() < 6
      s = "0" + s
    "0." + s

  # Escape the five characters that would otherwise break XML markup.
  -> .xml_escape(s)
    s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

  # Deterministic warm ("hot") fill for a frame name: reds/oranges/yellows,
  # like flamegraph.pl, but seeded from the name so a symbol always gets the
  # same color across runs and across metrics.
  -> .color_for(name)
    h = self.name_hash(name)
    r = 205 + (h % 51)
    g = (h / 51) % 231
    b = (h / 11781) % 56
    "rgb(" + r.to_s() + "," + g.to_s() + "," + b.to_s() + ")"

  -> .name_hash(name)
    h = 2166136261
    i = 0
    while i < name.size()
      ch = name.slice(i, 1)
      h = (h * 31 + ch.ord) % 2147483629
      i = i + 1
    h

  # ---- SVG scaffolding ----

  -> .svg_open(width, height)
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + width.to_s() + "\" height=\"" + height.to_s() + "\" viewBox=\"0 0 " + width.to_s() + " " + height.to_s() + "\">\n"

  -> .bg(width, height)
    "<rect width=\"" + width.to_s() + "\" height=\"" + height.to_s() + "\" fill=\"#f8f8f8\"/>\n"

  -> .title_text(title, width)
    "<text id=\"title\" x=\"" + (width / 2).to_s() + "\" y=\"28\">" + self.xml_escape(title) + "</text>\n"

  -> .svg_style
    "<style>\n.frame rect { stroke: rgba(0,0,0,0.15); stroke-width: 0.5px; cursor: pointer; }\n.frame:hover rect { stroke: #000; stroke-width: 1px; }\ntext { font-family: Verdana, Helvetica, Arial, sans-serif; fill: #111; }\n#title { font-size: 17px; font-weight: bold; text-anchor: middle; }\n#details, #info { font-size: 12px; fill: #555; }\n.frame text { pointer-events: none; }\n</style>\n"

  # Click-to-zoom / click-to-reset. Literal square brackets are escaped
  # (\[ \]) because unescaped brackets interpolate inside a .w string; the
  # JS lives in a CDATA section so its <, > and & are literal in the XML.
  -> .svg_script(margin, plot_w)
    js = "var mx=" + margin.to_s() + ",plotW=" + plot_w.to_s() + ";"
    js = js + "function fr(){return document.getElementsByClassName('frame');}"
    js = js + "function fit(t,name,pw){var m=Math.floor((pw-6)/7);if(m<3){t.style.display='none';return;}t.style.display='';var s=name;if(s.length>m){s=s.substring(0,m-2)+'..';}t.textContent=s;}"
    js = js + "function place(g,x0,x1,sc){var a=parseFloat(g.getAttribute('data-x0'));var b=parseFloat(g.getAttribute('data-x1'));var r=g.getElementsByTagName('rect')\[0\];var t=g.getElementsByTagName('text')\[0\];if(b<=x0||a>=x1){g.style.display='none';return;}g.style.display='';var px=mx+(a-x0)*sc*plotW;var pw=(b-a)*sc*plotW;if(pw<1){pw=1;}r.setAttribute('x',px);r.setAttribute('width',pw);if(t){t.setAttribute('x',px+3);fit(t,g.getAttribute('data-name'),pw);}}"
    js = js + "function zoom(x0,x1){var sc=1/(x1-x0);var gs=fr();for(var i=0;i<gs.length;i++){place(gs\[i\],x0,x1,sc);}var d=document.getElementById('details');if(d){d.textContent=(x0>0||x1<1)?'Zoomed - click title or here to reset':'';}}"
    js = js + "function reset(){zoom(0,1);}"
    js = js + "window.addEventListener('load',function(){var gs=fr();for(var i=0;i<gs.length;i++){var g=gs\[i\];var a=parseFloat(g.getAttribute('data-x0'));var b=parseFloat(g.getAttribute('data-x1'));g.onclick=(function(x,y){return function(e){zoom(x,y);if(e){e.stopPropagation();}};})(a,b);}var d=document.getElementById('details');if(d){d.style.cursor='pointer';d.onclick=reset;}var ti=document.getElementById('title');if(ti){ti.style.cursor='pointer';ti.onclick=reset;}});"
    "<script>\n// <!\[CDATA\[\n" + js + "\n// \]\]>\n</script>\n"
