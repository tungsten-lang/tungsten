# Media: encoding, muxing and verifying video

`core/media` encodes frames with VideoToolbox, writes MP4 and MOV masters with
AVAssetWriter, and reads them back with AVFoundation to check timing, timecode,
audio and colour. It replaces the ffmpeg CLI for the studio pipeline (studio
`TIMELINE.md` sections 2-5): frames are encoded once into closed-GOP
**segments**, and a master is a passthrough concatenation of segments, so an
edit re-encodes only the segments whose frames changed.

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

mux = Mux.new("master.mp4", rate: [24, 1], audio: "mix.wav", tc_start: "00:00:00:00")
keys.each ->(k)
  mux.append_file(k)
mux.close                             # {frames:, audio_samples:, audio_source_samples:, video_bytes:, file_bytes:}

r = MediaVerify.check("master.mp4", rate: [24, 1], frames: 96)
<< MediaVerify.format(r)              # PASS/FAIL per check
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
| `audio` | nil | a WAV file: 16/24/32-bit PCM or 32/64-bit float, any rate, up to 8 channels |
| `audio_codec` | `:aac` (MP4), `:pcm` (MOV) | MOV PCM is 24-bit |
| `audio_kbps` | 320 stereo, 192 mono | AAC bitrate |
| `tc_start` | `"00:00:00:00"` | start of the `tmcd` track; nil for none |
| `drop` | auto | drop-frame timecode (30000/1001 and 60000/1001) |
| `faststart` | true | moov before the media data |

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

## MediaVerify

`MediaVerify.check(path, opts)` returns `{ok:, path:, rate:, frames:, checks:,
facts:}`; `MediaVerify.format(r)` prints one PASS/FAIL line per check with the
measured values. Options: `rate` (inferred from the minimum frame duration
when absent), `frames`, `tc_start` (nil: no timecode expected), `drop`, `audio`
(false: none expected), `siting`, `faststart`, `sync`, `flashes`, `bars`.

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
```

`verify` exits 0 when every check passes.

## How it is built

- **Runtime:** `runtime/media/media.c` (handle registry, converter,
  VideoToolbox sessions, segments, SPS/VUI parser, WAV reader) and
  `runtime/media/media_avf.m` (AVAssetWriter mux, `tmcd` patch, AVAssetReader
  probes; manual retain/release like `metal.m`). The ccalls are listed once,
  with their arities, in `W_MEDIA_CCALLS` in `runtime/media/media.h`; the
  non-Apple half of `media.c` generates raising stubs from that list.
- **Link gate:** the compiler links the bridge only when a program's IR
  references `@w_media_` (`ll_needs_media` in `compiler/lib/driver/ir.w`): `media.c`
  on every target, `media_avf.m` on macOS, with `-framework VideoToolbox
  CoreMedia CoreVideo AVFoundation AudioToolbox Foundation CoreFoundation`.
  Canvas-only and Metal-only programs link none of them.
- **Handles:** encoders, segments and muxes are generation-checked integer
  handles; a released handle raises instead of touching freed memory. There
  are no finalizers: `release` segments and `close` encoders.

## Performance

See `benchmarks/media/` for the harness and the numbers against the ffmpeg CLI.
