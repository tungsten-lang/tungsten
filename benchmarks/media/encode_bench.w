# Encode raw frames with VideoEncoder and mux them, for the ffmpeg comparison
# in benchmarks/media/run.sh. Build with --release:
#
#   bin/tungsten -o /tmp/encode_bench --release benchmarks/media/encode_bench.w
#   /tmp/encode_bench FRAMES.rgb OUT.mp4 --frames 1200 --size 1920x1080 --codec h264 --quality 0.6
#       [--rate 24/1] [--input rgb24] [--gop 48] [--sessions 1] [--save-segments DIR] [--reorder]
#
#   /tmp/encode_bench --mux-only DIR OUT.mp4 --frames 56002 [--audio mix.wav]
#       appends DIR's segment files (seg_00000.h264 ...) round-robin until
#       FRAMES frames: a passthrough master, no encoding.
#
# FRAMES.rgb is raw packed pixels, frame after frame, read through an Mmap.
# With --sessions N, segment k goes to encoder k mod N: independent sessions
# with equal settings emit identical parameter sets, so their segments share
# one sample description, and N sessions keep more of the media engines busy.

args = argv()

-> flag(args, name, fallback)
  i = 0
  while i + 1 < args.size
    return args[i + 1] if args[i] == name
    i += 1
  fallback

-> ms(a, b)
  ((b - a) * ~1000.0).round

if args.size < 2
  << "usage: encode_bench FRAMES.rgb OUT.mp4 \[--frames N] \[--size WxH] \[--codec C] \[--quality Q] \[--rate N/D] \[--input rgb24] \[--gop 48] \[--sessions N] \[--save-segments DIR]"
  << "       encode_bench --mux-only DIR OUT.mp4 --frames N \[--audio WAV] \[--rate N/D]"
  exit(2)

rate = Timecode.rate(flag(args, "--rate", "24/1"))

if args[0] == "--mux-only"
  dir = args[1]
  out = args[2]
  total = flag(args, "--frames", "56002").to_i
  files = []
  Dir.children(dir).sort.each ->(n)
    files.push(dir + "/" + n) if n.starts_with?("seg_") && n.ends_with?(".h264")
  if files.size == 0
    << "no segment files in [dir]"
    exit(1)
  # Frame counts, so the tail can be a shorter segment that lands exactly.
  counts = []
  files.each ->(fp)
    sg = VideoSegment.load(fp)
    counts.push(sg.frames)
    sg.release
  # Cycle through the full-length segments; a shorter one only ends the file.
  longest = 0
  counts.each ->(n)
    longest = n if n > longest
  full = []
  j = 0
  while j < counts.size
    full.push(j) if counts[j] == longest
    j += 1
  t0 = clock()
  mux = Mux.new(out, rate: rate, audio: flag(args, "--audio", nil), frames: total)
  done = 0
  k = 0
  appended = 0
  while done < total
    idx = full[k % full.size]
    if done + counts[idx] > total
      # find a segment that fits the remainder exactly
      idx = -1
      j = 0
      while j < files.size
        idx = j if counts[j] == total - done && idx < 0
        j += 1
      if idx < 0
        << "no segment of [total - done] frames for the tail"
        exit(1)
    seg = VideoSegment.load(files[idx])
    mux.append(seg)
    done += seg.frames
    seg.release
    appended += 1
    k += 1
  t1 = clock()
  r = mux.close
  t2 = clock()
  << "mux-only: [appended] segments, [r[:frames]] frames, [r[:audio_samples]] audio samples, [r[:file_bytes]] bytes; append [ms(t0, t1)] ms, close [ms(t1, t2)] ms, total [ms(t0, t2)] ms"
  exit(0)

src = args[0]
out = args[1]
wh = flag(args, "--size", "1920x1080").split("x")
w = wh[0].to_i
h = wh[1].to_i
frames = flag(args, "--frames", "1200").to_i
codec = flag(args, "--codec", "h264")
quality = flag(args, "--quality", "0.6").to_f
input = flag(args, "--input", "rgb24")
gop = flag(args, "--gop", "48").to_i
nses = flag(args, "--sessions", "1").to_i
save_dir = flag(args, "--save-segments", nil)
reorder = args.include?("--reorder")
bpp = input == "rgb24" || input == "bgr24" ? 3 : 4
frame_bytes = w * h * bpp

m = File.mmap(src)
if m.size < frames * frame_bytes
  << "[src] holds [m.size / frame_bytes] frames, fewer than [frames]"
  exit(1)

-> flush_one(queue, head, mux, save_dir)
  s = queue[head]
  queue[head] = nil
  if save_dir != nil
    s.save(save_dir + "/seg_" + head.to_s.rjust(5, "0") + ".h264")
  mux.append(s)
  s.release
  head + 1

t0 = clock()
encs = []
i = 0
while i < nses
  encs.push(VideoEncoder.new(w, h, codec: codec, rate: rate, quality: quality, input: input, gop: gop, reorder: reorder))
  i += 1
mux = Mux.new(out, rate: rate, frames: frames)
queue = []
head = 0
f = 0
cur = 0
while f < frames
  encs[cur].encode(m, w * bpp, f * frame_bytes)
  if (f + 1) % gop == 0 || f == frames - 1
    queue.push(encs[cur].segment)
    cur = (cur + 1) % nses
    # Append segments in order once newer ones are in flight, so the
    # encoders keep working while the mux copies.
    while queue.size - head > nses
      head = flush_one(queue, head, mux, save_dir)
  f += 1
while head < queue.size
  head = flush_one(queue, head, mux, save_dir)
t1 = clock()
conv = ~0.0
wait = ~0.0
encs.each ->(e)
  st = e.stats
  conv += st[:convert_s]
  wait += st[:wait_s]
  e.close
r = mux.close
t2 = clock()
<< "encode_bench: [codec] q=[quality] sessions=[nses] [frames] frames [w]x[h] -> [out]: [r[:file_bytes]] bytes; encode+append [ms(t0, t1)] ms, close [ms(t1, t2)] ms, [(frames.to_f / (t2 - t0)).round] fps; convert [(conv * ~1000.0).round] ms, wait [(wait * ~1000.0).round] ms"
