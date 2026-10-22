# studio: the Tungsten timeline engine

A frame-addressable video renderer. It reads a declarative episode file, resolves it to integer frames and samples,
renders any frame on its own, encodes the picture as small closed-GOP segments with `core/media` (VideoToolbox), and
assembles masters by passthrough mux, with no ffmpeg. It is the video-processing backend. The publishing side
(series, storyboards, generation queue, review, uploads) is a separate project that drives it and is not part of
Tungsten.

## Build and run

    bin/tungsten -o apps/studio/bin/studio apps/studio/studio.w

    studio resolve <episode.json> [--cut full]           # → build/<cut>/timeline.resolved.json, .srt, chapters
    studio diff <old.resolved.json> <new.resolved.json>  # changed frame ranges and segment keys, before rendering
    studio frame <episode.json> <f> [--png out] [--fresh]
    studio render <episode.json> [--cut full] [--jobs N] [--max-frames N] [--from F --to F]   # missing segments only
    studio mix <episode.json>                            # → build/<cut>/mix.wav and a loudness report
    studio mux <episode.json>                            # → build/<cut>/master.mp4 (passthrough), .srt, chapters.txt
    studio verify <master> [--resolved path]             # CFR, PTS, tmcd, A/V length, colour tags, sync
    studio gradecheck <episode.json> <from> <to> [--step N]   # Metal grade vs the CPU reference, per code value
    studio selftest | raw | gc

`STUDIO_GRADE=cpu|metal` (or `"grade_impl"` in the cut) picks the per-pixel grade; the default is Metal when a device
is present. The CPU path (`lib/raster.w`) stays the reference.

`build/` sits next to the episode file. Heavy runs (render, mix) belong under the machine's heavy-job lock and memory
guard. Use `--max-frames 400` to keep each hold short.

## Model

- **Time is integers.** Picture events are frames at a rational rate `[num, den]`, audio events are samples at
  `sr`, and authored offsets are milliseconds. Conversions go through flicks (1/705,600,000 s, exact for 24, 23.976,
  25, 29.97, 50, 59.94 fps and every common audio rate). Cuts derived from audio snap with one rule,
  `frame = floor((flicks + FPF/2) / FPF)` (`Flicks.to_frame`). Timecode is a label on the frame index.
- **Source vs resolved.** The episode file holds narration lines (gap, `nudge_ms`, `ripple`), shots anchored to
  lines, the film start or other shots (`at: {ref, edge, ms}`), cues and markers. `resolve` is pure and writes the
  absolute timeline plus an interval table (frame runs with a constant active set), so `frame f` is a binary search
  plus a composite. `ripple: false` moves only the line's own audio and subtitle.
- **Keys.** item recipe = H(kind, canonical params, keyframes, dep SHA-256s, renderer version); frame key =
  H(compositor version, format, [(recipe, f − item start, role)]). Keys use item-local frames, so an unchanged shot
  that moves in time keeps its cache. Duration enters a recipe only for kinds whose pixels depend on it.
- **Segments.** Each interval is cut into runs of at most 48 frames, each one closed GOP (IDR first), stored under
  H(encoder settings, its frame keys). The master is a passthrough append of segments with PTS rewritten, plus the
  mix, a `tmcd` track and colour tags. An edit costs only the new keys plus an I/O-bound re-mux.
- **Determinism.** No state between frames. Every random draw is counter-based on (seed, item id, local frame,
  purpose). Textures are keyed by item, not by render order. Same inputs give the same frame on any worker.
- **Kinds:** still (sub-pixel camera over a panel), clip (frame sequence with speed map and blend), frames,
  `program` (a Tungsten scene module compiled from source, cached under its program hash, so an edit to the
  animation re-renders only its segments), card, black, group (triptych), and wipe/dissolve/fade transitions.

## Things learned the hard way

- **VideoToolbox:** a compression session that encodes several segments carries state across forced IDRs: identical
  frames gave different pictures. Open one session per segment. Bytes then match except a 30–62-byte session SEI.
  Parameter sets depend only on the settings, so segments from any session share one sample description.
