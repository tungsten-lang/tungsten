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

model_points = [[~0.0, ~0.0], [~1.0, ~1.0]]
model_check = PlotModelCheck.new(
  model_points, [model_points], "response", "linear-y",
  {:observed_transform_id => "identity-v1", :draw_source_id => "fixture-v1"})
visualization_check("autoload.model_check",
                    model_check.to_data[:draw_count] == 1)

assertion = AnimationTrackIntervalAssertion.new(
  "fade-equals-itself", "line", :opacity, :equals, "line", :opacity)
verification = AnimationVerifier.verify(timeline, [assertion])
result = verification.results[0]
visualization_check("autoload.verification_result",
                    result.class_name == "AnimationVerificationResult")
visualization_check("autoload.verification_report",
                    verification.class_name == "AnimationVerificationReport")
visualization_check("autoload.verifier", verification.passed?)

preview_scene = PlotScene.new(~4.0, ~4.0, "#000000")
preview_scene.add(PlotPoints.new(
  [[~1.0, ~1.0]], ~0.5, "preview-point",
  PlotStyle.new(nil, "#ff0000", ~0.0, ~1.0, [], :circle)))
preview_timeline = AnimationTimeline.new(preview_scene, ~0.0, 1)
preview = AnimationPointPreview.new(preview_timeline)
preview_pixels = preview.render(0)[:pixels]
visualization_check("autoload.point_preview",
                    preview_pixels[9] == 0xff0000ff)
visualization_check("autoload.window_preview",
                    AnimationWindowPreview.class_name == "Class")

<< "visualization_autoload_spec: all checks passed"
