# Plot — zero-dependency terminal sparklines, heatmaps and line charts (core/plot.w).
#
# `array_plot`, `grid_plot` and `line` print their rendering as well as returning
# it, so this spec's output interleaves a handful of small charts with the PASS
# lines. Every assertion is on the returned string.
#
# Run:
#   bin/tungsten run --interpret spec/core/plot_spec.w
#   bin/tungsten -o /tmp/plot_spec spec/core/plot_spec.w && /tmp/plot_spec

use core/plot

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- the ramp ----
check("ten spark levels", Plot.spark_chars.size == 10)
check("spark ramp", Plot.spark_chars == [".", ":", "-", "=", "+", "*", "#", "%", "@", "#"])
check("the ramp starts at the lightest glyph", Plot.spark_chars[0] == ".")

# ---- sparkline: min-max normalise, then index the ramp ----
check("empty input is the empty string", Plot.sparkline([]) == "")
check("a single point is the lowest level", Plot.sparkline([~1.0]) == ".")
check("two points span the ramp", Plot.sparkline([~0.0, ~1.0]) == ".#")
check("the midpoint lands mid-ramp", Plot.sparkline([~0.0, ~0.5, ~1.0]) == ".+#")
check("one glyph per sample", Plot.sparkline([~0.0, ~0.5, ~1.0]).size == 3)
# floor(t·9) over ten evenly spaced samples walks the whole ramp.
check("an even ramp walks every level",
      Plot.sparkline([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) == ".:-=+*#%@#")
check("a constant series is all lowest (zero span guarded)",
      Plot.sparkline([~5.0, ~5.0, ~5.0]) == "...")
check("normalisation is scale-free", Plot.sparkline([~-3.0, ~0.0, ~3.0]) == ".+#")
check("descending input", Plot.sparkline([10, 1]) == "#.")
check("integers are coerced to float", Plot.sparkline([0, 1]) == Plot.sparkline([~0.0, ~1.0]))

# ---- heatmap: one glyph per cell, one newline per row ----
check("an empty grid is the empty string", Plot.heatmap([]) == "")
check("a one-row heatmap", Plot.heatmap([[~0.0, ~1.0]]) == " @\n")
check("heatmap length is cells plus newlines", Plot.heatmap([[~0.0, ~1.0]]).size == 3)
check("a two-row heatmap", Plot.heatmap([[~0.0, ~1.0], [~1.0, ~0.0]]) == " @\n@ \n")
check("a constant grid is all lowest", Plot.heatmap([[~1.0, ~1.0], [~1.0, ~1.0]]) == "  \n  \n")
check("a custom ramp is honoured", Plot.heatmap([[~0.0, ~1.0]], "ab") == "ab\n")
check("a one-glyph ramp collapses", Plot.heatmap([[~0.0, ~1.0]], "z") == "zz\n")

# ---- array_plot: sparkline of a plain Array, printed and returned ----
check("array_plot returns the sparkline", Plot.array_plot([1, 5, 10]) == ".+#")
check("array_plot of an empty array", Plot.array_plot([]) == "")

# ---- line: a rows × cols character canvas with '*' markers ----
canvas = Plot.line([~0.0, ~1.0], [~0.0, ~1.0], 4, 3)
check("line has one newline per row", canvas.size == 15)
check("line plots the endpoints on opposite corners", canvas == "   *\n    \n*   \n")
check("line of an empty series is the empty string", Plot.line([], [], 4, 3) == "")
# A constant y series has zero span; the guard substitutes 1.0 and both points land on row 0.
check("a flat series does not divide by zero",
      Plot.line([~0.0, ~1.0], [~2.0, ~2.0], 3, 2) == "* *\n   \n")
check("line respects the requested size", Plot.line([~0.0, ~1.0], [~0.0, ~1.0], 5, 2).size == 12)

<< "ALL PASS plot_spec ([passed.load()] checks)"