- **afconvert** ignores the LAME/Info gapless header and keeps the 576-sample encoder delay (13 ms late at 44.1 kHz).
  The engine trims it from the header.
- **Compiler workarounds** (bugs reported, not fixed): typed→typed calls box i64 results, which leak as BigInts
  past 2^47; a u8→f64 cast stored back into a `u8[]` reads 0. `studio selftest` guards both.
- **CoreGraphics' crop rect** rounds to whole source pixels, which steps slow camera moves. Draw the whole still
  under a sub-pixel transform instead.
- **`x.abs` in a typed function** is a boxed method call, about 55 ns: it made the Airwindows de-esser, the compressor
  and the true-peak scans 10-40x slower than their arithmetic. Spell it out (`v = 0.0 - v if v < 0.0`).
- **Canvas pixels on the GPU:** a canvas's memory is page-aligned `mmap`, so `w_array_view_raw` over
  `data_pointer` (raw ints into `ccall`) and `metal_buffer_for` give a no-copy Metal buffer; the GPU writes the layer
  in place and CoreGraphics keeps drawing on it. Several `core/metal` wrappers are `fn` (memoised when their
  `ccall` is not on the impure list); call `w_metal_dispatch_groups` and friends from `->` methods.

## Performance (engine/perf, 2026-10-22)

**Mix** (`lib/audio.w`). Every narration take's whole chain (EQ, Airwindows de-esser, compressor, gain, split-band
de-esser, reverb, pan) is stored once as `build/audio/take_<key>.wav`, key = H(take SHA-256, voice chain, gain,
pan, reverb, vo settings, seed, `DSP_VERSION`, FIR sizes); every cue source's filter chain likewise as
`cue_<key>.wav`. Both are Q3.28 fixed point (32-bit PCM, 2^-29 resolution, ±8 range). A cold mix stores a take and
then places it from the file, so cold and cached mixes are bit-identical. A nudge or ripple re-places cached takes
and re-runs the bus (ducking, cues, peak, loudness, true-peak limiter, write). Bump `DSP_VERSION` when processed
bytes change. These files are not garbage-collected yet (Archimedes: 69 takes 852 MB, 19 cue chains 386 MB).

- **FFT:** radix-4 decimation in frequency forward and the mirrored decimation in time inverse, per-stage twiddle
  tables read in order, no bit reversal (spectra are only multiplied point by point), split f64 arrays. Real signals
  go two per complex transform: with a real kernel the real and imaginary parts of the inverse are the two blocks'
  outputs, so no separation pass. ms per transform (f64 complex): 65,536 points 0.20 (old radix-2 1.07), 131,072
  0.48 (2.26), 1,048,576 4.25 (31.4). Reference only, Apple vDSP: `fft_zipD` (f64) 0.39 / 0.81 / 8.3, `fft_zip`
  (f32) 0.084 / 0.13 / 1.55, `fft_zripD` (f64 real, n points) 0.18 / 0.39 / 3.7. Not adopted: de-ess and reverb
  together take 2.2 s of a cold mix, FFTs about two thirds of it, so f32 vDSP would save about 1 s.
- **Split-band de-esser:** the legacy whole-take FFT weighting (a linear ramp 3.0-3.8 kHz) is a zero-phase high-pass
  with a closed-form trapezoid impulse response; it runs as a 65,537-tap FIR (±0.68 s) by overlap-add with
  131,072-point transforms (65,536-sample blocks, two per transform). On a 137 s take: 1,050 ms -> 62 ms, and the
  de-essed signal is within 3.5e-8 (0.3 LSB at 24 bits) of the whole-take result (16,385 taps: 2.7 LSB).
- **Reverb:** the same overlap-add plan, two blocks per forward transform, one inverse per channel: 570 -> 82 ms on
  that take, equal to the old result within 3e-16.
