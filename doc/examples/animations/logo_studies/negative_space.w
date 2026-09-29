# Two negative-space identities. The aperture in each mark is a real opening
# in one positive contour: no background-colored paint, masks, or fake holes.
# Core owns the construction, frame schedule and all interpolated geometry.
use core/animation

-> negative_arc(points, x, y, radius, first, last, steps = 24)
  i = 0
  while i <= steps
    angle = first + (last - first) * i.to_f() / steps.to_f()
    points.push([x + radius * Math.cos(angle), y + radius * Math.sin(angle)])
    i += 1

-> negative_node(scene, id, points, fill, stroke = nil, width = ~0.0, closed = true)
  scene.add(Plot.polyline(points, closed, id,
    PlotStyle.new(stroke, fill, width), {
      :role => :mark, :linejoin => :round,
      :construction => :open_counterform
    }))

-> negative_scene(number, name, background, ink, description)
  scene = Plot.scene(~640.0, ~420.0, background, nil, {
    :number => number, :name => name, :bucket => "Negative space",
    :ink => ink, :description => description, :poster_frame => 48,
    :author => "Original Tungsten logo study",
    :geometry_coordinate_system => :screen_y_down,
    :construction => :true_transparent_aperture
  })
  scene.add(Plot.label("tungsten", [~320.0, ~312.0], :plain, "word",
    PlotStyle.new(nil, ink, ~0.0, ~1.0, [], nil, ~35.0, "Avenir Next"),
    {:tracking => ~0.25, :face => "Demi Bold", :role => :wordmark}))
  scene

-> negative_timeline(scene)
  Animation.timeline(scene, ~4.0, 24, nil, {
    :loop => true, :sampling => :core_animation_frames,
    :renderer_required_for_pixels => true
  })

-> negative_cycle(timeline, target, property, first, center)
  timeline.add(Animation.track(target, property, [
    Animation.keyframe(~0.0, first, :smooth),
    Animation.keyframe(~1.35, center),
    Animation.keyframe(~2.65, center, :smooth),
    Animation.keyframe(~4.0, first)
  ]))

# Counterform: trace the outer circle almost completely, then turn upward
# through the open foot and around the T aperture. Its 28px stem and 26px
# crossbar have enough clearance to survive a small monochrome reproduction.
-> counterform(half_stem, bar_top, bar_bottom)
  radius = ~88.0
  pi = ~3.141592653589793
  angle = Math.acos(half_stem / radius)
  points = []
  negative_arc(points, ~320.0, ~166.0, radius, angle, ~-1.0 * pi - angle, 144)
  points.push([~320.0 - half_stem, bar_bottom])
  points.push([~255.0, bar_bottom])
  points.push([~255.0, bar_top])
  points.push([~385.0, bar_top])
  points.push([~385.0, bar_bottom])
  points.push([~320.0 + half_stem, bar_bottom])
  points

counter = negative_scene(3, "Counterform", "#181815", "#eee7db",
  "A T cut from a circular ingot. Its open foot makes the absence part of the silhouette.")
counter_points = counterform(~14.0, ~121.0, ~147.0)
negative_node(counter, "ingot", counter_points, "#eee7db")
counter_timeline = negative_timeline(counter)
negative_cycle(counter_timeline, "ingot", :points,
  counterform(~17.0, ~119.5, ~148.5), counter_points)

# Cut Filament: the same principle in a softened square. The aperture stays
# broad; five slender helix turns introduce the material as a second read.
# Each wire turn joins the upper mass, leaving a continuous clear band below.
-> filament_billet(half_stem)
  pi = ~3.141592653589793
  points = [[~320.0 + half_stem, ~251.0], [~388.0, ~251.0]]
  negative_arc(points, ~388.0, ~226.0, ~25.0, pi / ~2.0, ~0.0)
  points.push([~413.0, ~106.0])
  negative_arc(points, ~388.0, ~106.0, ~25.0, ~0.0, pi / ~-2.0)
  points.push([~252.0, ~81.0])
  negative_arc(points, ~252.0, ~106.0, ~25.0, pi / ~-2.0, ~-1.0 * pi)
  points.push([~227.0, ~226.0])
  negative_arc(points, ~252.0, ~226.0, ~25.0, pi, pi / ~2.0)
  points.push([~320.0 - half_stem, ~251.0])
  points.push([~320.0 - half_stem, ~149.0])
  points.push([~252.0, ~149.0])
  points.push([~252.0, ~117.0])
  points.push([~388.0, ~117.0])
  points.push([~388.0, ~149.0])
  points.push([~320.0 + half_stem, ~149.0])
  points

-> counter_wire()
  points = []
  tau = ~6.283185307179586
  turns = ~5.0
  steps = 300
  i = 0
  while i <= steps
    fraction = i.to_f() / steps.to_f()
    theta = fraction * tau * turns
    points.push([
      ~254.0 + ~132.0 * fraction + ~14.0 * Math.sin(theta),
      ~128.0 + ~11.0 * Math.cos(theta)
    ])
    i += 1
  points

cut = negative_scene(4, "Cut Filament", "#eee7db", "#181815",
  "A broad T aperture with five fine winding turns. A solid identity first; tungsten wire on closer inspection.")
negative_node(cut, "billet", filament_billet(~14.0), "#181815")
negative_node(cut, "winding", counter_wire(), nil, "#181815", ~2.6, false)
cut_timeline = negative_timeline(cut)
negative_cycle(cut_timeline, "winding", :stroke_width, ~1.7, ~2.6)

studies = []
[counter_timeline, cut_timeline].each -> (timeline)
  samples = []
  timeline.each_frame -> (frame)
    samples.push({:time => frame.time, :updates => frame.updates})
  raise "negative-space frame schedule changed" if timeline.frame_count != 97
  raise "negative-space loop did not close exactly" if JSON.encode(samples[0][:updates]) != JSON.encode(samples[96][:updates])
  studies.push({:timeline => timeline.to_data, :samples => samples})
<< JSON.encode({:schema => "tungsten.logo-studies/v1", :studies => studies})
