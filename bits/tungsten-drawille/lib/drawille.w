# tungsten-drawille — Unicode braille plotting for Tungsten.
#
# A port of asciimoo/drawille (https://github.com/asciimoo/drawille). The
# braille `Canvas` gives 2×4 sub-character resolution; `Plot` renders a
# polynomial over a range as a line chart with dimmed `-` / `|` axes.
#
# Library use:
#     use bits/tungsten-drawille/lib/drawille
#     << plot_poly(1, 100, [3, 2])           # 2x + 3
#
# CLI:
#     drawille <lo> <hi> <c0> [c1 c2 …]     # cₖ = coefficient of xᵏ
#     drawille 1 100 3 2                     # plot 2x + 3 over 1..100

use canvas
use plot
use argand

# Plot P(x) = Σ coeffs[k]·xᵏ over [lo, hi]; returns the chart string. With
# `fill`, shades the area under the curve (the integral / AUC highlight);
# `margin` adds that many x-units of context on each side of the range; `zeros`
# is the list of real roots (each as x·10) to mark on a number line below.
-> plot_poly(lo, hi, coeffs, fill = false, margin = 0, zeros = [], cols = 70, rows = 15)
  Plot.render(lo, hi, coeffs, cols, rows, fill, margin, zeros)

# Argand mode: drawille --argand [--scale S] [--rows N] <re0> <im0> [<op> <re> <im> …]
# Components are integers pre-scaled by S (so 0.8 arrives as 800, S=1000); the
# ops are the operators between complex operands. All complex math is computed
# in Tungsten Complex<f64> by the bit (see lib/argand.w).
-> run_argand(args)
  i = 1
  scale = 1000
  rows = 15
  rot = 0
  while i < args.size() && args[i].starts_with?("--")
    if args[i] == "--scale"
      scale = args[i + 1].to_i()
      i += 2
    elsif args[i] == "--rows"
      rows = args[i + 1].to_i()
      i += 2
    elsif args[i] == "--rotate"
      rot = args[i + 1].to_i()
      i += 2
    else
      i += 1
  re_ints = []
  im_ints = []
  ops = []
  if i + 1 < args.size()
    re_ints.push(args[i].to_i())
    im_ints.push(args[i + 1].to_i())
    i += 2
  while i + 3 <= args.size()
    ops.push(args[i])
    re_ints.push(args[i + 1].to_i())
    im_ints.push(args[i + 2].to_i())
    i += 3
  print(Argand.render(re_ints, im_ints, ops, scale, rows, rot))

# CLI entry: drawille [--auc] [--margin N] [--zeros z1,z2,…] <lo> <hi> <c0> [c1 …]
#        or: drawille --argand …  (Argand-plane complex viz; see run_argand)
args = argv()
if args.size() > 0 && args[0] == "--argand"
  run_argand(args)
else
  fill = false
  margin = 0
  rows = 15
  zeros = []
  i = 0
  while i < args.size() && args[i].starts_with?("--")
    if args[i] == "--auc"
      fill = true
      i += 1
    elsif args[i] == "--margin"
      margin = args[i + 1].to_i()
      i += 2
    elsif args[i] == "--rows"
      rows = args[i + 1].to_i()
      i += 2
    elsif args[i] == "--zeros"
      args[i + 1].split(",").each -> (z)
        zeros.push(z.to_i())
      i += 2
    else
      i += 1
  if args.size() - i >= 3
    lo = args[i].to_i()
    hi = args[i + 1].to_i()
    coeffs = []
    j = i + 2
    while j < args.size()
      coeffs.push(args[j].to_i())
      j += 1
    print(plot_poly(lo, hi, coeffs, fill, margin, zeros, 70, rows))