- **Loudness and true peak:** true-peak gain and measurement skip 12-tap windows whose largest sample times the
  largest tap sum cannot reach min(ceiling, running maximum) (exactly the same gains and maxima: 6.9 s -> 0.19 s and
  5.0 s -> 0.16 s); the two channels' K-weighting recursions run interleaved (0.70 -> 0.26 s per measurement);
  ducking gain is one `exp` per 64-sample block; consecutive biquads run four at a time (bit-identical).

Archimedes (39 min, 69 takes, 49 cues), wall time: before, 71.4 s (takes 48.6 s: chain 13.7, de-ess FFTs 16.8,
reverb 16.9; loudness 16.2 s). After: cold 8.6 s (takes 5.1 s, cues 1.4 s, loudness 1.3 s); cached 2.8 s for the
same mix again or the +10 ms ripple and non-ripple nudges (4.5 s when the take files are not in the page
cache). Against the previous mix: max 2 LSB at 24 bits (-132.5 dBFS), 1.43% of samples differ (124 by 2 LSB), RMS
difference 0.12 LSB (-156.9 dBFS); integrated loudness -16.0213530583 vs -16.0213530582 LUFS, true peak identical
(-1.4998 dBTP).

**Grade** (`lib/grade.w`). Before, a graded frame spent 18 of its 28 ms in the CPU grade (8 ms in CoreGraphics
drawing the source). MetalGrade runs the source (load, lerp or wipe of the active-picture canvases), flicker, rain,
fog, particle discs and their 7x7 blur screen, clip, the bloom grid, its separable blur and the grade (tints,
S-curve, saturation, bloom, lift/gain, vignette, grain, row fade, alpha) as six MSL kernels in one command buffer
per graded picture, compiled with strict math. The canvases' pixel memory is wrapped as no-copy Metal buffers: the
GPU reads the CoreGraphics source and writes the layer in place. Particle positions stay on the CPU in f64.

- **Match:** `studio gradecheck` over 342 sampled frames (dust, flicker, embers, the s12 clip, the triptych, the s36
  wipe, and rain + fog and snow from feature_test.json): max 1 code value; 0.0002-0.0008% of values differ by one,
  none by more. The GPU computes in f32 where the CPU uses f64 between its f32 planes, so values that sit on a
  rounding boundary can land one code apart. The CPU path is unchanged: `studio raw` gives the same bytes as before
  on 30 frames across every fx kind.
- **Keys:** the recipes of graded kinds (still, clip, group) carry `"grade": "metal1"`; the CPU reference adds
  nothing, so segments made before stay valid under `STUDIO_GRADE=cpu`. With the Metal default, an episode rendered
  before re-renders its graded shots once (Archimedes: 721 of 1,232 segments); the rest keep their keys. Bump
  `METAL_GRADE_ID` when the kernels' output changes.
- **Speed**, Archimedes span 15,600-18,480 (2,900 frames: anim:m02/m03 frame sequences, which are not graded, s12
  clip with dust, s13 still), render time over 8 holds of <= 400 frames: 1 worker, CPU 81.8 s (35 fps, 91 CPU-s) vs
  Metal 42.4 s (68 fps, 45 CPU-s); 6 workers, CPU 26.8 s (108 fps, 111 CPU-s) vs Metal 16.7 s (174 fps, 59 CPU-s).
  On graded shots alone, 1 worker goes from about 33 to about 82 fps. Peak RSS per process is unchanged (~645 MB at
  1 worker, ~515 MB at 6).

## Reference run (Profiles: Archimedes & Eratosthenes, 2026-10-22)

56,002 frames at 1080p24. Over a 2,880-frame span, the engine with VideoToolbox HEVC and 6 workers took 29.2 s and
112 CPU-s. The Python/PIL + libx264 pipeline took 198.5 s and 391 CPU-s. The full film took 488 s of render time, the
mix 74 s, the mux 11 s. `verify` passes 16/16. 20 random `frame` outputs are bit-identical to the master after
decode. Changing one camera move re-renders 11 of 1,232 segments (6.5 s). See `doc/media.md` for the encoder,
mux and verifier.
