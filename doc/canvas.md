# Canvas: native vector drawing

`Canvas` (`core/canvas.w`) draws vector paths, gradients, strokes, images and
text straight into an RGBA bitmap through CoreGraphics, CoreText and ImageIO
(`runtime/quartz.c`). It is the native replacement for building an `Svg` and
rasterizing it with `rsvg-convert` (`Svg#write_png`): the same shapes and
attribute hashes, about 20x faster per 1080p frame, with real text metrics and
the colour space embedded in the output.

It is compiled-only and macOS-only, like Metal. The tree-walking interpreter
stops with "Canvas is compiled-only"; on other targets the bridge is a stub, so
programs link and `Canvas.available?` is false. Any `Canvas` call there raises
"Canvas needs macOS CoreGraphics/CoreText".

```tungsten
c = Canvas.new(1280, 720, scale: 2)            # 1280 x 720 user units, 2560 x 1440 pixels
c.clear("#0b0e13")
field = Canvas.radial(0.62, 0.45, 0.75, [[0, "#1c2533"], [1, "#0b0e13"]], units: :bbox)
c.rect(0, 0, 1280, 720, fill: field)
c.image("panels/s17.png", 0, -18, 1780, 755, fit: :slice)
c.rect(46, 72, 206, 100, fill: "#ff8a5b", rx: 50)
c.text(56, 380, "ALL IS", size: 160, weight: "bold", fill: "#fff",
       stroke: "#0b0e13", width: 9, linejoin: "round", spacing: -4)
c.write_png("thumb.png")
c.close
```

## Porting from Svg

Shapes take the same positional arguments and attribute keys as `Svg`: `rect`,
`circle`, `ellipse`, `line`, `polyline`, `polygon`, `path` (SVG path data), `text`
and `text_runs`. The attribute keys are `fill`, `stroke`, `width` (stroke width),
`opacity`, `fill_opacity`, `stroke_opacity`, `dash` (`"10 8"` or `[10, 8]`),
`dash_offset`, `linecap`, `linejoin`, `miter`, `rx`/`ry`, `rule` (`:evenodd`)
and `blend`.

SVG defaults apply: fill is black, stroke is none, and `line` and `polyline`
are unfilled. Group `opacity` composites fill and stroke together, as SVG does,
so a stroke over its own fill does not double up.

| Svg | Canvas |
| --- | --- |
| `s.linear_gradient("g", 0, 0, 1, 0, stops)` + `fill: "url(#g)"` | `fill: Canvas.linear(0, 0, 1, 0, stops, units: :bbox)` |
| `<image … preserveAspectRatio="xMidYMid slice"/>` | `c.image(path, x, y, w, h, fit: :slice)` |
| `paint-order="stroke"` on text | the default whenever text has a stroke |
| `transform="rotate(30 cx cy)"` | `c.save; c.rotate(30 * π / 180, cx, cy); …; c.restore` |
| `clip_rect` + `clip: id` | `c.save; c.clip_rect(x, y, w, h); …; c.restore` |
| `est_w(s, size)` width estimates | `c.text_width(s, size: size, weight: "bold")` |

Gradient stops are `[[offset, colour], …]` or `[[offset, colour, opacity], …]`.
With `units: :user` (the default), the coordinates are in user space. With
`units: :bbox`, they are fractions of the painted shape's bounding box, which
is SVG's default. `Canvas.radial(cx, cy, r, stops, fx:, fy:, fr:)` takes an
optional focal circle.

## API

| Call | Does |
| --- | --- |
| `Canvas.new(w, h, scale:, space:, depth:, manage:, background:)` | a canvas of `w` x `h` user units |
| `Canvas.available?` | true when the native bridge is built (macOS) |
| `Canvas.load_image(path)` | a `CanvasImage`, decoded once and cached by path |
| `Canvas.linear(x1, y1, x2, y2, stops, opts)`, `Canvas.radial(cx, cy, r, stops, opts)` | gradients |
| `Canvas.font_name(family, weight, style)` | the PostScript face a CSS family list resolves to |
| `Canvas.stats`, `Canvas.purge_images` | native memory in use; drop the image cache |
| `rect circle ellipse line polyline polygon path text text_runs` | shapes, as `Svg` |
| `image(src, x, y, w, h, fit:, align:, opacity:, quality:, src:)` | draw a path, a `CanvasImage` or another `Canvas` |
| `measure_text(s, opts)`, `text_width(s, opts)` | the advance, ascent, descent, leading and ink box |
| `begin_path move_to line_to quad_to curve_to arc arc_to close_path` | low-level path building |
| `add_rect add_round_rect add_ellipse add_path add_points` | append shapes or SVG path data to the path |
| `paint(opts)`, `fill(paint, opts)`, `stroke(paint, opts)`, `clip(rule)` | paint or clip the current path |
| `path_bounds`, `contains?(x, y, rule)` | geometry of the current path |
| `clip_rect`, `clip_path(d)` | clip, undone by `restore` |
| `save restore reset translate scale_by rotate transform ctm` | graphics state and transforms |
| `alpha=`, `blend=`, `quality=`, `antialias=`, `begin_layer(opacity)`, `end_layer` | compositing |
| `clear(colour)`, `pixel(px, py)`, `bytes(premultiplied)`, `to_raster(bg)` | pixels |
| `write_png(path)`, `write(path, quality:)`, `encode(type)` | PNG, JPEG, TIFF or HEIC, ICC embedded |
| `data_pointer`, `stride`, `pixel_width`, `pixel_height`, `depth`, `snapshot` | buffer access for encoders |
| `close`, `closed?` | release the pixel buffer |

