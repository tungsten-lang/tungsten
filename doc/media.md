# Media: encoding, muxing and verifying video

`core/media` encodes frames with VideoToolbox, writes MP4 and MOV masters with
AVAssetWriter (with timecode and chapter tracks), and reads them back with
AVFoundation to check timing, timecode, chapters, audio and colour. It also
scales frames (Lanczos-3 or bicubic on Metal, vImage or the CPU), decodes
masters and segments with VideoToolbox, and transcodes them into share
copies, 4K masters and a resolution ladder. It replaces the ffmpeg CLI for the
studio pipeline (studio `TIMELINE.md` sections 2-5): frames are encoded once
into closed-GOP **segments**, and a master is a passthrough concatenation of
segments, so an edit re-encodes only the segments whose frames changed.

Like Canvas, it is compiled-only and macOS-only. The tree-walking interpreter
stops with "media is compiled-only". On other targets the bridge is a stub, so
programs link, `VideoEncoder.available?` is false, and any encoder or mux call
raises "media needs macOS VideoToolbox/AVFoundation". `Timecode` and `Flicks`
are pure Tungsten and run everywhere, on both engines.

```tungsten
enc = VideoEncoder.new(1920, 1080, codec: :h264, rate: [24, 1], quality: 0.6)
c = Canvas.new(1920, 1080)
keys = []
f = 0
while f < 96
  draw(c, f)                          # any drawing; one canvas for the whole render
  enc.encode(c)                       # or enc.encode(pointer, stride) / (bytes, stride, offset)
  if (f + 1) % 48 == 0
    seg = enc.segment                 # closes the GOP: IDR + 47 P-frames
    seg.save("build/segments/[f / 48].h264")
    keys << "build/segments/[f / 48].h264"
    seg.release
  f += 1
enc.close

chapters = [["Opening", 0], ["The sieve", 48]]          # (title, first frame)
mux = Mux.new("master.mp4", rate: [24, 1], audio: "mix.wav", tc_start: "00:00:00:00", chapters: chapters)
keys.each ->(k)
  mux.append_file(k)
mux.close                             # {frames:, audio_samples:, audio_source_samples:, video_bytes:, file_bytes:}

r = MediaVerify.check("master.mp4", rate: [24, 1], frames: 96, chapters: chapters)
<< MediaVerify.format(r)              # PASS/FAIL per check

Transcode.run("master.mp4", "share.mp4", preset: :share)  # 720p H.264 + AAC, chapters and tmcd carried
```

## Time

| Call | Does |
| --- | --- |
| `Timecode.rate(r)` | `[num, den]` reduced, from `[24000, 1001]`, `24` or `"24000/1001"` |
| `Timecode.quanta(rate)` | nominal frames per timecode second: 24, 25, 30, 50, 60 |
| `Timecode.drop_frame?(rate)` | true for 30000/1001 and 60000/1001 |
| `Timecode.to_smpte(frame, rate, drop = nil)` | `"HH:MM:SS:FF"`, or `"HH:MM:SS;FF"` for drop-frame |
| `Timecode.parse(label, rate)` | the frame index; raises on labels drop-frame skips |
| `Timecode.samples(frames, rate, sr = 48000)` | audio samples spanning `frames` frames, rounded half up |
| `Timecode.frame_of_sample(sample, rate, sr)` | the frame containing a sample |
| `Flicks.per_frame(rate)`, `Flicks.per_sample(sr)` | flicks (1/705,600,000 s) per frame or sample, exact |
| `Flicks.from_frame / from_sample / from_ms` | to flicks |
| `Flicks.to_frame(fl, rate)`, `to_sample`, `to_ms` | back, rounding half up (the snapping rule) |

A frame `f` starts at `f × den / num` seconds. Timecode is a presentation of
the frame index, never a key: non-drop for integer rates and 24000/1001,
drop-frame for 30000/1001 and 60000/1001 (labels `;00` and `;01`, or `;00`-`;03`
at 59.94, are skipped at every minute except each tenth), wrapping at 24 hours.

The snapping rule is round half up: `frame = floor((2 · flicks · num + 705600000 · den) / (2 · 705600000 · den))`.
(TIMELINE.md section 2 writes the half-frame term as `den · FPF/2`; the term
that rounds to the nearest frame is `705600000 · den / 2`, which is `num · FPF/2`.
`Flicks.to_frame` uses the correct one.)

## VideoEncoder

`VideoEncoder.new(width, height, opts)`:

| Option | Default | Meaning |
| --- | --- | --- |
| `codec` | `:h264` | `:h264` (High), `:hevc` (Main), `:hevc10` (Main10), `:prores422`, `:prores422hq`, `:prores422lt`, `:prores422proxy` |
| `rate` | `[24, 1]` | frame rate, as for `Timecode.rate` |
| `quality` | 0.75 | VideoToolbox constant quality, 0..1 (H.264/HEVC) |
| `bitrate` | nil | average bits per second instead of `quality` |
| `gop` | 48 | keyframe backstop for segments longer than this |
| `input` | `:rgba` | `:rgba`, `:bgra`, `:argb`, `:rgb24`, `:bgr24` |
| `siting` | `:left` | 4:2:0/4:2:2 chroma siting: `:left`, `:center`, `:topleft` |
| `reorder` | true | B-frames inside a segment (H.264/HEVC); false keeps decode order = presentation order |
| `speed` | false | ask VideoToolbox to favour speed over quality |
| `source` | nil | `[w, h]`: take frames of that size (RGBA/BGRA) and scale each to the encoder's size first (`filter`, `fit`, `crop`, `rect`, `fill`, `scale_backend` as for `Scaler`) |

