# Compare bounded asynchronous decoding with the former per-frame wait:
# bin/tungsten -o /tmp/decode-bench --release benchmarks/media/decode_bench.w
# /tmp/decode-bench master.mp4 480
# TUNGSTEN_MEDIA_DECODER_SERIAL=1 /tmp/decode-bench master.mp4 480
args = argv()
limit = args.size > 1 ? args[1].to_i : 480
t0 = clock()
dec = VideoDecoder.new(args[0], format: :nv12)
i = 0
while i < limit && dec.read != nil
  raise "frame order changed at [i] (got [dec.frame])" if dec.frame != i
  i += 1
dec.close
dt = clock() - t0
<< "[i] frames [dt] seconds [i.to_f / dt] fps"
