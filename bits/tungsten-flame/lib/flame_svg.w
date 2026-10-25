# flame_svg.w — Render folded stacks as an interactive SVG flame graph.

use folded

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
    self.emit_children_into(out, root, 0, total, plot_w, margin, max_d, frame_h, top)
    out.push("</g>")
    out.push("<text id=\"details\" x=\"" + margin.to_s() + "\" y=\"" + (h - 9).to_s() + "\"> </text>")
    out.push("<text id=\"info\" x=\"" + (width - margin).to_s() + "\" y=\"" + (h - 9).to_s() + "\" text-anchor=\"end\" font-size=\"12px\" fill=\"#666\">" + total.to_s() + " samples</text>")
    out.push(self.svg_script(margin, plot_w))
    out.push("</svg>")
    out.join("")

  # ---- Tree construction (delegated to Folded) ----

  -> .build_tree(folded_text)
    Tungsten:Flame:Folded.build_tree(folded_text)

  -> .insert_stack(root, frames, count)
    Tungsten:Flame:Folded.insert_stack(root, frames, count)

  -> .find_child(node, name)
    Tungsten:Flame:Folded.find_child(node, name)

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

  -> .sort_children(kids)
    Tungsten:Flame:Folded.sort_children(kids)

  # ---- SVG emission ----

  -> .emit_children(node, x_start, total, plot_w, margin, max_d, frame_h, top)
    parts = []
    self.emit_children_into(parts, node, x_start, total, plot_w, margin, max_d, frame_h, top)
    parts.join("")

  -> .emit_children_into(out, node, x_start, total, plot_w, margin, max_d, frame_h, top)
    kids = self.sort_children(node[:children])
    cur = x_start
    i = 0
    n = kids.size()
    while i < n
      child = kids[i]
      out.push(self.emit_frame(child, cur, total, plot_w, margin, max_d, frame_h, top))
      self.emit_children_into(out, child, cur, total, plot_w, margin, max_d, frame_h, top)
      cur = cur + child[:count]
      i = i + 1

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
      label_esc = label == name ? esc : self.xml_escape(label)
      txt = "<text x=\"" + (px + 3).to_s() + "\" y=\"" + (y + frame_h - 5).to_s() + "\" font-size=\"12px\">" + label_esc + "</text>"
    g + rect + txt + "</g>"

  # ---- Formatting helpers ----

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

  -> .fmt_pct(n, total)
    Tungsten:Flame:Folded.fmt_pct(n, total)

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

  -> .xml_escape(s)
    s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

  -> .color_for(name)
    h = self.name_hash(name)
    r = 205 + (h % 51)
    g = (h / 51) % 231
    b = (h / 11781) % 56
    "rgb(" + r.to_s() + "," + g.to_s() + "," + b.to_s() + ")"

  -> .name_hash(name)
    h = 2166136261
    i = 0
    n = name.size()
    while i < n
      h = (h * 31 + name.byte_at(i)) % 2147483629
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

  -> .svg_script(margin, plot_w)
    js = "var mx=" + margin.to_s() + ",plotW=" + plot_w.to_s() + ";"
    js = js + "function fr(){return document.getElementsByClassName('frame');}"
    js = js + "function fit(t,name,pw){var m=Math.floor((pw-6)/7);if(m<3){t.style.display='none';return;}t.style.display='';var s=name;if(s.length>m){s=s.substring(0,m-2)+'..';}t.textContent=s;}"
    js = js + "function place(g,x0,x1,sc){var a=parseFloat(g.getAttribute('data-x0'));var b=parseFloat(g.getAttribute('data-x1'));var r=g.getElementsByTagName('rect')\[0\];var t=g.getElementsByTagName('text')\[0\];if(b<=x0||a>=x1){g.style.display='none';return;}g.style.display='';var px=mx+(a-x0)*sc*plotW;var pw=(b-a)*sc*plotW;if(pw<1){pw=1;}r.setAttribute('x',px);r.setAttribute('width',pw);if(t){t.setAttribute('x',px+3);fit(t,g.getAttribute('data-name'),pw);}}"
    js = js + "function zoom(x0,x1){var sc=1/(x1-x0);var gs=fr();for(var i=0;i<gs.length;i++){place(gs\[i\],x0,x1,sc);}var d=document.getElementById('details');if(d){d.textContent=(x0>0||x1<1)?'Zoomed - click title or here to reset':'';}}"
    js = js + "function reset(){zoom(0,1);}"
    js = js + "window.addEventListener('load',function(){var gs=fr();for(var i=0;i<gs.length;i++){var g=gs\[i\];var a=parseFloat(g.getAttribute('data-x0'));var b=parseFloat(g.getAttribute('data-x1'));g.onclick=(function(x,y){return function(e){zoom(x,y);if(e){e.stopPropagation();}};})(a,b);}var d=document.getElementById('details');if(d){d.style.cursor='pointer';d.onclick=reset;}var ti=document.getElementById('title');if(ti){ti.style.cursor='pointer';ti.onclick=reset;}});"
    "<script>\n// <!\[CDATA\[\n" + js + "\n// \]\]>\n</script>\n"
