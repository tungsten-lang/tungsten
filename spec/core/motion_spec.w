# Motion, Ease, Paint, Narration (core/motion.w) and the Svg additions they draw with.
#
# Run:
#   bin/tungsten run --interpret spec/core/motion_spec.w
#   bin/tungsten -o /tmp/motion_spec spec/core/motion_spec.w && /tmp/motion_spec

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b)
  (a - b).abs < ~0.000001

# ---- easing: every curve maps 0 → 0 and 1 → 1 and clamps outside ----
curves = [Ease.linear(~0.0), Ease.smooth(~0.0), Ease.smoother(~0.0), Ease.in_quad(~0.0), Ease.out_quad(~0.0),
          Ease.in_out_quad(~0.0), Ease.in_cubic(~0.0), Ease.out_cubic(~0.0), Ease.in_out_cubic(~0.0),
          Ease.out_quart(~0.0), Ease.out_expo(~0.0), Ease.in_out_sine(~0.0), Ease.out_back(~0.0)]
check("every easing starts at 0", curves.all? -> (v) near(v, ~0.0))
ends = [Ease.linear(~1.0), Ease.smooth(~1.0), Ease.smoother(~1.0), Ease.in_quad(~1.0), Ease.out_quad(~1.0),
        Ease.in_out_quad(~1.0), Ease.in_cubic(~1.0), Ease.out_cubic(~1.0), Ease.in_out_cubic(~1.0),
        Ease.out_quart(~1.0), Ease.out_expo(~1.0), Ease.in_out_sine(~1.0), Ease.out_back(~1.0)]
check("every easing ends at 1", ends.all? -> (v) near(v, ~1.0))
check("easing clamps below 0", near(Ease.out_cubic(~-3.0), ~0.0))
check("easing clamps above 1", near(Ease.smooth(~7.0), ~1.0))
check("smoothstep is symmetric at the midpoint", near(Ease.smooth(~0.5), ~0.5))
check("in-out cubic is symmetric at the midpoint", near(Ease.in_out_cubic(~0.5), ~0.5))
check("out-cubic leads linear", Ease.out_cubic(~0.3) > ~0.3)
check("in-cubic lags linear", Ease.in_cubic(~0.3) < ~0.3)
check("out-back overshoots", Ease.out_back(~0.7) > ~1.0)

# ---- timing ----
check("ramp is 0 before its start", near(Motion.ramp(~1.0, ~2.0, ~1.0), ~0.0))
check("ramp is halfway mid-ramp", near(Motion.ramp(~2.5, ~2.0, ~1.0), ~0.5))
check("ramp is 1 after its end", near(Motion.ramp(~9.0, ~2.0, ~1.0), ~1.0))
check("a zero-width ramp is a step", near(Motion.ramp(~2.0, ~2.0, ~0.0), ~1.0) && near(Motion.ramp(~1.9, ~2.0, ~0.0), ~0.0))
check("window is fully visible in the middle", near(Motion.window(~3.0, ~1.0, ~5.0), ~1.0))
check("window has faded out by its end", near(Motion.window(~5.0, ~1.0, ~5.0), ~0.0))
check("window has not started before its start", near(Motion.window(~0.5, ~1.0, ~5.0), ~0.0))
check("stagger delays the i-th item", near(Motion.stagger(~1.5, ~1.0, 2, ~0.25, ~0.5), ~0.0) && near(Motion.stagger(~2.0, ~1.0, 2, ~0.25, ~0.5), ~1.0))
check("pulse peaks at half period", near(Motion.pulse(~1.0, ~2.0), ~1.0))
check("lerp", near(Motion.lerp(~10.0, ~20.0, ~0.25), ~12.5))

# ---- polylines ----
route = [[~0.0, ~0.0], [~3.0, ~0.0], [~3.0, ~4.0]]
check("polyline length", near(Motion.length(route), ~7.0))
mid = Motion.point_at(route, ~0.5)
check("point at half the arc length", near(mid[0], ~3.0) && near(mid[1], ~0.5))
check("heading on the second leg points down +y", near(Motion.heading_at(route, ~0.9)[1], ~1.0))
part = Motion.partial(route, ~3.0 / ~7.0)
check("partial stops at the corner", part.size == 2 && near(part[1][0], ~3.0) && near(part[1][1], ~0.0))
check("partial(0) is the start point only", Motion.partial(route, ~0.0).size == 1)
check("partial(1) is the whole polyline", near(Motion.length(Motion.partial(route, ~1.0)), ~7.0))
check("slice length matches the fraction", near(Motion.length(Motion.slice(route, ~0.25, ~0.75)), ~3.5))
sh = Motion.shorten([~0.0, ~0.0], [~10.0, ~0.0], ~1.0, ~2.0)
check("shorten trims both ends", near(sh[0][0], ~1.0) && near(sh[1][0], ~8.0))
cv = Motion.curve([~0.0, ~0.0], [~10.0, ~0.0], ~0.0, 4)
check("a zero bend is straight", cv.size == 5 && near(cv[2][1], ~0.0) && near(cv[4][0], ~10.0))
bow = Motion.curve([~0.0, ~0.0], [~10.0, ~0.0], ~0.25, 4)
check("a positive bend bows to the left of travel", bow[2][1] > ~0.0)
head = Motion.arrow([~10.0, ~0.0], [~1.0, ~0.0], ~4.0)
check("arrowhead tip and base", head.size == 3 && near(head[0][0], ~10.0) && near(head[1][0], ~6.0))
check("circle points", Motion.circle_points(~0.0, ~0.0, ~1.0, 8).size == 8)

