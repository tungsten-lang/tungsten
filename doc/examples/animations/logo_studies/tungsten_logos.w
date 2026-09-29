# Eight original logo studies. Core owns every scene, sampled curve, particle,
# keyframe, easing calculation, and frame update. The SVG consumer interprets
# explicit material metadata (chrome / heat / flat), and outlines PlotLabels.
# Coordinates are screen-space, y down, as declared in each scene's metadata.
use core/animation

-> bezier_chain(values, steps = 12)
  out = []
  start = values[0]
  segment = 1
  while segment < values.size
    a = values[segment]
    b = values[segment + 1]
    finish = values[segment + 2]
    i = 0
    while i < steps
      t = i.to_f() / steps.to_f()
      u = ~1.0 - t
      out.push([
        u*u*u*start[0] + ~3.0*u*u*t*a[0] + ~3.0*u*t*t*b[0] + t*t*t*finish[0],
        u*u*u*start[1] + ~3.0*u*u*t*a[1] + ~3.0*u*t*t*b[1] + t*t*t*finish[1]
      ])
      i += 1
    start = finish
    segment += 3
  out.push(start)
  out

-> logo_node(scene, id, points, fill, stroke = nil, width = ~0.0, closed = true, metadata = nil)
  scene.add(Plot.polyline(points, closed, id,
    PlotStyle.new(stroke, fill, width), metadata))

-> logo_text(scene, id, text, x, y, size, family, color, tracking = ~0.0, face = "Regular")
  scene.add(Plot.label(text, [x, y], :plain, id,
    PlotStyle.new(nil, color, ~0.0, ~1.0, [], nil, size, family),
    {:tracking => tracking, :face => face, :role => :wordmark}))

-> logo_scene(number, name, bucket, background, ink, description)
  Plot.scene(~640.0, ~420.0, background, nil, {
    :number => number, :name => name, :bucket => bucket, :ink => ink,
    :description => description, :author => "Original Tungsten logo study",
    :geometry_coordinate_system => :screen_y_down,
    :material_backend => :svg, :poster_frame => 48
  })

-> logo_timeline(scene)
  Animation.timeline(scene, ~4.0, 24, nil, {
    :loop => true, :sampling => :core_animation_frames,
    :renderer_required_for_pixels => true
  })

-> logo_cycle(timeline, target, property, from, peak, back = nil)
  finish = back == nil ? from : back
  timeline.add(Animation.track(target, property, [
    Animation.keyframe(~0.0, from, :smooth),
    Animation.keyframe(~2.0, peak, :smooth),
    Animation.keyframe(~4.0, finish)
  ]))

-> logo_assemble(timeline, target, dx, dy)
  timeline.add(Animation.track(target, :translate, [
    Animation.keyframe(~0.0, [dx, dy], :smooth),
    Animation.keyframe(~1.15, [~0.0, ~0.0]),
    Animation.keyframe(~2.85, [~0.0, ~0.0], :smooth),
    Animation.keyframe(~4.0, [dx, dy])
  ]))

-> logo_warp(points, amplitude)
  out = []
  points.each -> (point)
    x = point[0]
    y = point[1]
    out.push([x + amplitude * Math.sin(y * ~0.032),
              y + amplitude * ~0.5 * Math.sin(x * ~0.045)])
  out

-> logo_sparks(scene, timeline, count, center_x, center_y, spread)
  i = 0
  while i < count
    # Deterministic, stratified ember positions. No random source.
    x = center_x + Math.sin(i.to_f() * ~2.39996323) * spread
    y = center_y + Math.cos(i.to_f() * ~1.713) * ~58.0
    radius = i % 3 == 0 ? ~1.6 : ~0.85
    id = "spark-" + i.to_s()
    scene.add(Plot.points([[x, y]], radius, id,
      PlotStyle.new(nil, "#ffba69", ~0.0), {:role => :atmosphere}))
    phase = i.to_f() / count.to_f() * ~3.0
    timeline.add(Animation.track(id, :opacity, [
      Animation.keyframe(~0.0, ~0.0),
      Animation.keyframe(phase + ~0.10, ~0.0, :smooth),
      Animation.keyframe(phase + ~0.40, ~0.85, :smooth),
      Animation.keyframe(phase + ~0.95, ~0.0),
      Animation.keyframe(~4.0, ~0.0)
    ]))
    logo_cycle(timeline, id, :translate, [~0.0, ~14.0], [~5.0, ~-16.0])
    i += 1

# 01 / QUICKSILVER. A pooled, rounded T with a narrow waist.
s1 = logo_scene(1, "Quicksilver", "Liquid metal", "#101214", "#ecedef",
  "A poured T. Soft edges, a dense silver body, a moving reflection.")
