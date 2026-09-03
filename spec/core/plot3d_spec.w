# Plot3D — self-contained three.js viewer export for gridded data (core/plot3d.w).
#
# METAL LANE (GPU-adjacent visualisation module). Nothing here opens a browser:
# `write_and_open` shells out to `open`, so it is not exercised. What is covered
# is the CPU half — asset resolution, 8-bit field quantization, JSON assembly and
# the static HTML template pieces.
#
# Run:
#   bin/tungsten run --interpret spec/core/plot3d_spec.w
#   bin/tungsten -o /tmp/plot3d_spec spec/core/plot3d_spec.w && /tmp/plot3d_spec

use core/plot3d

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- asset resolution ----
root = Plot3D.asset_root
check("asset_root is a string", type(root) == "String")
check("asset_root points at a viewer3d directory", root.include?("data/viewer3d"))
check("asset_root is stable", Plot3D.asset_root == root)

# ---- json_escape: backslashes first, then quotes ----
check("json_escape leaves plain text alone", Plot3D.json_escape("plain") == "plain")
check("json_escape escapes a quote", Plot3D.json_escape("a\"b") == "a\\\"b")
check("json_escape escapes a backslash", Plot3D.json_escape("a\\b") == "a\\\\b")
check("json_escape of the empty string", Plot3D.json_escape("") == "")
check("json_escape stringifies non-strings", Plot3D.json_escape(12) == "12")

# ---- quantize: min/max into out, 8-bit scaled samples into dst ----
src = f64[4]
src[0] = ~0.0
src[1] = ~1.0
src[2] = ~2.0
src[3] = ~4.0
dst = u8[4]
out = f64[2]
check("quantize returns 0", Plot3D.quantize(src, dst, 4, out) == 0)
check("quantize records the minimum", out[0] == ~0.0)
check("quantize records the maximum", out[1] == ~4.0)
check("the minimum quantizes to 0", dst[0] == 0)
check("the maximum quantizes to 255", dst[3] == 255)
# round(v/4 · 255): 1 -> 64, 2 -> 128
check("quantize rounds to nearest", dst[1] == 64 && dst[2] == 128)
check("quantize is monotone", dst[0] < dst[1] && dst[1] < dst[2] && dst[2] < dst[3])

# A constant field has zero span: the guard substitutes 1.0 so nothing divides by zero.
flat = f64[3]
flat[0] = ~7.0
flat[1] = ~7.0
flat[2] = ~7.0
flat_dst = u8[3]
flat_out = f64[2]
Plot3D.quantize(flat, flat_dst, 3, flat_out)
check("a constant field reports its value as both bounds",
      flat_out[0] == ~7.0 && flat_out[1] == ~7.0)
check("a constant field quantizes to 0", flat_dst[0] == 0 && flat_dst[2] == 0)

# ---- pack_field: quantize plus base64 ----
packed = Plot3D.pack_field(src)
check("pack_field carries the minimum", packed["min"] == ~0.0)
check("pack_field carries the maximum", packed["max"] == ~4.0)
check("pack_field base64-encodes the samples", packed["b64"] == "AECA/w==")
check("pack_field round-trips through Base64", Base64.decode(packed["b64"]).size == 4)
check("pack_field is a three-key hash", packed.size == 3)

# ---- frames_json: an array of {t, fields} objects ----
frames = [{:t => ~0.0, :fields => {"rho" => packed}}]
check("frames_json emits one object per frame",
      Plot3D.frames_json(frames, ["rho"]) ==
      "\[{\"t\":0,\"fields\":{\"rho\":{\"b64\":\"AECA/w==\",\"min\":0,\"max\":4}}}\]")
check("frames_json of no frames is an empty array", Plot3D.frames_json([], ["rho"]) == "\[\]")
two = [{:t => ~0.0, :fields => {"rho" => packed}}, {:t => ~1.0, :fields => {"rho" => packed}}]
check("frames_json separates frames with a comma",
      Plot3D.frames_json(two, ["rho"]).include?("}},{\"t\":1"))

