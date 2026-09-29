# Filament T: an original incandescent-wire identity study.
# The crossbar is a projected three-dimensional helix, not a planar sine wave.
# Core owns its sampled geometry, depth-band correspondence and heat timeline.
use core/animation

-> filament_helix(theta)
  turns = ~22.0
  tau = ~6.283185307179586
  [~222.0 + ~196.0 * theta / (tau * turns) + ~6.0 * Math.sin(theta),
   ~126.0 + ~11.0 * Math.cos(theta)]

-> filament_segment(start, finish, count)
  points = []
  i = 0
  while i <= count
    t = i.to_f() / count.to_f()
    points.push(filament_helix(start + (finish - start) * t))
    i += 1
  points

-> filament_wire(scene, id, points, width, color, core = true)
  scene.add(Plot.polyline(points, false, id,
    PlotStyle.new(color, nil, width), {
      :role => :mark, :material => :heat,
      :heat_color => color, :heat_core => core,
      :core_color => "#fff4dc", :core_fraction => ~0.40,
      :heat_floor => ~0.28
    }))

-> filament_heat(timeline, id, strength = ~1.0)
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
  :number => 1, :name => "Filament T", :bucket => "Coiled tungsten wire",
  :ink => "#f2e4d1",
  :description => "A T with an incandescent coil for its crossbar and a fine glowing stem.",
  :geometry_coordinate_system => :screen_y_down,
  :poster_frame => 48,
  :construction => :projected_helix,
  :coil_turns => 22, :coil_radius => ~11.0,
  :helix_pitch => ~196.0 / ~22.0,
  :author => "Original Tungsten logo study"
})
timeline = Animation.timeline(scene, ~4.0, 24, nil, {
  :loop => true, :sampling => :core_animation_frames,
  :renderer_required_for_pixels => true
})

# The stem meets the bottom of the eleventh complete turn exactly.
filament_wire(scene, "stem", [[~320.0, ~137.0], [~320.0, ~245.0]], ~4.4, "#ffb56d")
filament_heat(timeline, "stem", ~0.87)

# Warm, slightly dimmer wire backs establish the coil's depth.
tau = ~6.283185307179586
filament_wire(scene, "coil-back", filament_segment(~0.0, tau * ~22.0, 880), ~2.3, "#cf7735", false)
filament_heat(timeline, "coil-back", ~0.64)

# The front half of every turn is hotter and whiter. Geometry is a subset of
# the same continuous helix, with stable point correspondence.
turn = 0
while turn < 22
  start = turn.to_f() * tau + ~0.10
  finish = turn.to_f() * tau + ~3.041592653589793
  id = "coil-front-" + turn.to_s()
  filament_wire(scene, id, filament_segment(start, finish, 24), ~2.0, "#ffdba1")
  filament_heat(timeline, id)
  turn += 1

# Short wire ends keep the horizontal stroke clean and legible as a T.
filament_wire(scene, "left-tail", [[~208.0, ~137.0], [~222.0, ~137.0]], ~2.4, "#e99448")
filament_wire(scene, "right-tail", [[~418.0, ~137.0], [~432.0, ~137.0]], ~2.4, "#e99448")
filament_heat(timeline, "left-tail", ~0.73)
filament_heat(timeline, "right-tail", ~0.73)

scene.add(Plot.label("TUNGSTEN", [~320.0, ~327.0], :plain, "word",
  PlotStyle.new(nil, "#e8d8c8", ~0.0, ~1.0, [], nil, ~27.0, "Avenir Next"),
  {:tracking => ~5.0, :face => "Medium", :role => :wordmark}))

samples = []
timeline.each_frame -> (frame)
  samples.push({:time => frame.time, :updates => frame.updates})
raise "filament frame schedule changed" if timeline.frame_count != 97
raise "filament heat loop did not close" if JSON.encode(samples[0][:updates]) != JSON.encode(samples[96][:updates])
center = filament_helix(tau * ~11.0)
raise "coil/stem junction moved" if (center[0] - ~320.0).abs > ~1.0e-9 || (center[1] - ~137.0).abs > ~1.0e-9
<< JSON.encode({
  :schema => "tungsten.logo-studies/v1",
  :title => "Filament, wound into a T.",
  :slug => "filament-t",
  :studies => [{:timeline => timeline.to_data, :samples => samples}]
})
