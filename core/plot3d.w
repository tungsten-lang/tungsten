# Plot3D — interactive 3D visualization export for grid simulations.
#
# Renders a simulation spec into a single self-contained HTML file with an
# embedded three.js scene: drag to orbit, scroll to zoom, right-drag to
# pan, with playback over captured frames and live control over fields,
# colormaps, isosurfaces, slice planes, and height scaling. Works offline —
# three.js (vendored at data/viewer3d/three.module.min.js) is inlined via
# an import-map data: URL, and all field data ships quantized to 8 bits
# with per-frame ranges.
#
# Spec schema (hash; symbol keys at the top level):
#   kind    "surface" (2D height map) | "volume" (3D iso+slices) |
#           "spacetime" (1D stacked over time)
#   title   display name
#   dims    [nx, ny, nz] interior cells (unused axes = 1)
#   domain  [Lx, Ly, Lz] physical lengths (metres; aspect only)
#   fields  ["rho", ...] field names, matching every frame
#   frames  [{t:, fields: {"rho" => {"b64","min","max"}, ...}}, ...]
#   mask    base64 u8 grid of solid cells, or nil
#   meta    {"label" => "value"} shown in the parameter panel
#   live    optional: server URL path for re-running with new parameters
#
# EulerSimulation#view! builds this spec automatically; Plot.viewer3d is
# the generic facade for any gridded data.

