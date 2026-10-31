# A PNG scaled into a JPEG with CoreGraphics (high-quality resampling), for the thumbnails and the Short's cover
# (tools/tw_thumbs.sh): replaces the PIL Lanczos + JPEG step of tools/render_thumb.sh.
#   tw_jpeg <src.png> <dst.jpg> <width> <height> [quality 0.92]

-> main(args)
  if args.size < 4
    << "usage: tw_jpeg <src.png> <dst.jpg> <width> <height> \[quality]"
    exit(2)
  w = args[2].to_i
  h = args[3].to_i
  q = ~0.92
  q = args[4].to_f if args.size > 4
  img = Canvas.load_image(args[0])
  c = Canvas.new(w, h)
  c.clear("#000000")
  c.image(img, 0, 0, w, h, {fit: :fill, quality: :high})
  img.release
  c.write(args[1], {quality: q})
  c.close
  << args[1] + " " + w.to_s + "x" + h.to_s
  0

args = []
i_arg = 0
while i_arg < ARGV.size
  if ARGV[i_arg] != "--"
    args.push(ARGV[i_arg])
  i_arg += 1
main(args)
