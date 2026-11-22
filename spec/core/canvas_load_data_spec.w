# Canvas.load_image_data: decode from memory with the system decoders.
#
# Run: `bin/tungsten spec/core/canvas_load_data_spec.w`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

c = Canvas.new(7, 5)
c.clear("#ff0000")
path = "/tmp/canvas_load_data_spec.png"
c.write_png(path)
c.close
bytes = File.read(path)
img = Canvas.load_image_data(bytes)
check("load_data.width", img.width == 7)
check("load_data.height", img.height == 5)
px = img.bytes
check("load_data.red", px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255)
img.release
raised = false
begin
  Canvas.load_image_data("not an image")
rescue e
  raised = true
check("load_data.rejects_garbage", raised)
<< "canvas_load_data_spec: all passed"