+ Plot3D
  # -- asset resolution -------------------------------------------------------

  -> .asset_root
    override = env("TUNGSTEN_VIEWER3D_ASSETS")
    return override if override != nil && override != ""
    home = env("TUNGSTEN_HOME")
    if home != nil && home != ""
      return home + "/data/viewer3d"
    local = "data/viewer3d"
    probe = read_file(local + "/three.module.min.js")
    return local if probe != nil
    env("HOME") + "/tungsten/data/viewer3d"

  -> .three_source
    path = Plot3D.asset_root() + "/three.module.min.js"
    src = read_file(path)
    if src == nil
      raise "Plot3D: three.js asset not found at [path] (set TUNGSTEN_HOME or TUNGSTEN_VIEWER3D_ASSETS)"
    src

  # -- field packing ----------------------------------------------------------

  # Quantize src[0..n) to 8 bits in dst; writes [min, max] into out[0..1].
  # NaN values (masked cells) map to 0 and are excluded from the range.
  -> .quantize(src, dst, n, out) (f64[] u8[] i64 f64[]) i64
    lo = ~1.0e308
    hi = ~-1.0e308
    i = 0 ## i64
    while i < n
      v = src[i]
      if v == v
        if v < lo
          lo = v
        if v > hi
          hi = v
      i = i + 1
    if hi < lo
      lo = ~0.0
      hi = ~0.0
    out[0] = lo
    out[1] = hi
    span = hi - lo
    if span <= ~0.0
      span = ~1.0
    i = 0 ## i64
    while i < n
      v = src[i]
      b = 0 ## i64
      if v == v
        scaled = (v - lo) / span * ~255.0
        if scaled < ~0.0
          scaled = ~0.0
        if scaled > ~255.0
          scaled = ~255.0
        b = (scaled + ~0.5).to_i
        if b > 255
          b = 255
      dst[i] = b
      i = i + 1
    0

  # f64[] -> {"b64" =>, "min" =>, "max" =>} ready for the frames array.
  -> .pack_field(raw)
    n = raw.size
    dst = u8[n]
    out = f64[2]
    Plot3D.quantize(raw, dst, n, out)
    packed = {}
    packed["b64"] = Base64.encode(dst)
    packed["min"] = out[0]
    packed["max"] = out[1]
    packed

  # -- output -----------------------------------------------------------------

  -> .write_and_open(path, html)
    write_file(path, html)
    << "viewer: [path]"
    system("open " + path)
    path

  # -- html assembly ----------------------------------------------------------

  -> .json_escape(s)
    "[s]".replace("\\", "\\\\").replace("\"", "\\\"")

  -> .frames_json(frames, fields)
    sb = StringBuffer()
    sb.append("\[")
    i = 0
    while i < frames.size
      fr = frames[i]
      sb.append(",") if i > 0
      sb.append("{\"t\":")
      t = fr[:t]
      sb.append("[t]")
      sb.append(",\"fields\":{")
      j = 0
      while j < fields.size
        name = fields[j]
        packed = fr[:fields][name]
        sb.append(",") if j > 0
        sb.append("\"")
        sb.append("[name]")
        sb.append("\":{\"b64\":\"")
        b64 = packed["b64"]
        sb.append("[b64]")
        sb.append("\",\"min\":")
        mn = packed["min"]
        sb.append("[mn]")
        sb.append(",\"max\":")
        mx = packed["max"]
        sb.append("[mx]")
        sb.append("}")
        j = j + 1
      sb.append("}}")
      i = i + 1
    sb.append("\]")
    sb.to_s

  -> .spec_json(spec)
    sb = StringBuffer()
    sb.append("{\"kind\":\"")
    sb.append("[spec[:kind]]")
    sb.append("\",\"title\":\"")
    esc_title = Plot3D.json_escape(spec[:title])
    sb.append("[esc_title]")
    sb.append("\",\"dims\":\[")
    dims = spec[:dims]
    sb.append("[dims[0]],[dims[1]],[dims[2]]")
    sb.append("\],\"domain\":\[")
    dom = spec[:domain]
    sb.append("[dom[0]],[dom[1]],[dom[2]]")
    sb.append("\],\"fields\":")
    fields_json = JSON.encode(spec[:fields])
    sb.append("[fields_json]")
    sb.append(",\"mask\":")
    if spec[:mask] == nil
      sb.append("null")
    else
      sb.append("\"")
      mask64 = spec[:mask]
      sb.append("[mask64]")
      sb.append("\"")
    sb.append(",\"live\":")
    if spec[:live] == nil
      sb.append("false")
    else
      sb.append("\"")
      sb.append("[spec[:live]]")
      sb.append("\"")
    sb.append(",\"params\":")
    if spec[:params] == nil
      sb.append("null")
    else
      params_json = JSON.encode(spec[:params])
      sb.append("[params_json]")
    sb.append(",\"meta\":")
    meta_json = JSON.encode(spec[:meta])
    sb.append("[meta_json]")
    sb.append(",\"frames\":")
    fj = Plot3D.frames_json(spec[:frames], spec[:fields])
    sb.append("[fj]")
    sb.append("}")
    sb.to_s

  -> .render(spec)
    # NOTE: every dynamic append is interpolation-wrapped ("[v]") — the
    # compiled StringBuffer#append drops raw locals/params/+-concats (see
    # TODO.md: strbuf append representation bug); interpolated and .to_s
    # arguments take the working path.
    three64 = Base64.encode(Plot3D.three_source())
    p1 = Plot3D.html_head()
    p2 = Plot3D.json_escape(spec[:title])
    p3 = Plot3D.html_importmap_open()
    p4 = Plot3D.html_importmap_close()
    p5 = Plot3D.app_css()
    p6 = Plot3D.html_body_open()
    p7 = Plot3D.spec_json(spec)
    p8 = Plot3D.html_data_close()
    p9 = Plot3D.app_js()
    p10 = Plot3D.html_tail()
    sb = StringBuffer()
    sb.append("[p1]")
    sb.append("[p2]")
    sb.append("[p3]")
    sb.append("[three64]")
    sb.append("[p4]")
    sb.append("[p5]")
    sb.append("[p6]")
    sb.append("[p7]")
    sb.append("[p8]")
    sb.append("[p9]")
    sb.append("[p10]")
    sb.to_s

  # -- static template pieces (heredocs: no interpolation) --------------------

  -> .html_head
    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <title>
    HTML

  -> .html_importmap_open
    <<~HTML
      </title>
      <script type="importmap">{"imports":{"three":"data:text/javascript;base64,
    HTML

  -> .html_importmap_close
    <<~HTML
      "}}</script>
    HTML

  -> .html_body_open
    <<~HTML
      </head>
      <body>
      <div id="app"></div>
      <div id="panel">
        <div id="ptitle"></div>
        <div class="row" id="row-field"><label>field</label><select id="sel-field"></select></div>
        <div class="row"><label>colors</label><select id="sel-cmap">
          <option value="viridis">viridis</option>
          <option value="magma">magma</option>
          <option value="coolwarm">coolwarm</option>
        </select></div>
        <div class="row" id="row-scale"><label>scale</label>
          <span class="seg"><input type="checkbox" id="chk-auto"/><label for="chk-auto" class="inline">per-frame</label></span>
        </div>
        <div class="row" id="row-height"><label>height</label><input type="range" id="rng-height" min="0" max="100" value="35"/></div>
        <div class="row" id="row-iso"><label>iso</label><input type="range" id="rng-iso" min="1" max="99" value="50"/><span id="iso-val" class="val"></span></div>
        <div class="row" id="row-showiso"><label>show</label>
          <span class="seg">
            <input type="checkbox" id="chk-iso" checked/><label for="chk-iso" class="inline">iso</label>
            <input type="checkbox" id="chk-sx"/><label for="chk-sx" class="inline">x</label>
            <input type="checkbox" id="chk-sy"/><label for="chk-sy" class="inline">y</label>
            <input type="checkbox" id="chk-sz" checked/><label for="chk-sz" class="inline">z</label>
          </span>
        </div>
        <div class="row" id="row-slx"><label>slice x</label><input type="range" id="rng-slx" min="0" max="100" value="50"/></div>
        <div class="row" id="row-sly"><label>slice y</label><input type="range" id="rng-sly" min="0" max="100" value="50"/></div>
        <div class="row" id="row-slz"><label>slice z</label><input type="range" id="rng-slz" min="0" max="100" value="50"/></div>
        <div id="legend"><canvas id="cbar" width="220" height="12"></canvas>
          <div id="legend-labels"><span id="lg-min"></span><span id="lg-name"></span><span id="lg-max"></span></div>
        </div>
        <div id="playbar">
          <button id="btn-play">pause</button>
          <input type="range" id="rng-frame" min="0" max="0" value="0"/>
          <select id="sel-speed">
            <option value="0.5">0.5x</option>
            <option value="1" selected>1x</option>
            <option value="2">2x</option>
            <option value="4">4x</option>
          </select>
        </div>
        <div id="tlabel"></div>
        <div id="meta"><div class="mtitle">parameters</div><table id="meta-table"></table></div>
        <div id="hint">drag orbit &middot; wheel zoom &middot; right-drag pan &middot; space play</div>
      </div>
      <script id="sim-data" type="application/json">
    HTML

  -> .html_data_close
    <<~HTML
      </script>
      <script type="module">
    HTML

  -> .html_tail
    <<~HTML
      </script>
      </body>
      </html>
    HTML

  # The viewer application (JS and CSS) ships as data assets beside the
  # vendored three.js — multi-KB heredocs trip a packed-lexer bug in the
  # fast tokenizer (see TODO.md: heredoc content mis-scan), and separate
  # files keep the app editable/lintable as plain JS anyway.
  -> .asset(name)
    path = Plot3D.asset_root() + "/" + name
    data = read_file(path)
    if data == nil
      raise "Plot3D: asset not found at [path] (set TUNGSTEN_HOME or TUNGSTEN_VIEWER3D_ASSETS)"
    data

  -> .app_css
    Plot3D.asset("viewer.css")

  -> .app_js
    Plot3D.asset("viewer.js")

+ Plot
  # Open a gridded dataset in the interactive 3D web viewer.
  # See Plot3D for the spec schema.
  -> .viewer3d(spec, path = "/tmp/plot3d_viewer.html")
    html = Plot3D.render(spec)
    Plot3D.write_and_open(path, html)