# ---- numbers ----
check("commas", Motion.commas(22020096) == "22,020,096")
check("commas below a thousand", Motion.commas(504) == "504")
check("commas on negatives", Motion.commas(-1234) == "-1,234")
check("fixed rounds", Motion.fixed(~3.14159, 2) == "3.14")
check("fixed pads", Motion.fixed(~2.5, 3) == "2.500")
check("fixed with no places", Motion.fixed(~72.46, 0) == "72")
check("fixed keeps the sign", Motion.fixed(~-0.25, 1) == "-0.3" || Motion.fixed(~-0.25, 1) == "-0.2")
check("pad", Motion.pad(7, 5) == "00007")

# ---- colour ----
check("hex", Paint.hex(255, 128, 0) == "#ff8000")
check("rgb parses six digits", Paint.rgb("#4fd1ff") == [79, 209, 255])
check("rgb parses three digits", Paint.rgb("#fff") == [255, 255, 255])
check("mix halfway", Paint.mix("#000000", "#ffffff", ~0.5) == "#808080")
check("mix clamps", Paint.mix("#000000", "#ffffff", ~2.0) == "#ffffff")
check("ramp endpoints", Paint.ramp(["#000000", "#ff0000", "#ffffff"], ~1.0) == "#ffffff")
check("ramp middle stop", Paint.ramp(["#000000", "#ff0000", "#ffffff"], ~0.5) == "#ff0000")

# ---- narration timeline ----
n = Narration.new(~0.5)
n.read_script("# title\n## s01\nFirst sentence here. Second one!\n## s02\nOnly one.\n")
n.read_durations("segment,seconds\ns01,4.0\ns02,2.0\n")
check("two segments", n.count == 2 && n.ids == ["s01", "s02"])
check("segment text is joined", n.texts[0] == "First sentence here. Second one!")
check("scene lengths add the pause", near(n.length(0), ~4.5) && near(n.total, ~7.0))
check("scene starts accumulate", near(n.start(1), ~4.5))
check("scene_at", n.scene_at(~4.4) == 0 && n.scene_at(~4.6) == 1)
check("sentences", n.sentences(0) == ["First sentence here.", "Second one!"])
check("first cue is at zero", near(n.cue(0, 0), ~0.0))
check("second cue by character share", near(n.cue(0, 1), ~4.0 * ~21.0 / ~32.0))
check("cue past the end is the clip length", near(n.cue(0, 5), ~4.0))
check("word cue", near(n.word_cue(0, "Second"), ~4.0 * ~21.0 / ~32.0))
check("srt time", Narration.srt_time(~3725.5) == "01:02:05,500")
srt = n.srt
check("srt numbers every caption", srt.includes?("1\n00:00:00,000 --> ") && srt.includes?("\n3\n00:00:04,500 --> "))
check("wrap2 splits long captions", Narration.wrap2("aaaa bbbb cccc dddd", 10) == "aaaa bbbb\ncccc dddd")

# ---- Svg additions ----
s = Svg.new(100, 50)
s.linear_gradient("g", 0, 0, 0, 1, [[0, "#000000", 1], [1, "#ffffff", ~0.5]])
s.glow_filter("glow", 4)
s.clip_rect("c", 0, 0, 50, 50)
s.rect(0, 0, 100, 50, {fill: "url(#g)", rx: 6, clip: "c"})
s.circle(10, 10, 3, {fill: "#4fd1ff", filter: "glow", fill_opacity: ~0.5, stroke_opacity: ~0.25})
s.text_runs(5, 20, [["a ", {}], ["b", {fill: "#ff0000", weight: "bold"}]], {size: 12, spacing: 2})
s.ellipse(50, 25, 10, 5, {stroke: "#fff", linejoin: "round", dash_offset: 3})
out = s.to_s
check("linear gradient definition", out.includes?("<linearGradient id=\"g\"") && out.includes?("stop-opacity=\"0.5\""))
check("glow filter definition", out.includes?("<filter id=\"glow\"") && out.includes?("feGaussianBlur"))
check("clip rect definition", out.includes?("<clipPath id=\"c\">"))
check("rounded, clipped rect", out.includes?("rx=\"6\"") && out.includes?("clip-path=\"url(#c)\""))
check("filter and opacities", out.includes?("filter=\"url(#glow)\"") && out.includes?("fill-opacity=\"0.5\"") && out.includes?("stroke-opacity=\"0.25\""))
check("text runs as tspans", out.includes?("<tspan>a </tspan><tspan fill=\"#ff0000\" font-weight=\"bold\">b</tspan>") && out.includes?("letter-spacing=\"2\""))
check("ellipse with join and dash offset", out.includes?("<ellipse cx=\"50\"") && out.includes?("stroke-linejoin=\"round\"") && out.includes?("stroke-dashoffset=\"3\""))

<< "ALL PASS motion_spec ([passed.load()] checks)"
