# Mailing-label extraction (Amazon returns, UPS CampusShip), image selection,
# thresholding, and printing.
# image-native exposes only image decoding and CoreGraphics PDF output.
-> error(message)
  ccall("w_eputs", "print-label: " + message)
  exit(1)

# A 4x6 mailing label is a landscape 3:2 image at least 900x600 pixels.
-> label_shape(w, h)
  w >= 900 && h >= 600 && w * 10 > h * 14 && w * 10 < h * 16

# The smallest rectangle [x, y, w, h] holding every pixel darker than paper
# white, or nil for a blank image. pixels is 8-bit gray, rows top to bottom.
-> ink_box(pixels, w, h)
  left = w
  right = -1
  top = h
  bottom = -1
  y = 0
  while y < h
    row = y * w
    x = 0
    while x < w
      if pixels[row + x] < 200
        if x < left
          left = x
        if x > right
          right = x
        if y < top
          top = y
        bottom = y
      x = x + 1
    y = y + 1
  box = nil
  if right >= 0
    box = [left, top, right - left + 1, bottom - top + 1]
  box

-> usage
  << "Usage: print-label FILE.pdf \[--output LABEL.pdf] \[--printer NAME]"
  << "Extract an Amazon return or UPS CampusShip label. --output saves a PDF without printing."
  << "Prints to Rollo_X1040; override with ROLLO_PRINTER or --printer."
  exit(0)

args = argv()
input = nil
output = nil
printer = env("ROLLO_PRINTER")
if printer == nil || printer == ""
  printer = "Rollo_X1040"
i = 0
while i < args.size
  arg = args[i]
  if arg == "--help" || arg == "-h"
    usage()
  elsif arg == "--output" || arg == "--printer"
    if i + 1 >= args.size
      error("missing value after " + arg)
    i = i + 1
    if arg == "--output"
      output = args[i]
    else
      printer = args[i]
  elsif arg[0] == "-"
    error("unknown option " + arg)
  elsif input == nil
    input = arg
  else
    error("only one input PDF is supported")
  i = i + 1
if input == nil
  usage()
if !File.exist?(input)
  error("input PDF does not exist")
if output == nil && (printer == nil || printer == "")
  error("set ROLLO_PRINTER or specify --printer; use --output to save a PDF")
if output != nil && File.exist?(output)
  error("output already exists; choose another path")
root = ccall("w_executable_dir")
if root == nil || root == ""
  error("cannot locate the executable directory")
tmp = capture("/usr/bin/mktemp -d -t print-label").strip
if tmp == ""
  error("could not create temporary directory")
result = 1
begin
  result = Process.spawn(["/opt/homebrew/bin/pdfimages", "-png", input, tmp + "/image"]).wait
  if result == 0
    target = output == nil ? tmp + "/label.pdf" : output
    native = root + "/image-native"
    metadata = tmp + "/images.txt"
    candidate = nil
    crop = nil
    width = 0
    height = 0
    count = 0
    Dir.children(tmp).each ->(name)
      if name.size > 10 && name[0...6] == "image-" && name[(name.size - 4)...name.size] == ".png"
        image_path = tmp + "/" + name
        info_result = Process.spawn([native, "info", image_path, metadata]).wait
        if info_result == 0
          parts = File.read(metadata).strip.split(" ")
          if parts.size == 2
            w = parts[0].to_i
            h = parts[1].to_i
            if label_shape(w, h)
              candidate = image_path
              width = w
              height = h
              crop = nil
              count = count + 1
            elsif w >= 900 && h >= 600 && w > h
              # UPS CampusShip pads its 3:2 label with blank white columns
              # (1400x800 around a 1200x800 label): trim to the inked area.
              trim_path = tmp + "/trim.gray"
              if Process.spawn([native, "gray", image_path, trim_path]).wait == 0
                box = ink_box(File.read_bytes(trim_path), w, h)
                if box != nil && label_shape(box[2], box[3])
                  candidate = image_path
                  width = w
                  height = h
                  crop = box
                  count = count + 1
    if result == 0
      if count != 1
        ccall("w_eputs", "print-label: expected one large 3:2 landscape label image; found " + count.to_s + ". This PDF layout needs review; no job was printed.")
        result = 1
      else
        raw = "-"
        threshold_text = env("LABEL_THRESHOLD")
        if threshold_text != nil && threshold_text != ""
          threshold = threshold_text.to_i
          if threshold >= 1 && threshold <= 254
            raw = tmp + "/pixels.gray"
            result = Process.spawn([native, "gray", candidate, raw]).wait
            if result == 0
              pixels = File.read_bytes(raw)
              if pixels.size != width * height
                result = 1
              else
                j = 0
                while j < pixels.size
                  pixels[j] = pixels[j] < threshold ? 0 : 255
                  j = j + 1
                File.write_bytes(raw, pixels)
        if result == 0
          label_w = crop == nil ? width : crop[2]
          label_h = crop == nil ? height : crop[3]
          scale = ~278.0 / label_h
          vertical_scale = ~422.0 / label_w
          if vertical_scale < scale
            scale = vertical_scale
          draw_w = label_w * scale
          draw_h = label_h * scale
          tx = (~288.0 - draw_h) / ~2.0
          ty = (~432.0 + draw_w) / ~2.0
          pdf_args = [native, "pdf", candidate, raw, target, "288", "432", draw_w.to_s, draw_h.to_s, tx.to_s, ty.to_s]
          if crop != nil
            crop.each ->(edge)
              pdf_args.push(edge.to_s)
          result = Process.spawn(pdf_args).wait
    if result == 0
      if output == nil
        print_args = ["/usr/bin/lp", "-d", printer, "-o", "media=4x6", "-o", "fit-to-page"]
        # IPP uses 3/4/5 for draft/normal/high. ippeveprinter supplies
        # the keyword in the job environment; preserve the caller's choice.
        quality = env("IPP_PRINT_QUALITY")
        if quality == "high"
          print_args.push("-o")
          print_args.push("print-quality=5")
        elsif quality == "draft"
          print_args.push("-o")
          print_args.push("print-quality=3")
        print_args.push(target)
        result = Process.spawn(print_args).wait
      else
        << "Saved 4×6 label to " + output
ensure
  Process.spawn(["/bin/rm", "-rf", tmp]).wait
exit(result)