## Colours and colour spaces

A colour can be given as:

- a CSS string: `"#rgb"`, `"#rrggbb"`, `"#rrggbbaa"`, `"rgb()"`, `"rgba()"`, or one
  of the 148 named colours
- a `Color` value, such as the literal `#FF8A5B` or `Color.rgb`
- a `0xRRGGBB` integer
- an `[r, g, b]` or `[r, g, b, a]` array of 0..1 components

`space:` selects the canvas colour space. It is one of `"srgb"` (the default),
`"rec709"`, `"display_p3"`, `"linear_srgb"`, `"extended_srgb"`,
`"extended_linear_srgb"`, `"linear_display_p3"`, `"extended_display_p3"`,
`"rec2020"`, `"linear_rec2020"`, `"dci_p3"`, `"adobe_rgb"` or `"acescg"`.
`depth:` is 8 (the default), 16, `"half"` or `"float"`. Use 16-bit or float
depth with linear spaces, to avoid banding.

`manage:` decides how inputs are read:

- `manage: false` (the default): colours and image pixels are code values in
  the canvas space. This is what the SVG → rsvg → ffmpeg pipeline did, so a
  `"rec709"` canvas reproduces today's frames with an honest tag.
- `manage: true`: colours are sRGB (CSS semantics), and images go through their
  embedded profiles. CoreGraphics colour-matches both into the canvas space.

PNGs carry the canvas space: an `sRGB` chunk for sRGB, and an ICC profile
(`iCCP`) for every other space.

## Text

Text options:

- `size`
- `family`: a CSS list such as `"Helvetica Neue, Helvetica, sans-serif"`; the
  generic families `sans-serif`, `serif`, `monospace`, `math` and `system-ui`
  are recognized
- `weight`: `"bold"`, 100–900
- `style`: `"italic"`
- `anchor`: start, middle or end
- `baseline`: alphabetic, middle, hanging or bottom
- `spacing`: letter spacing

A face is chosen by CSS-style matching on weight, italic and width; a PostScript
name such as `"Menlo-Bold"` also works. CoreText falls back per glyph, so
Greek, `√`, `²`, `—`, full-width `＜＞` and emoji render whatever the family.

`text_runs(x, y, [[string, opts], …], opts)` sets mixed styles on one baseline.
A run takes `dx` for a gap and `shift` (user units, `"super"` or `"sub"`) for a
raised or lowered run. All strokes are drawn before any fill.

## Video frames

Keep one canvas for the whole render, and call `clear` (and `reset`, if a frame
leaves transforms or clips behind) at the top of each frame. Hand the pixels on
with `bytes`, `data_pointer` and `stride`, or `write_png`.

Images are decoded once and converted once to the canvas's colour space and
pixel format. A still drawn on 10,000 frames costs one decode. The cache keeps
up to 4 GiB of decoded pixels, keyed by path and mtime. A canvas's laid-out
text lines and gradients are cached per canvas, because frames repeat them.

The runtime has no finalizers, so `close` a canvas you are done with. The pixel
buffer is an anonymous mmap and returns to the OS immediately.

Native encoders in the runtime can take a canvas without copying through the C
API in `runtime/quartz.h`. `w_cg_canvas_buffer(handle, &info)` returns the
premultiplied RGBA buffer, its stride, depth and colour space.

## How it is built

- **ccall surface:** `runtime/quartz.c` exposes 57 `w_cg_*` ccalls, listed
  once with their arities in `W_CG_CCALLS` in `quartz.h`.
- **Arguments:** every argument is a boxed WValue. Numbers arrive as Float,
  Int, Decimal or Rational and are coerced in C, so `10`, `2.5` and `~2.5` all
  work.
- **Handles:** canvases and images are generation-checked integer handles, so
  a closed handle raises instead of touching freed memory.
- **Link gate:** the compiler links `quartz.c` only when a program's IR
  references `@w_cg_` (`ll_needs_quartz` in `compiler/lib/driver/ir.w`). On macOS
  it adds `-framework CoreGraphics CoreText ImageIO CoreFoundation`. A Canvas
  program pulls in neither Metal nor AppKit, and a Metal program never links
  CoreText.
- **Other targets:** the same file compiles to raising stubs, generated from
  that list.

## Performance

From `benchmarks/canvas/run.sh`, a `--release` build on an Apple M5 Max. Each
lane draws 60 frames of a 1920 x 1080 picture: a radial field, a full-frame
still, 40 shapes, dashed curves, a translucent panel, and six text runs with
outline strokes and Unicode.

| Lane | Frames/s | ms/frame |
| --- | --- | --- |
| Canvas, draw only (what an encoder reads) | 126.2 | 7.9 |
| Canvas + `write_png` | 21.9 | 45.8 |
| `Svg` + `write_png` (rsvg-convert) | 5.6 | 178.4 |

The native frame and rsvg's PNG of the same frame differ by 0.35/255 per
channel on average. PNG encoding (ImageIO's deflate) dominates the PNG lane.

## Limits

- No blur or glow filters yet: `Svg#blur_filter` and `glow_filter` have no
  Canvas counterpart.
- No variable-font axes beyond the named instances.
- No text on a path, and no multi-line layout.
- Paths are interpreted under the transform in effect when they are painted,
  not when their points were added.
- The drawille bit (`bits/tungsten-drawille`) defines its own terminal
  `Canvas`. Programs that load it get that class, as with `Plot`.
