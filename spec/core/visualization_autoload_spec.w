# Public plotting and animation classes are discoverable from core/tungsten's
# generated autoload catalog without an explicit use directive.

-> visualization_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

scene = PlotScene.new(~320.0, ~180.0)
line = PlotPolyline.new([[~0.0, ~0.0], [~1.0, ~1.0]], false, "line")
scene.add(line)
timeline = AnimationTimeline.new(scene, ~1.0, 2)
timeline.add(Animation.fade("line", ~0.0, ~1.0))

visualization_check("autoload.plot_scene", scene.to_data[:nodes].size == 1)
visualization_check("autoload.animation", timeline.frame_count == 3)
visualization_check("autoload.frame", timeline.frame(1).updates[0][:value] == ~0.5)

<< "visualization_autoload_spec: all checks passed"
