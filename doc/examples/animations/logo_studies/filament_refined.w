# Filament T, refined: a compact identity with eight clear coil turns.
# The crossbar is a projected three-dimensional helix, not a planar sine wave.
# Core owns its sampled geometry, depth-band correspondence and heat timeline.
use core/animation

-> refined_helix(theta)
  turns = ~8.0
  tau = ~6.283185307179586
  [~245.0 + ~150.0 * theta / (tau * turns)  + ~8.3 * Math.sin(theta),
   ~137.0 + ~10.4 * Math.cos(theta)]

-> refined_segment(start, finish, count)
  points = []
  i = 0
  while i <= count
    t = i.to_f() / count.to_f()
    points.push(refined_helix(start + (finish - start) * t))
    i += 1
  points

-> refined_wire(scene, id, points, width, color, core = true)
  scene.add(Plot.polyline(points, false, id,
    PlotStyle.new(color, nil, width), {
      :role => :mark, :material => :heat,
      :heat_color => color, :heat_core => core,
      :core_color => "#fff4dc", :core_fraction => ~0.30,
      :heat_floor => ~0.35, :glow => :restrained
    }))

-> refined_heat(timeline, id, strength = ~1.0)
  timeline.add(Animation.track(id, :heat, [
    Animation.keyframe(~0.0, ~0.04, :smooth),
    Animation.keyframe(~0.45, ~0.24 * strength, :smooth),
    Animation.keyframe(~1.10, ~1.0 * strength, :smooth),
    Animation.keyframe(~1.50, ~0.84 * strength, :smooth),
    Animation.keyframe(~2.0, ~1.0 * strength, :smooth),
    Animation.keyframe(~2.65, ~0.88 * strength, :smooth),
    Animation.keyframe(~3.20, ~0.55 * strength, :smooth),
    Animation.keyframe(~4.0, ~0.04)
  ]))

scene = Plot.scene(~640.0, ~420.0, "#100e0d", nil, {
  :number => 1, :name => "Filament", :bucket => "Refined coil T",
  :ink => "#f2e4d1",
  :description => "Eight deliberate coils, a stronger stem, and a closer, quieter wordmark.",
  :geometry_coordinate_system => :screen_y_down,
  :poster_frame => 48,
  :construction => :projected_helix,
  :coil_turns => 8, :coil_radius => ~10.4,
  :helix_pitch => ~150.0 / ~8.0,
  :author => "Original Tungsten logo study"
})
timeline = Animation.timeline(scene, ~4.0, 24, nil, {
  :loop => true, :sampling => :core_animation_frames,
  :renderer_required_for_pixels => true
})

# The stem joins the center trough. No decorative lead extensions.
refined_wire(scene, "stem", [[~320.0, ~147.4], [~320.0, ~242.0]], ~6.8, "#ffb56d")
refined_heat(timeline, "stem", ~0.87)

# Warm, slightly dimmer wire backs establish the coil's depth.
tau = ~6.283185307179586
refined_wire(scene, "coil-back", refined_segment(~0.0, tau * ~8.0, 320), ~3.7, "#cf7735", false)
refined_heat(timeline, "coil-back", ~0.64)

# The front half of every turn is hotter and whiter. Geometry is a subset of
# the same continuous helix, with stable point correspondence.
turn = 0
while turn < 8
  start = turn.to_f() * tau + ~0.10
  finish = turn.to_f() * tau + ~3.041592653589793
  id = "coil-front-" + turn.to_s()
  refined_wire(scene, id, refined_segment(start, finish, 24), ~3.4, "#ffdba1")
  refined_heat(timeline, id)
  turn += 1

scene.add(Plot.label("tungsten", [~320.0, ~306.0], :plain, "word",
  PlotStyle.new(nil, "#e8d8c8", ~0.0, ~1.0, [], nil, ~43.0, "Avenir Next"),
  {:tracking => ~-1.0, :face => "Demi Bold", :role => :wordmark}))

samples = []
timeline.each_frame -> (frame)
  samples.push({:time => frame.time, :updates => frame.updates})
raise "filament frame schedule changed" if timeline.frame_count != 97
raise "filament heat loop did not close" if JSON.encode(samples[0][:updates]) != JSON.encode(samples[96][:updates])
center = refined_helix(tau * ~4.0)
raise "coil/stem junction moved" if (center[0] - ~320.0).abs > ~1.0e-9 || (center[1] - ~147.4).abs > ~1.0e-9
<< JSON.encode({
  :schema => "tungsten.logo-studies/v1",
  :title => "Filament, refined.",
  :slug => "filament-refined",
  :studies => [{:timeline => timeline.to_data, :samples => samples}]
})
