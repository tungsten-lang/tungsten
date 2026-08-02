# Canvas, clipping, sampled-series, and projection checks.
# Run both ways from the repository root:
#   bin/tungsten run bits/tungsten-drawille/spec/canvas_spec.w
#   bin/tungsten compile bits/tungsten-drawille/spec/canvas_spec.w --out /tmp/drawille-canvas-spec

use ../lib/drawille

-> drawille_check(name, condition)
  if !condition
    raise "FAIL " + name
  << "PASS " + name

canvas = Canvas.new(4, 2)
drawille_check("canvas.pixel_width", canvas.pixel_width == 8)
drawille_check("canvas.pixel_height", canvas.pixel_height == 8)
canvas.set(0, 0)
drawille_check("canvas.utf8_braille", canvas.cell_char(0, 0) == "\u2801")

horizontal = canvas.clip_line(-1000000, 3, 1000000, 3)
drawille_check("canvas.clip.horizontal", horizontal.to_s == "\[0, 3, 7, 3\]")
drawille_check("canvas.clip.reject", canvas.clip_line(-8, 0, -2, 7).size == 0)
canvas.clear.line(-1000000, 3, 1000000, 3)
drawille_check("canvas.clipped_line.draws", !canvas.cell_empty?(0, 0))

bounded = Canvas.new(1000000, 1000000)
drawille_check("canvas.cols_bounded", bounded.cols == 240)
drawille_check("canvas.rows_bounded", bounded.rows == 100)

series = DrawilleInspection.render_series([~0.0, ~1.0, ~0.0], 0, 2, 20, 6, false)
drawille_check("series.rendered", series.size > 20)
drawille_check("series.labels", series.include?("0") && series.include?("2"))
auc = DrawilleInspection.render_series([~-1.0, ~1.0, ~-1.0], -1, 1, 20, 6, true)
drawille_check("series.auc", auc.size > series.size / 2)

projected = DrawilleProjection3D.project(~1.0, ~2.0, ~3.0)
drawille_check("projection.dimension", projected.size == 3)
drawille_check("projection.numeric", projected[0].class_name == "Float")
drawille_check(
  "numbers.reject_nonfinite",
  DrawilleNumbers.numeric(Math.exp(~1000.0)).class_name == "Nil")

<< "drawille canvas spec: all checks passed"