p1 = bezier_chain([
  [244,94], [280,83], [357,83], [393,94],
  [419,101], [425,121], [402,132],
  [384,141], [354,134], [346,154],
  [339,176], [352,216], [336,235],
  [327,247], [304,246], [295,232],
  [283,213], [298,179], [289,153],
  [283,134], [252,143], [234,130],
  [215,117], [223,101], [244,94]
])
logo_node(s1, "pool", p1, "#d2d6da", "#bac2c9", ~0.6, true,
  {:material => :chrome, :role => :mark, :bevel => true})
logo_text(s1, "word", "tungsten", ~320.0, ~327.0, ~42.0, "Avenir Next", "#eef0f2", ~1.8, "Medium")
t1 = logo_timeline(s1)
logo_cycle(t1, "pool", :points, p1, logo_warp(p1, ~3.8))
logo_cycle(t1, "pool", :sheen, ~-55.0, ~55.0)

# 02 / FLUX. One continuous folded W ribbon, with a reflective face.
s2 = logo_scene(2, "Flux", "Liquid metal", "#dcdedb", "#222728",
  "A continuous W ribbon. Folded chrome with a quieter industrial wordmark.")
p2 = bezier_chain([
 [219,99], [225,89], [245,92], [251,106],
 [263,135], [270,185], [284,196],
 [298,177], [299,144], [309,131],
 [316,121], [330,123], [336,136],
 [348,162], [345,184], [359,196],
 [373,175], [380,130], [391,105],
 [397,91], [416,91], [422,101],
 [413,146], [398,206], [378,231],
 [366,246], [347,246], [336,230],
 [327,217], [323,200], [320,183],
 [316,201], [310,221], [300,233],
 [286,248], [270,245], [257,228],
 [242,207], [224,145], [219,99]
], 8)
logo_node(s2, "ribbon", p2, "#aab0b1", "#798083", ~0.65, true,
  {:material => :chrome, :role => :mark, :bevel => true})
logo_text(s2, "word", "TUNGSTEN", ~320.0, ~324.0, ~32.0, "DIN Condensed", "#303637", ~7.2, "Bold")
t2 = logo_timeline(s2)
logo_cycle(t2, "ribbon", :sheen, ~55.0, ~-55.0)
logo_cycle(t2, "ribbon", :points, p2, logo_warp(p2, ~2.2))

# 03 / FILAMENT. One hot, continuous W line. Heat is concentrated at its bends.
s3 = logo_scene(3, "Filament", "Embers", "#100e0d", "#ffd4a4",
  "A white-hot W. A restrained filament glow and a few escaping embers.")
p3 = [[224,104], [273,225], [320,134], [367,225], [416,104]]
logo_node(s3, "filament", p3, nil, "#ffb163", ~7.0, false,
  {:material => :heat, :role => :mark, :linejoin => :round})
logo_text(s3, "word", "TUNGSTEN", ~320.0, ~327.0, ~27.0, "Avenir Next", "#e8d8c8", ~5.0, "Medium")
t3 = logo_timeline(s3)
logo_cycle(t3, "filament", :heat, ~0.48, ~1.0)
logo_sparks(s3, t3, 32, ~320.0, ~144.0, ~125.0)

# 04 / CINDER. A compact forged T split by a diagonal hot seam.
s4 = logo_scene(4, "Cinder", "Embers", "#17120f", "#ff994f",
  "A forged T with a glowing cut. More solid, more emblematic.")
logo_node(s4, "cap-left", [[228,98],[307,98],[290,145],[244,145]], "#ba5029", nil, ~0.0, true,
  {:material => :copper, :role => :mark})
logo_node(s4, "cap-right", [[318,98],[412,98],[396,145],[301,145]], "#db7540", nil, ~0.0, true,
  {:material => :copper, :role => :mark})
logo_node(s4, "stem", [[295,156],[346,156],[321,239],[270,239]], "#dc733c", nil, ~0.0, true,
  {:material => :copper, :role => :mark})
logo_node(s4, "seam", [[307,101],[293,141]], nil, "#ffc388", ~2.0, false,
  {:material => :heat, :role => :accent})
logo_text(s4, "word", "tungsten", ~320.0, ~327.0, ~43.0, "Avenir Next", "#f1d9c6", ~0.0, "Demi Bold")
t4 = logo_timeline(s4)
logo_cycle(t4, "seam", :heat, ~0.38, ~1.0)
logo_cycle(t4, "stem", :sheen, ~-20.0, ~30.0)
logo_sparks(s4, t4, 24, ~315.0, ~117.0, ~118.0)

