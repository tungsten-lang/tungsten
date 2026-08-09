# Optional macOS Metal/Cocoa window for an AnimationPointPreview.
#
# This backend stays separate from both core/animation and the pure point
# rasterizer. Public class autoloading brings it in only when a caller invokes
# AnimationWindowPreview, so headless interpreters and example checks never
# need to parse or resolve the platform graphics bridge.

use core/animation/point_preview
use core/graphics

+ AnimationWindowPreview
  -> .show(timeline, title = "Tungsten animation", mode = :ping_pong,
           max_frames = nil)
    if title.class_name != "String" || title.size == 0
      raise "animation window preview title must be a nonempty String"
    AnimationPointPreview.frame_index(0, timeline.frame_count, mode)
    limit = nil
    if max_frames != nil
      limit = PlotData.positive_integer(
        max_frames, "preview maximum frame count", 1_000_000)

    preview = AnimationPointPreview.new(timeline)
    device = metal_device()
    pixels = metal_array(32, preview.pixel_count)
    buffer = metal_buffer_for(device, pixels)
    window = gfx_window(
      device, title, preview.width, preview.height)
    started = clock()
    last_step = -1
    presented = 0
    while !gfx_should_close(window) && !gfx_key_down(window, KEY_ESC)
      gfx_poll(window)
      elapsed = clock() - started
      logical_step = Math.floor(elapsed * timeline.fps.to_f()).to_i()
      if logical_step != last_step
        selected = AnimationPointPreview.frame_index(
          logical_step, timeline.frame_count, mode)
        preview.render_into(selected, pixels)
        displayed = gfx_present_wait(
          window, buffer, preview.width, preview.height)
        if displayed
          presented += 1
          last_step = logical_step
          break if limit != nil && presented >= limit
      elapsed_after_present = clock() - started
      delay = (logical_step + 1).to_f() / timeline.fps.to_f() - elapsed_after_present
      delay = ~0.01 if delay > ~0.01
      sleep(delay) if delay > ~0.0
    presented
