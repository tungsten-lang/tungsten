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

## Reference run (Profiles: Archimedes & Eratosthenes, 2026-10-22)

56,002 frames at 1080p24. Over a 2,880-frame span, the engine with VideoToolbox HEVC and 6 workers took 29.2 s and
112 CPU-s. The Python/PIL + libx264 pipeline took 198.5 s and 391 CPU-s. The full film took 488 s of render time, the
mix 74 s, the mux 11 s. `verify` passes 16/16. 20 random `frame` outputs are bit-identical to the master after
decode. Changing one camera move re-renders 11 of 1,232 segments (6.5 s). See `doc/media.md` for the encoder,
mux and verifier.