# ---- static template pieces ----
check("html_head opens the document", Plot3D.html_head.include?("<!doctype html>"))
check("html_head ends at the title", Plot3D.html_head.include?("<title>"))
check("html_importmap_open closes the title", Plot3D.html_importmap_open.include?("</title>"))
check("html_importmap_open declares the three import", Plot3D.html_importmap_open.include?("\"three\":"))
check("html_importmap_close closes the map", Plot3D.html_importmap_close == "\"}}</script>")
check("html_body_open has the app mount point", Plot3D.html_body_open.include?("<div id=\"app\">"))
check("html_body_open has the control panel", Plot3D.html_body_open.include?("id=\"sel-cmap\""))
check("html_body_open opens the data script", Plot3D.html_body_open.include?("id=\"sim-data\""))
check("html_data_close switches to the module script",
      Plot3D.html_data_close == "</script>\n<script type=\"module\">")
check("html_tail closes the document", Plot3D.html_tail == "</script>\n</body>\n</html>")

# ---- spec_json / render need JSON.encode over an Array and the vendored assets ----
# BUG: `JSON.encode(["rho"])` raises "Undefined variable or method 'item'" on the native
# interpreter (an Array argument only; a Hash encodes fine). Plot3D.spec_json calls it for
# spec[:fields], so spec_json and render are compiled-only until that is fixed.
# Repro: printf '<< JSON.encode(["a"])\n' > /tmp/j.w && bin/tungsten run --interpret /tmp/j.w
spec = {:kind => "surface", :title => "T\"x", :dims => [2, 1, 1],
        :domain => [~1.0, ~1.0, ~1.0], :fields => ["rho"], :frames => frames,
        :mask => nil, :meta => {"a" => "b"}}
json_ok = true
begin
  JSON.encode(["rho"])
rescue e
  json_ok = false

if json_ok
  encoded = Plot3D.spec_json(spec)
  check("spec_json emits the kind", encoded.include?("\"kind\":\"surface\""))
  check("spec_json escapes the title", encoded.include?("\"title\":\"T\\\"x\""))
  check("spec_json emits the dims triple", encoded.include?("\"dims\":\[2,1,1\]"))
  check("spec_json emits the domain triple", encoded.include?("\"domain\":\[1,1,1\]"))
  check("spec_json emits the field list", encoded.include?("\"fields\":\[\"rho\"\]"))
  check("a nil mask becomes null", encoded.include?("\"mask\":null"))
  check("an absent live URL becomes false", encoded.include?("\"live\":false"))
  check("absent params become null", encoded.include?("\"params\":null"))
  check("spec_json embeds the meta table", encoded.include?("\"meta\":{\"a\":\"b\"}"))
  check("spec_json embeds the frames", encoded.include?("\"frames\":\[{\"t\":0"))
  check("spec_json is a single JSON object",
        encoded.slice(0, 1) == "{" && encoded.slice(encoded.size - 1, 1) == "}")

  live = {:kind => "volume", :title => "v", :dims => [1, 1, 1],
          :domain => [~1.0, ~1.0, ~1.0], :fields => ["rho"], :frames => [],
          :mask => "AAA=", :meta => {}, :live => "/run", :params => {"n" => 4}}
  live_json = Plot3D.spec_json(live)
  check("a mask is emitted as a base64 string", live_json.include?("\"mask\":\"AAA=\""))
  check("a live URL is emitted as a string", live_json.include?("\"live\":\"/run\""))
  check("params are JSON-encoded", live_json.include?("\"params\":{\"n\":4}"))
  check("kind is carried through", live_json.include?("\"kind\":\"volume\""))
else
  << "SKIP Plot3D.spec_json (interpreter: JSON.encode of an Array is broken)"

# ---- the vendored viewer assets, when they are reachable ----
assets_ok = true
begin
  Plot3D.three_source
rescue e
  assets_ok = false

if assets_ok
  check("three.js is a non-empty source", Plot3D.three_source.size > 1000)
  check("viewer.css is readable", Plot3D.app_css.size > 0)
  check("viewer.js is readable", Plot3D.app_js.size > 0)
  if json_ok
    html = Plot3D.render(spec)
    check("render produces one HTML document", html.include?("<!doctype html>") && html.include?("</html>"))
    check("render inlines the spec JSON", html.include?("\"kind\":\"surface\""))
    check("render inlines three.js as a data URL", html.include?("data:text/javascript;base64,"))
else
  << "SKIP Plot3D asset loading (data/viewer3d not reachable from [root])"

<< "ALL PASS plot3d_spec ([passed.load()] checks)"
