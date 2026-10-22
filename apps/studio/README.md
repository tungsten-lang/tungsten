# studio: the Tungsten timeline engine

A frame-addressable video renderer. It reads a declarative episode file, resolves it to integer frames and samples,
renders any frame on its own, encodes the picture as small closed-GOP segments with `core/media` (VideoToolbox), and
assembles masters by passthrough mux, with no ffmpeg. It is the video-processing backend. The publishing side
(series, styles, importers, storyboards, generation queue, review, uploads) is a separate project that drives it
(`~/projects/studio`, with its tools in `~/projects/studio/tools`) and is not part of Tungsten.

## Build and run

    bin/tungsten -o apps/studio/bin/studio apps/studio/studio.w

    studio resolve <episode.json> [--cut full]           # → build/<cut>/timeline.resolved.json, .srt, chapters
    studio diff <old.resolved.json> <new.resolved.json>  # changed frame ranges and segment keys, before rendering
    studio frame <episode.json> <f> [--png out] [--fresh]
    studio render <episode.json> [--cut full] [--jobs N] [--max-frames N] [--from F --to F]   # missing segments only
    studio mix <episode.json> [--cut full]               # → build/<cut>/mix.wav and a loudness report
    studio mux <episode.json> [--cut full]               # → build/<cut>/master.mp4 (passthrough), .srt, chapters.txt
    studio verify <master> --resolved <path>             # CFR, PTS, tmcd, A/V length, colour tags, sync
    studio fcpxml <episode.json> [--cut full]            # → build/<cut>/timeline.fcpxml (FCPXML 1.11)
    studio raw <episode.json> <from> <to> <path>         # pre-encode RGB24 frames, for comparisons
    studio selftest | gc

`build/` sits next to the episode file. Heavy runs (render, mix, and resolve when it has to compile a program) belong
under the machine's heavy-job lock and memory guard. Use `--max-frames 400` to keep each hold short.

## Model

- **Time is integers.** Picture events are frames at a rational rate `[num, den]`, audio events are samples at
  `sr`, and authored offsets are milliseconds or frames. Every instant is held in flicks (1/705,600,000 s, exact
  for 24, 23.976, 25, 29.97, 30, 50, 59.94 fps and every common audio rate), so an anchor can add milliseconds and
  frames. Cuts snap with one rule, `frame = floor((flicks + FPF/2) / FPF)` (`Flicks.to_frame`). Timecode is a
  label on the frame index.