# 05 / CLEAVE. Two exactly drawn pieces read as one spare T.
s5 = logo_scene(5, "Cleave", "Sharp geometry", "#eae7df", "#252725",
  "A single cut through a T. Crisp, economical, and strong in one color.")
logo_node(s5, "crossbar", [[228,103],[419,103],[388,136],[228,136]], "#252725", nil, ~0.0, true,
  {:role => :mark})
logo_node(s5, "blade", [[306,147],[346,147],[346,231],[306,253]], "#252725", nil, ~0.0, true,
  {:role => :mark})
logo_text(s5, "word", "TUNGSTEN", ~320.0, ~330.0, ~25.0, "Avenir Next", "#252725", ~5.5, "Medium")
t5 = logo_timeline(s5)
logo_assemble(t5, "crossbar", ~-14.0, ~0.0)
logo_assemble(t5, "blade", ~0.0, ~16.0)

# 06 / LATTICE. Three open chevrons create a crystalline W.
s6 = logo_scene(6, "Lattice", "Sharp geometry", "#121a1b", "#dedbcf",
  "An open crystalline W. Fine joins, generous space, and a warm ivory finish.")
logo_node(s6, "left", [[231,111],[276,232],[320,111]], nil, "#dedbcf", ~4.0, false,
  {:role => :mark, :linejoin => :miter})
logo_node(s6, "right", [[320,111],[364,232],[409,111]], nil, "#dedbcf", ~4.0, false,
  {:role => :mark, :linejoin => :miter})
logo_node(s6, "crown", [[231,111],[320,68],[409,111]], nil, "#dedbcf", ~2.0, false,
  {:role => :mark})
logo_text(s6, "word", "TUNGSTEN", ~320.0, ~329.0, ~25.0, "Futura", "#dedbcf", ~5.7, "Medium")
t6 = logo_timeline(s6)
logo_assemble(t6, "left", ~-9.0, ~7.0)
logo_assemble(t6, "right", ~9.0, ~7.0)
logo_assemble(t6, "crown", ~0.0, ~-9.0)

# 07 / LOWERCASE. Typography leads: compact, friendly, and technically exact.
s7 = logo_scene(7, "Lowercase", "Typography", "#e9eee8", "#1e352d",
  "A tightly set lowercase wordmark. A square terminal adds a small coding cue.")
logo_text(s7, "word", "tungsten", ~307.0, ~244.0, ~93.0, "Avenir Next", "#1e352d", ~-4.0, "Demi Bold")
logo_node(s7, "terminal", [[491,230],[505,230],[505,244],[491,244]], "#678779", nil, ~0.0, true,
  {:role => :mark})
t7 = logo_timeline(s7)
logo_cycle(t7, "word", :tracking, ~-3.0, ~-4.0)
logo_cycle(t7, "terminal", :opacity, ~0.35, ~1.0)

# 08 / EDITORIAL. A high-contrast italic, with an elemental signature.
s8 = logo_scene(8, "Editorial", "Typography", "#f1e9dd", "#30291f",
  "A literary, high-contrast italic. An elemental signature above a fluid wordmark.")
logo_text(s8, "element", "W", ~309.0, ~127.0, ~24.0, "Bodoni 72", "#30291f", ~0.0, "Book")
logo_text(s8, "atomic", "74", ~332.0, ~111.0, ~10.0, "Avenir Next", "#8b6946", ~0.6, "Medium")
logo_text(s8, "word", "Tungsten", ~317.0, ~253.0, ~91.0, "Bodoni 72", "#30291f", ~-2.5, "Book Italic")
logo_node(s8, "rule", [[275,303],[365,303]], nil, "#a58a63", ~0.9, false, {:role => :accent})
t8 = logo_timeline(s8)
logo_cycle(t8, "word", :tracking, ~-1.7, ~-2.5)
logo_cycle(t8, "rule", :opacity, ~0.25, ~1.0)

# Retain the authoritative Core descriptions and materialize all playback
# updates in Core. Consumers choose a frame; they do not recalculate easing.
all = [t1, t2, t3, t4, t5, t6, t7, t8]
studies = []
all.each -> (timeline)
  samples = []
  timeline.each_frame -> (frame)
    samples.push({:time => frame.time, :updates => frame.updates})
  first = JSON.encode(samples[0][:updates])
  last = JSON.encode(samples[samples.size - 1][:updates])
  raise "logo loop did not close exactly" if first != last
  raise "logo frame schedule changed" if timeline.frame_count != 97
  studies.push({:timeline => timeline.to_data, :samples => samples})
<< JSON.encode({:schema => "tungsten.logo-studies/v1", :studies => studies})