| Call | Does |
| --- | --- |
| `encode(canvas)` | encode a Canvas's pixels (premultiplied RGBA, taken as composited over black) |
| `encode(pixels, stride = nil, offset = 0)` | an address (`Canvas#data_pointer`), a ByteArray / `u8[]`, or an `Mmap` |
| `segment` | close the open GOP and return it as a `VideoSegment` |
| `frames`, `segments`, `stats` | counters; `stats` adds conversion and wait seconds |
| `close` | finish frames in flight; frames since the last `segment` are discarded |
| `VideoEncoder.codecs` | codec names VideoToolbox opens on this machine |
| `VideoEncoder.stats` | native encoders, segments, segment bytes and muxes alive |

### Colour

Frames are R'G'B' code values. They are converted to Y'CbCr in
`runtime/media/media.c`, not inside VideoToolbox, so the matrix, range and
siting are explicit: the BT.709 matrix (Kr 0.2126, Kb 0.0722), limited range
(8-bit Y' 16-235, C 16-240; 10-bit 64-940, 64-960), chroma filtered `[1 2 1]/4`
on co-sited axes and `[1 1]/2` on midway axes. H.264 and HEVC take 4:2:0
(`420v`, or `x420` for `:hevc10`); ProRes takes 10-bit 4:2:2 (`x422`).

The planes are bit-for-bit `YuvFrame.from_rgba(...)` as the compiled engine
computes it. Codes are computed in 2^-30 fixed point (about 0.5 ms of wall
time, 2-3 ms of CPU, per 1080p frame); a sample whose fixed-point value lies
within a guard band of a rounding tie (far wider than the fixed-point error
bound; about one sample in 10^5) is recomputed with `core/ycbcr.w`'s double
arithmetic. `spec/core/media_spec.w` checks a frame holding every 8-bit RGB
triple. Note that compiled Tungsten fuses `a * b + c` in typed float code into
a fused multiply-add and the interpreter does not, so the two engines'
`YuvFrame` can differ by one code on such near-tie inputs; the converter
follows the compiled engine.

The pixel buffers, the session and the format description carry BT.709
primaries, transfer and matrix (1/1/1), limited range and the chroma
location; VideoToolbox writes primaries/transfer/matrix and the range into
the SPS VUI. The old ffmpeg path (`-pix_fmt yuv420p` from RGB) used swscale's
default BT.601 matrix with no tags, which BT.709 players decode with a hue and
luma shift (red: BT.709 Y'CbCr 63/102/240, BT.601 81/90/240).

### Segments and parameter sets

A segment is one closed GOP: the first frame is a forced IDR (H.264 NAL 5,
HEVC IDR_N_LP), and B-frames (`reorder: true`, the default) only reorder frames
inside it, so nothing refers across a segment boundary. With reordering the
keyframe backstop doubles to 2 × `gop`, because VideoToolbox plans keyframes a
mini-GOP ahead and would otherwise add one a few frames before each forced
IDR. Frames are
encoded asynchronously: `segment` returns at once, and the first use of the
segment (`frames`, `save`, `Mux#append`) waits for its samples. Keep encoding
the next segment before saving the previous one to keep the hardware busy.

H.264 and HEVC parameter sets live in the format description (`avcC` /
`hvcC`, sample entries `avc1` / `hvc1`), not in the samples. Measured on
macOS 27 / M5 Max: VideoToolbox derives them from the settings alone. Two
sessions with the same codec, size, profile and quality emit byte-identical
SPS/PPS (and VPS), whatever the content or the segment length (1 to 48
frames tried). HEVC's also change with `quality` and with frame reordering;
H.264's change with neither. So segments encoded by any number of encoders,
in any order, concatenate under one sample description, and the mux refuses
a segment whose format description differs from the first segment's
("encoded with different settings") instead of writing a stream a decoder
would mis-read. In-band parameter sets (`avc3` / `hev1`) are not needed.

Segment files (`VideoSegment#save`, `VideoSegment.load`; little-endian):

| Offset | Field |
| --- | --- |
| 0 | `"TWMS"`, u32 version 1, u32 header size 64 |
| 12 | u32 codec fourcc, i32 width, i32 height, i32 rate num, i32 rate den |
| 32 | u32 sample count, u32 format bytes, u64 data bytes, i32 DTS delay, u32 flags, u64 reserved |
| 64 | the format description's extensions as a binary property list (colour tags, `avcC`/`hvcC`) |
| … | one 24-byte record per sample in decode order: u64 offset, u32 size, i32 pts, i32 dts, u8 sync, 3 bytes 0 |
| … | sample data: length-prefixed NAL units, or one ProRes frame per sample |

## Mux

`Mux.new(path, opts)` writes MP4 or MOV (from the extension, or `format:`):

| Option | Default | Meaning |
| --- | --- | --- |
| `rate` | `[24, 1]` | must match the segments |
| `audio` | nil | a WAV file (16/24/32-bit PCM or 32/64-bit float, any rate, up to 8 channels), or a movie whose first audio track is decoded (or passed through) |
| `audio_codec` | `:aac` (MP4), `:pcm` (MOV) | MOV PCM is 24-bit; `:copy` passes a movie's track through unchanged |
| `audio_kbps` | 320 stereo, 192 mono | AAC bitrate |
| `tc_start` | `"00:00:00:00"` | start of the `tmcd` track; nil for none |
| `drop` | auto | drop-frame timecode (30000/1001 and 60000/1001) |
| `faststart` | true | moov before the media data |
| `frames` | nil | promise the frame count, so the audio is fed exactly |
| `chapters` | nil | `[[title, first frame], ...]` (or `mux.chapter(title, frame)`) |
| `chpl` | true (MP4) | also write Nero `chpl` chapters |

`append(segment)` and `append_file(path)` copy a segment's samples in order;
`close` finishes the file and returns `{frames:, audio_samples:,
audio_source_samples:, video_bytes:, file_bytes:}`.

- **Timing.** Every PTS is rewritten to `frame × den/num` in a track timescale
  where a frame is a whole number of ticks: 24 fps uses 24000 (1000 ticks a
  frame), 25 uses 25000, 24000/1001 uses 24000 (1001 ticks), 30000/1001 and
  60000/1001 use 30000 and 60000. Every sample lasts exactly one frame, so the
  file is constant frame rate with exact timestamps.
- **B-frames.** Decode timestamps are the segment's sorted PTS minus a delay
  fixed for the whole file (4 frames when the first segment was encoded with
  reordering, enough for VideoToolbox's B-pyramid, whose measured depth is 2),
  so DTS rise monotonically across segments of any length; AVAssetWriter
  stores the shift as an edit list, which players and `MediaVerify` apply.
- **Audio.** The WAV is fed in 100 ms buffers interleaved with the video and
  padded with silence or trimmed to exactly `Timecode.samples(frames, rate,
  wav_rate)` samples. AVAssetWriter's AAC edit list hides the encoder priming
  (2112 samples), so audio sample 0 plays with video frame 0; `MediaVerify`'s
  sync test measures it.
- **Timecode.** AVAssetWriter takes a timecode input only for QuickTime movies
  and needs its sample's duration before writing starts, so the `tmcd` track is
  added after AVAssetWriter finishes, for MP4 and MOV alike: the moov is parsed,
  a timecode trak (with the video trak's `tref`) is inserted, the 4-byte frame
  number goes in a 12-byte mdat at the end, and the moov moves to the front
  with every chunk offset relocated (an `stco` that would overflow becomes
  `co64`). The layout follows ffmpeg's `-timecode` output (`nmhd` in MP4,
  `gmhd`/`tcmi` in MOV) with the 24-hour flag, and the drop-frame flag for
  29.97 and 59.94.
- **Chapters.** `chapters: [[title, first frame], ...]` (ascending; or
  `mux.chapter(title, frame)` before `close`) adds a QuickTime chapter track,
  in MP4 and MOV alike: a disabled text track (`text` sample entry, `gmhd`)
  with one sample per chapter, the UTF-8 title followed by an `encd` atom
  (ffmpeg's chapter samples), lasting until the next chapter, the last until
  the end of the video. The video and audio tracks reference it through
  `tref`/`chap`, which is how AVFoundation (`chapterMetadataGroups`), QuickTime
  Player and ffprobe find it. The track's timescale is the video's, so every
  chapter starts on an exact frame; a first chapter after frame 0 sits behind
  an empty edit. MP4s also get a Nero `chpl` box in `moov/udta` (starts in
  100 ns units, rounded; titles cut to 255 bytes at a UTF-8 boundary; at most
  255 chapters) for players that read only that; `chpl: false` leaves it out.
  The chapter track goes in with the `tmcd` patch below (one moov rewrite for
  both).
- **Chapters on an existing file.** `Mux.chapterize(src, dst, chapters,
  rate: nil)` adds the same chapter track (and `chpl`) to a movie that has
  none, without touching its samples: the moov is rewritten moov-first and
  the media data copied once (3 GB in a few seconds). The video must be
  constant frame rate in a timescale where a frame is whole ticks (every
  `Mux` master is).

## MediaVerify

`MediaVerify.check(path, opts)` returns `{ok:, path:, rate:, frames:, checks:,
facts:}`; `MediaVerify.format(r)` prints one PASS/FAIL line per check with the
measured values. Options: `rate` (inferred from the minimum frame duration
when absent), `frames`, `tc_start` (nil: no timecode expected), `drop`, `audio`
(false: none expected), `siting`, `faststart`, `sync`, `flashes`, `bars`,
`chapters`, `chpl`.

| Check | Passes when |
| --- | --- |
| video | one video track, one sample description, every sample read |
| cfr | every sample lasts den/num s exactly; the nominal rate matches |
| pts | the sorted presentation times (sample PTS through the edit list) are exactly `frame × ticks`, from 0, all representable |
| frames | the count equals `frames:` |
| timecode | one `tmcd` track associated with the video, starting at `tc_start`, drop flag and quanta right for the rate, spanning every frame |
| audio | audio starts at 0, lasts as long as the video, decodes to exactly `Timecode.samples(frames)` samples |
| colour | container tags BT.709 1/1/1, not full range, chroma location stated; SPS VUI 1/1/1, limited range, matching chroma_sample_loc_type |
| faststart | the moov precedes the mdat |
| sync | every flash frame has a click at its first audio sample within ±1 sample, and the flash frames are the expected ones |
| bars | the decoded Y'CbCr of each colour bar matches BT.709 limited-range codes and not BT.601's, and decoded RGB matches the encoded RGB |
| chapters | AVFoundation's chapter groups have exactly the expected titles, each starting at `frame × den/num` s and lasting until the next (the last until the end); in an MP4, `chpl` agrees (starts rounded to 100 ns) |

`MediaVerify.sync_test(path, opts)` writes a test master through the real
encoder and mux: black frames with a white flash every two seconds, 75%
colour bars in the bottom third, and a click (a 9-sample raised cosine
peaking at the flash frame's first sample) in a WAV it writes next to it.

From the shell:

```sh
bin/tungsten media verify master.mp4 --rate 24/1 --frames 56002
bin/tungsten media sync-test /tmp/sync.mp4 --rate 30000/1001 --tc "00:59:59;00"
bin/tungsten media verify /tmp/sync.mp4 --sync --bars --rate 30000/1001 --tc "00:59:59;00"
bin/tungsten media probe master.mp4     # raw AVFoundation facts
bin/tungsten media codecs
bin/tungsten media tc 56001 24/1        # 00:38:53:09
bin/tungsten media verify master.mp4 --chapters chapters.frames.txt   # "frame title" or "HH:MM:SS:FF title" lines
bin/tungsten media transcode master.mp4 share.mp4 --size 1280x720 --kbps 2500 --audio aac --audio-kbps 128 --verify
bin/tungsten media preset share master.mp4 share.mp4                 # the preset, then Transcode.check
bin/tungsten media preset 2160p master.mp4 yt4k.mp4
bin/tungsten media preset share build/full/segments.txt share.mp4 --rate 24/1 --audio-src build/full/mix.wav \
    --chapters chapters.frames.txt                                   # straight from the engine's segments
bin/tungsten media presets
```

`verify`, `transcode --verify` and `preset` exit 0 when every check passes.
A transcode source may be a movie or a list of segment files (a text file of
paths, or of ffmpeg concat lines `file '...'` like the engine's
`segments.txt`).

## Scaler

`core/media/scaler.w`: high-quality resampling of RGBA frames (any order with
alpha last) for share copies, 4K masters from 1080p renders, and vertical
crops and pads.

```tungsten
sc = Scaler.new(1920, 1080, 1280, 720)                    # Lanczos-3, the fastest backend
small = sc.scale(canvas)                                  # a new ByteArray, or sc.scale(canvas, buf)
up = Scaler.new(1920, 1080, 3840, 2160, filter: :bicubic)
v = Scaler.new(1920, 1080, 1080, 1920, fit: :cover)       # centre crop 607.5 x 1080, no bars
p = Scaler.new(1920, 1080, 1080, 1920, fit: :contain)     # whole frame in 1080 x 608, black bars
enc = VideoEncoder.new(3840, 2160, codec: :hevc, source: [1920, 1080])   # the encoder scales each frame itself
```

| Option | Default | Meaning |
| --- | --- | --- |
| `filter` | `:lanczos3` | `:lanczos3` (radius 3), `:bicubic` (Keys a = -0.5, Catmull-Rom), `:bilinear` |
| `fit` | `:stretch` | `:stretch`, `:contain` (whole source, centred, `fill` bars), `:cover` (fill, centre crop) |
| `crop` | from `fit` | source region `[x, y, w, h]`; fractional values are exact |
| `rect` | from `fit` | destination region `[x, y, w, h]` |
| `fill` | `[0, 0, 0, 255]` | colour outside `rect` |
| `alpha` | `:premultiplied` | `:premultiplied` (Canvas), `:straight`, `:opaque`, `:none` |
| `backend` | `:auto` | `:metal`, `:vimage`, `:cpu` |

`scale(src, dst = nil, src_stride = nil, dst_stride = nil)` takes a Canvas,
an address, a ByteArray / `u8[]` or an Mmap; `Scaler.fit(sw, sh, dw, dh,
mode)` returns the crop and rect a mode uses; `backend`, `taps`, `seconds`,
`runs`, `weights(:x | :y)` describe a scaler; `free` releases its native plan
and GPU buffers. `Scaler.backends` lists what this machine has.

- **Mapping.** Destination pixel `x` samples the source at
  `crop_x + (x - rect_x + 0.5) * crop_w / rect_w - 0.5` (pixel centres), so a
  2x upscale is phase-correct, a crop is not shifted by half a pixel, and a
  same-size scale is an exact copy.
- **Filters.** Separable, with weights computed once per scaler in double
  precision, normalised to sum 1, the edge samples repeated (folded into the
  edge weight). When downscaling, the kernel is stretched by the scale factor
  (1080p to 720p reads 9 taps a pixel with Lanczos-3, to 480p 14), so it stays
  a low-pass filter at the output rate: a 1-pixel checkerboard scaled by 1/3
  comes out flat grey.
- **Alpha.** Premultiplied input is filtered as it is, then each colour is
  clamped to the pixel's alpha: Lanczos and bicubic ring, and a colour above
  its alpha is not a valid premultiplied pixel (it would brighten when
  composited). `:straight` premultiplies on load and divides on store, so a
  transparent pixel's colour cannot bleed into an opaque neighbour.
  `:opaque` ignores the input alpha and writes 255.
- **Backends.** `:cpu` is multithreaded C (32 bands of output rows, a
  horizontal pass over just the source rows a band needs, then a vertical
  pass, float4 arithmetic). `:metal` runs the same weight tables in two
  compute passes (a float intermediate in private GPU memory); the source and
  destination are wrapped in place (the pages that hold them, bound at the
  buffer's offset), so a frame is not copied, and several plans (a frame's
  Y' and CbCr planes) share one command buffer. Metal and the CPU agree to
  within one code (bit-identical on most jobs). `:vimage` is Accelerate's
  `vImageScale_ARGB8888` / `Planar8` / `CbCr8`, which has its own Lanczos-3
  (Lanczos-5 with its high-quality flag, not used) and maps whole-pixel
  source rects only; colours are clamped to alpha afterwards
  (`vImageScale` leaves them above it). Metal.framework and Accelerate are
  opened with `dlopen` on first use, so the media link line does not change
  and programs that never scale do not load them; `TUNGSTEN_MEDIA_NO_METAL=1`
  hides Metal.

## VideoDecoder

`VideoDecoder.new(source, format: :rgba, start: 0, rate: nil)` decodes a
movie's first video track (AVAssetReader passthrough samples) or a list of
segment files with a `VTDecompressionSession` (hardware) on a thread of its
own, and hands frames out in presentation order: `read(buf = nil, stride =
nil)` fills `buf` (or one buffer the decoder keeps) and returns it, or nil at
the end; `frame` is the index of the frame just read, `frames` the count the
movie's duration implies. `format:` is `:rgba`, `:bgra` (VideoToolbox's
BT.709 conversion, from the stream's tags) or `:nv12` (the decoded 8-bit
4:2:0 planes, Y' then CbCr, no conversion).

- **Order.** Samples are fed in decode order and decoded one at a time;
  a decoded frame is handed out once no frame still to come can precede it:
  its time is below the next sample's decode time (DTS <= PTS) and below every
  frame VideoToolbox still holds. Frames are identified by the sample they came
  from (the decode call's refcon), because VideoToolbox reports a frame at its
  output time (the movie's edit list applied: our B-frame masters shift by 4
  frames), not the media time the sample carries.
- **Index.** A frame's index is its presentation time times the rate,
  rounded, so a master whose frame times wander a little (the legacy
  Archimedes master has a 513-tick frame) still maps every frame to its own
  index.

## Transcode

`Transcode.run(src, dst, opts)` decodes, scales, encodes and muxes in one
pass with no ffmpeg; `Transcode.check(path, opts)` verifies the result.

```tungsten
r = Transcode.run("master.mp4", "share.mp4", preset: :share)       # 720p H.264 + AAC; chapters, tmcd kept
r = Transcode.run("master.mp4", "yt4k.mp4", preset: "2160p")      # 4K from 1080p, Lanczos-3, AAC passed through
r = Transcode.run("master.mp4", "clip.mp4", start: 41760, frames: 2400, width: 1280, height: 720)
r = Transcode.run(segment_paths, "share.mp4", rate: [24, 1], audio_src: "mix.wav", preset: :share, chapters: chs)
<< MediaVerify.format(Transcode.check("share.mp4", preset: :share, frames: 56002, chapters: chs))
```

| Option | Default | Meaning |
| --- | --- | --- |
| `preset` | nil | fills in the options below (explicit ones win) |
| `width`, `height` | the source's | output size (even) |
| `fit`, `crop`, `rect`, `filter`, `scale_backend` | `:stretch`, ..., `:lanczos3`, `:auto` | as for `Scaler` |
| `via` | `:yuv` | `:yuv` resamples the decoded Y' and CbCr planes; `:rgb` decodes to BGRA, scales RGBA, converts back |
| `codec`, `quality`, `bitrate`, `gop`, `gop_seconds`, `reorder`, `speed` | `:h264`, ..., 1 s | as for `VideoEncoder`; a segment (closed GOP) is `gop` frames |
| `level` | lowest that fits | H.264 level (`"3.1"` ... `"5.2"`); VideoToolbox picks HEVC's |
| `audio` | `:copy` | `:copy` (passthrough), `:aac`, `:pcm` (MOV), false |
| `audio_src`, `audio_kbps` | the source, preset | a WAV or movie to take the sound from |
| `chapters` | `:copy` | `:copy` (the source's chapter track), `[[title, frame], ...]`, false |
| `tc` | `:copy` | `:copy` (the source's tmcd start; segments: 00:00:00:00), a label, false |
| `start`, `frames` | 0, the rest | a range of the source (movies) |
| `rate` | the source's | needed for segments |
| `format`, `faststart`, `progress` | from `dst`, true, false | |

The result: `{frames:, duplicated:, dropped:, seconds:, fps:, decode_s:,
scale_s:, encode_wait_s:, mux_s:, scale_backend:, via:, file_bytes:,
video_bytes:, audio_samples:, chapters:, tc_start:, level:, ...}`.

- **Y'CbCr path** (default): the decoder gives 8-bit 4:2:0 and the scaler
  resamples the Y' plane and the interleaved CbCr plane separately, straight
  from the decoder's buffer into the encoder's pool buffer, with the chroma
  siting honoured on both sides (the source's from its format description,
  left for ours; a left-sited 4:2:0 chroma sample sits on luma column 2i and
  between luma rows 2j and 2j+1). There is no colour conversion at all, so
  the master's BT.709 code values carry over, as in `ffmpeg -vf scale` on
  yuv420p. Pads are Y' 16, CbCr 128.
- **RGB path** (`via: :rgb`): BGRA from VideoToolbox, the RGBA scaler
  (`alpha: :opaque`), then `media.c`'s converter: what a render scaled to 4K
  goes through.
- **Frames.** The copy has exactly `frames` frames, constant rate: a decoded
  frame whose index was already written is dropped and a gap repeats the
  previous frame (both counted; 0 and 0 on every master tried).
- **Audio.** `:copy` appends the source's AAC packets unchanged
  (AVAssetWriter keeps the priming and trim, so sample 0 still plays with
  frame 0); `:aac` / `:pcm` decode the source track with AVAssetReader (which
  applies its edit list, giving the exact samples) and re-encode them like a
  WAV. A range, or a WAV source, always re-encodes.
- **Chapters and timecode** carry through: chapter times are read through
  AVFoundation and converted back to frames (exact, since `Mux` wrote them on
  frames), shifted by `start:` (the chapter running at `start` moves to frame
  0); the tmcd start moves by `start:` too.
- **Pipeline.** Decoding runs on its own thread (6 frames ahead); scaling and
  submission on the caller's; VideoToolbox encodes asynchronously; each
  closed segment is appended to the mux two segments behind, so the encoder
  is never waited on. `Transcode.run` steps the native transcoder ~10 s of
  video at a time (`progress: true` prints a line each step) and frees it
  (deleting the partial file) if anything raises.

### Presets

`Transcode.presets` (`bin/tungsten media presets`):

| Preset | Size | Codec | Video | Audio | Fit | Level cap |
| --- | --- | --- | --- | --- | --- | --- |
| `share` | 1280 x 720 | H.264 High | 2.5 Mb/s, 2 s GOP | AAC 128k | | 4.0 |
| `480p` | 854 x 480 | H.264 High | 2.5 Mb/s | AAC 128k | | 3.1 |
| `720p` | 1280 x 720 | H.264 High | 5 Mb/s | AAC 192k | | 4.0 |
| `1080p` | 1920 x 1080 | H.264 High | 8 Mb/s | copy | | 4.2 |
| `1440p` | 2560 x 1440 | H.264 High | 16 Mb/s | copy | | 5.1 |
| `2160p` (`4k`) | 3840 x 2160 | H.264 High | 40 Mb/s | copy | | 5.2 |
| `4320p` (`8k`) | 7680 x 4320 | HEVC Main | 120 Mb/s | copy | | 6.2 |
| `vertical` | 1080 x 1920 | H.264 High | 8 Mb/s | AAC 192k | cover | 4.2 |
| `vertical_pad` | 1080 x 1920 | H.264 High | 8 Mb/s | AAC 192k | contain | 4.2 |
| `vertical4k` | 2160 x 3840 | H.264 High | 40 Mb/s | copy | cover | 5.2 |

The ladder bitrates are YouTube's recommended SDR upload rates (24-30 fps;
`youtube_master.sh` uses the same table); GOP half a second unless set,
B-frames on, BT.709 tags, faststart. H.264 stops at 4096 x 2304 (level 5.2,
36,864 macroblocks a frame), so 8K is HEVC. The H.264 level is pinned to the
lowest level whose MaxFS, MaxMBPS (Table A-1) and MaxBR (High: 1.25 x, with
1.5 x the average for peaks) hold the job; `Transcode.min_level(codec, w, h,
rate, bits)` computes it (HEVC: Table A.8, Main tier).

`Transcode.check(path, preset:, ...)` runs every MediaVerify check (pass
`chapters:`, `frames:`, `tc_start:` as for `MediaVerify.check`) plus
`preset`: sample entry `avc1` / `hvc1`, profile (High 100 / Main 1), 8-bit,
4:2:0, the size, the stream's level at least the minimum the picture needs and
at most the preset's cap, and the average bitrate within that level's MaxBR.

## How it is built

- **Runtime:** `runtime/media/media.c` (handle registry, converter,
  VideoToolbox sessions, segments, SPS/VUI parser, WAV reader, the scaler's
  weight tables and its CPU and vImage backends) and
  `runtime/media/media_avf.m` (AVAssetWriter mux with WAV / decoded /
  passthrough audio, the `tmcd` and chapter moov patch, AVAssetReader
  probes, the Metal scaler, the decoder thread and the transcoder; manual
  retain/release like `metal.m`). The ccalls are listed once,
  with their arities, in `W_MEDIA_CCALLS` in `runtime/media/media.h`; the
  non-Apple half of `media.c` generates raising stubs from that list.
- **Link gate:** the compiler links the bridge only when a program's IR
  references `@w_media_` (`ll_needs_media` in `compiler/lib/driver/ir.w`): `media.c`
  on every target, `media_avf.m` on macOS, with `-framework VideoToolbox
  CoreMedia CoreVideo AVFoundation AudioToolbox Foundation CoreFoundation`.
  Canvas-only and Metal-only programs link none of them. Metal.framework
  and Accelerate (vImage) are not on that line: the scaler opens them with
  `dlopen` the first time it needs them (`MTLCreateSystemDefaultDevice` and
  three `vImageScale_*` entry points by `dlsym`; everything else in Metal is
  Objective-C messaging), so the gate is unchanged and a program that never
  scales never loads them.
- **Handles:** encoders, segments, muxes, scalers, decoders and transcoders
  are generation-checked integer handles; a released handle raises instead
  of touching freed memory. There are no finalizers: `release` segments,
  `close` encoders and decoders, `free` scalers (`Transcode.run` frees its
  transcoder itself, also when it raises).

## Performance

`benchmarks/media/run.sh` (with `encode_bench.w` built `--release`) encodes the
same raw frames with each contender and scores the output with libvmaf
(VMAF v0.6.1 and SSIM, luma) against those frames, after converting both to
BT.709 4:2:0 (each output is first decoded with the matrix it was encoded
with, so the untagged BT.601 libx264 file is not penalised for its tags).

Apple M5 Max, macOS 27, 2026-10-22: 2,400 frames (100 s, two runs of 1,200)
of the Archimedes & Eratosthenes episode at 29:00-30:40 (catapults, iron
hand), 1920 x 1080 at 24 fps, decoded once to RGB24. Wall and CPU (user + sys)
are `/usr/bin/time -l`; memory is the peak footprint (encode_bench maps the
raw file, so its resident size counts page cache). VideoEncoder numbers
include its RGB -> Y'CbCr conversion, segmenting, the mux, the tmcd patch
and faststart.

| Encoder | Wall s | CPU s | Memory MB | Output MB | VMAF | SSIM |
| --- | --- | --- | --- | --- | --- | --- |
| ffmpeg libx264 `-preset medium -crf 18 -x264-params keyint=48` (today's master) | 13.34 | 194.0 | 1028 | 186.5 | 96.91 | 0.99885 |
| ffmpeg `h264_videotoolbox -q:v 75` | 4.80 | 8.5 | 178 | 251.5 | 96.80 | 0.99852 |
| ffmpeg `hevc_videotoolbox -q:v 73` | 4.98 | 8.5 | 172 | 170.2 | 96.37 | 0.99810 |
| VideoEncoder H.264, quality 0.75 | 5.56 | 9.4 | 127 | 211.9 | 96.89 | 0.99860 |
| VideoEncoder H.264, quality 0.80 | 6.39 | 9.4 | 222 | 314.3 | 97.79 | 0.99920 |
| VideoEncoder HEVC, quality 0.73 | 5.21 | 9.5 | 73 | 133.2 | 96.35 | 0.99812 |
| VideoEncoder HEVC, quality 0.75 | 5.26 | 9.4 | 77 | 159.8 | 96.83 | 0.99846 |
| VideoEncoder HEVC, quality 0.80 | 5.27 | 9.2 | 193 | 263.1 | 97.85 | 0.99918 |

- At libx264's VMAF, HEVC at quality 0.75 is 2.5 times faster, uses 21 times
  less CPU and 13 times less memory, and its file is 14% smaller; H.264 at
  0.75 matches the VMAF with a file 14% larger.
- VideoToolbox's quality setting is coarse: 0.74 and 0.75 give the same
  stream. B-frames (`reorder: true`) are what make HEVC smaller than libx264:
  at the same quality they cut 13% (H.264) to 19% (HEVC), and against
  ffmpeg's own VideoToolbox encoders at equal VMAF the files are 16-22%
  smaller.
- CPU per 1080p frame is about 3.9 ms, of which about 1 ms is page faults on
  the mapped input and 1-2 ms the conversion (0.4 ms wall on 16 threads).
  ffmpeg's VideoToolbox path, converting with swscale, uses 3.5 ms.
- Two encoder sessions in one thread are slower than one (312 against 460
  fps): one session keeps the media engine busy.
- Passthrough mux of a 39-minute master from segment files: 1,167 segments
  (56,002 frames, 3.1 GB HEVC) in 1.9 s with a 41 MB footprint, including the
  tmcd patch and the faststart rewrite; 9.4 s with 39 minutes of PCM encoded
  to AAC. `MediaVerify.check` on that master takes 2 s and passes every check.

### Scaling

`benchmarks/media/scale_bench.w` (built `--release`) decodes real frames with
`VideoDecoder` and times every backend over them (median of three passes);
`benchmarks/media/scale_vs_ffmpeg.sh` compares the CPU backend's output with
ffmpeg's `scale` filter on the same RGBA input. Apple M5 Max, macOS 27,
2026-10-22: 12 frames of the Archimedes & Eratosthenes master from 29:00
(1920 x 1080 RGBA, `u8[]` buffers, so Metal wraps pages rather than
aligned buffers), ms per frame:

| Job | Filter | Metal | CPU | vImage |
| --- | --- | --- | --- | --- |
| 1280 x 720 (share) | Lanczos-3 | **0.68** | 0.71 | 0.98 |
| 1280 x 720 | bicubic | **0.55** | 0.59 | n/a |
| 3840 x 2160 (4K) | Lanczos-3 | **1.76** | 2.77 | 2.99 |
| 3840 x 2160 | bicubic | **1.56** | 2.13 | n/a |
| 854 x 480 | Lanczos-3 | **0.62** | 1.06 | 0.82 |
| 854 x 480 | bicubic | **0.59** | 0.74 | n/a |
| 1080 x 1920 cover (crop 607.5 x 1080) | Lanczos-3 | **0.69** | 0.87 | n/a (fractional crop) |
| 1080 x 1920 cover | bicubic | 0.64 | **0.56** | n/a |
| 1080 x 1920 contain (bars) | Lanczos-3 | **0.73** | 0.90 | 2.93 |
| 1080 x 1920 contain | bicubic | **0.59** | 0.75 | n/a |

- Metal is the fastest or within noise on every job, so it is the default;
  the CPU backend is the fallback (and the only one for 10-bit planes).
  Below about 0.6 ms Metal's time is mostly the command buffer round trip.
  vImage is slower than both except at 480p, where it beats the CPU.
- Metal against the CPU: at most 1 code apart, RMS 0.002 (fused
  multiply-adds round differently); bit-identical on the 4K bicubic job.
  vImage's own Lanczos-3 differs from ours by up to 18 codes (RMS 0.36-0.52)
  at edges.
- Against ffmpeg's swscale (`-sws_flags lanczos+accurate_rnd+full_chroma_int`)
  on the same RGBA frames: Lanczos-3 PSNR 68.6 dB / SSIM 0.99996 at 720p,
  68.4 dB / 0.99993 at 4K, 61.0 dB / 0.99988 at 480p, i.e. the same filter.
  Bicubic 53.8-55.1 dB: swscale's bicubic is B = 0, C = 0.6 (a = -0.6), ours
  Catmull-Rom (a = -0.5).

### Transcoding (Archimedes & Eratosthenes, 2026-10-22)

The engine's rebuild (`studio/build/full`: 1,232 HEVC segments, 56,002 frames
at 24 fps, `mix.wav`, 51 chapter markers in `timeline.resolved.json`):

| Job | Wall s | CPU s | Footprint MB | Output | Checks |
| --- | --- | --- | --- | --- | --- |
| Chaptered master: passthrough re-mux of the segments + AAC from the mix + 51 chapters + tmcd | 9.7 (11.6 with startup) | 14.5 | 153 | 2.99 GB | MediaVerify 9/9 incl. chapters; ffprobe: 51 chapters, starts on frames (587000/24000 s ...) |
| Share copy: `preset: :share` from that master (HEVC 1080p -> H.264 720p 2.5 Mb/s, AAC 128k) | 66.7 (840 fps) | 34.8 | 222 | 763 MB (2,486 kb/s video) | MediaVerify 10/10 incl. chapters (51), tmcd, audio 112,004,000 samples; preset (level 3.1, cap 4.0) |
| 4K: `preset: "2160p"`, 2,400 frames from 29:00 (H.264 40 Mb/s, level 5.1), Y'CbCr path | 19.4 (124 fps) | 15.2 | 444 (both runs) | 506 MB | all pass |
| the same through the RGB path (BGRA decode, RGBA scaler, converter) | 19.3 (124 fps) | 15.2 | | 506 MB | all pass |

- Share copy breakdown: the decoder thread was busy 53 s (synchronous
  hardware decode), scaling 34 s (Metal, both planes in one command buffer,
  0.6 ms a frame), submission 19 s; the encoder was never waited on (6 ms).
  At 4K the H.264 encoder is the limit (14 s of the 19 s is submission
  backpressure), so the Y'CbCr and RGB paths take the same time.
- Quality of the share copy against ffmpeg's Lanczos 720p of the master
  (`scale=1280:720:flags=lanczos+accurate_rnd+full_chroma_int`, yuv420p),
  libvmaf v0.6.1 over all 56,002 frames, with ffmpeg's own share copies from
  the same master for context:

| Share copy | Wall s | CPU s | File MB | VMAF mean (min) | SSIM | PSNR-Y dB |
| --- | --- | --- | --- | --- | --- | --- |
| `Transcode` `preset: :share` (VideoToolbox H.264 2.5 Mb/s) | 66.7 | 34.8 | 763 | 94.92 (71.1) | 0.99794 | 46.16 |
| ffmpeg Lanczos + libx264 `-preset medium -b:v 2500k -maxrate 3750k -bufsize 5000k -g 48` | 133.5 | 1,857 | 635 | 95.75 (79.4) | 0.99787 | 48.45 |
| ffmpeg Lanczos + `h264_videotoolbox -b:v 2500k -g 48` | 69.5 | 672 | 638 | 93.52 (44.3) | 0.99687 | 46.82 |

  The share copy beats ffmpeg's VideoToolbox path on VMAF (worst frame 71
  against 44) and SSIM in the same wall time with 19x less CPU; libx264
  medium scores 0.8 VMAF higher with a 17% smaller file at 53 times the CPU.
  VideoToolbox holds the average bitrate closely (2,486 of 2,500 kb/s);
  libx264 and ffmpeg's VideoToolbox wrapper undershoot to about 2.05 Mb/s on
  this mostly still material, hence the smaller files.