- **Source vs resolved.** The episode file holds narration lines (gap, `nudge_ms`, `ripple`), shots anchored to a
  line edge or a phrase in it, the start, or another shot's start or end (`at: {ref, edge, phrase, ms, frames}` or
  `{shot, edge, ms, frames}`), cues and markers. Lines and shots resolve lazily, so either may anchor on the other.
  A shot may have an explicit length (`frames: N`, or `"program"` for its program's own frame count). A cut may
  carry its own lines, shots, cues, captions and markers. `resolve` is pure and writes the absolute timeline plus an
  interval table (frame runs with a constant active set), so `frame f` is a binary search plus a composite.
  `ripple: false` moves only the line's own audio and subtitle.
- **Keys.** item recipe = H(kind, canonical params, keyframes, dep SHA-256s, renderer version); frame key =
  H(compositor version, format, [(recipe, f − item start, role)]). Keys use item-local frames, so an unchanged shot
  that moves in time keeps its cache. Duration enters a recipe only for kinds whose pixels depend on it.
- **Segments.** Each interval is cut into runs of at most 48 frames, each one closed GOP (IDR first), stored under
  H(encoder settings, its frame keys). The master is a passthrough append of segments with PTS rewritten, plus the
  mix, a `tmcd` track and colour tags. An edit costs only the new keys plus an I/O-bound re-mux.
- **Determinism.** No state between frames. Every random draw is counter-based on (seed, item id, local frame,
  purpose). Textures are keyed by their owners and parameters (the grain field by the grain's parameters), not by
  render order. Same inputs give the same frame on any worker.

## Primitives

The engine draws generic things; a series' look arrives as data (the episode's `styles` and its items). A style
("look") holds the grade (shadow/highlight tints, contrast mix, saturation, lift, gain, bloom threshold/sigma/tint),
vignette, grain (count, base, mid, optional `blur_var`), jitter, shakes and a camera table.

| Kind | Params |
| --- | --- |
| `still` | a panel under a camera move from the style's table: zoom moves `{amp: [base, per s, max], focus_k, reverse}` or travelling moves `{z: [z0, z1], x/y: {base: center\|focus\|weight, span: [s0, per s] \| edge: fraction, dir}}`; `fx` (rain, fog, snow, dust/embers, flicker, shake); a `wipe` to a second image at a phrase; a `matte` (the letterbox colour and its overlay elements); timed overlays |
| `clip` | a still plus `clip`: frame-sequence `parts` (each `{src, first, count}`) joined by `xf`-frame crossfades, played at `speed: [min, max]` to fill the item (+ `add_ms`) from a phrase `at`, with `blend`, a `zoom` curve, a `pre` pull from the still, or a `hold` push on the last frame |
| `group` | panes, each `{src, pane: [x, y, w, h], at (phrase), lead_ms, fade_ms, zoom, focus, frame: pane\|picture (+ x), shade: {rows, to}, elements}`, plus a matte |
| `frames` | a pre-rendered frame sequence (`in` offset) |
| `program` | a Tungsten program's frames (below) |
| `card` | `bg: {color, paper: {key, seed, down, blur, amount, tint}}` and `elements` |
| `black` | |

Overlay elements (lib/overlay.w): `text` (size, family, weight, style, fill, anchor, `valign: mid`, spacing,
`center_spaced`, stroke), `circle`, `line`, `rect`, `image`, and `fit` (the first of several options that keeps
clear of another element, e.g. a label that shrinks beside a source line). Timed text (`overlay` cues, attached
to the stills they overlap): a text element with `reveal_ms` per character (typewriter), `fade_ms`,
`stroke_min_alpha`. Transitions: dissolve, fade-in (`trans_in`), fade-out before a shot (a `fade_out` cue).

**Programs.** `"program": {source, extract?, patch?, append?, data, link?, run, frames, count, captions?}`: a
source file (optionally one marked section of it, literal patches, appended text), the files its frames depend on,
an argv template (`{root} {dir} {work} {dur} {first} {last}`), where frame k lands, and how many frames there are
(`"dur"`: round(duration × rate), or `{"run": [...]}`: the last line the program prints). With `link` it runs in a
work directory linking a folder's entries, so a program that reads its video folder and writes frames into it
writes into the cache. `captions: {run, file}` reads the SRT the program writes for its own frames (a shot opts in
with `captions_from_program`). Frames are cached under H(program text, data, compiler, run arguments) and rendered
per hold, only those the segments need, in up to `--jobs` processes.

**Captions.** Lines carry caption chunks `cc: [{w: [first word, end word), text}]`, laid out by the author (breaks,
speaker labels); their times come from the take's word starts and ends (`words_ms`, `words_end_ms`), so they follow a
nudge or a re-take. The cut's `caption_timing` picks the rule: `starts` (a chunk runs to the next chunk's first
word, at least `min_ms`) or `spans` (first word's start to last word's end, held to `gap_ms` before the next, the
last one `tail_ms` longer). Explicit `captions` are anchored; program captions are offset to their shot.

**Mix.** `studio mix` runs lib/audio.w's chain (voice EQ/de-ess/compression/reverb, music and ambience loops,
ducking), or, with `"mix": {"mode": "plain"}`, places every take and cue as it is (cut at a cue's `until`)
(lib/mixplain.w). Both end in BS.1770 integrated loudness, a linear gain to the cut's target and a 4x true-peak
limiter, 24-bit WAV exactly the picture's length. The cut's `audio_kbps` sets the master's AAC rate.

**FCPXML.** `studio fcpxml` writes FCPXML 1.11: rational times from the integers (frame f = f·den/num s, sample s =
s/sr s); the picture on the spine (one clip of the master per item, named by its id, a note with kind, transition and
recipe); above it the source panels and the overlay text as disabled connected clips and the captions (SRT role);
below it the final mix (role "Final Mix") and the stems by role (dialogue, music, ambience, effects), disabled, at
their exact samples; chapters as chapter markers. It validates against Apple's DTD (iMovie ships it).

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
- **Keys of derived textures** must hash only what the texture depends on: the grain field was keyed by the whole
  style, so adding a camera curve to a style re-randomised every frame's grain.

## Reference run (Profiles: Archimedes & Eratosthenes, 2026-10-22)

56,002 frames at 1080p24. Over a 2,880-frame span, the engine with VideoToolbox HEVC and 6 workers took 29.2 s and
112 CPU-s. The Python/PIL + libx264 pipeline took 198.5 s and 391 CPU-s. The full film took 488 s of render time, the
mix 74 s, the mux 11 s. `verify` passes 16/16. 20 random `frame` outputs are bit-identical to the master after
decode. Changing one camera move re-renders 11 of 1,232 segments (6.5 s). See `doc/media.md` for the encoder,
mux and verifier.

The importers, comparison and benchmark scripts that produced these numbers (and the episode-specific layout of
the Profiles look) live in `~/projects/studio/tools` and `~/projects/studio/styles`.
