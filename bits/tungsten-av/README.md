# av

`bit av` plans, renders, checks and delivers native Tungsten AV projects. `av`
fits the scope and is short to type; `studio` remains the timeline engine.

```sh
bit av init --source input.mov       # or --timeline studio/episode.json
bit av doctor                       # tools, capabilities, inputs, clock, space
bit av plan                         # read-only stage/output plan
bit av render                       # all declared profiles; activates after checks
bit av render --profile master
bit av share                        # share and its declared parent profiles
bit av short                        # named short profile / its alternate timeline
bit av verify                       # native structure plus declared QC
bit av qc --profile share
bit av quality --profile share      # bounded bitrate probes; no release activation
bit av status
bit av files                        # print the main implementation files
bit av stage --target upload        # named, verified atomic copy
bit av gc                           # preview stale temporary artifacts
bit av gc --apply                    # remove only listed eligible artifacts
```

All commands accept `--project DIR` (or a Bitfile), `--profile NAME` (repeatable),
and `--json`. Commands discover the closest parent Bitfile. No source timeline,
media, or release is changed by doctor/plan. Tungsten may populate its compiler
cache. Preparation commands execute only during render/quality.

## Bitfile

The AV section is a declarative literal format, not evaluated project code.
Strings, numbers, `:symbols`, booleans, lists, hashes, multiline literals and
comments are supported. Unknown AV directives/options fail with a location.
The ordinary package-manager directives can coexist with AV declarations.

```ruby
name "my-film"
version "0.1.0"
# Alternatively: timeline: "studio/episode.json", cut: "full", mix: "mix.wav"
av.project "my-film", source: "input.mov", toolchain: "/path/to/isolated/tungsten"
av.output "master", path: "render/master.mov", format: :mov
av.video "master", codec: :prores422hq
av.audio "master", codec: :pcm, sample_format: :s24le, sample_rate: 48000, channels: 2
av.output "share", from: "master", path: "render/share.mp4", format: :mp4, width: 1280, height: 720
av.video "share", codec: :hevc10, bitrate: "1800k", gop: 48
av.audio "share", codec: :aac, bitrate: "192k"
av.colour "all", primaries: :bt709, transfer: :bt709, matrix: :bt709, range: :limited, untagged: :reject
av.subtitles "captions.srt", language: "en", mode: :sidecar
av.chapters "chapters.json", format: :json
av.loudness "all", enabled: true, target: -16, tolerance: 1, true_peak: -1,
  max_clipped_samples: 0, max_silence: 8, silence_threshold: -60, max_channel_difference: 6
av.text "all", enabled: true, font: "fonts/MyFont.ttf", size: 48, minimum_size: 24,
  box: [0.05, 0.70, 0.90, 0.25], minimum_contrast: 4.5, burned: false
av.anomalies "all", enabled: true, black_min: 1, freeze_min: 3,
  allow_black: [[0, 1]], allow_freeze: [], policy: :fail
av.quality "share", mode: :search, minimum_bitrate: "800k", maximum_bitrate: "3M",
  max_probes: 6, probe_frames: 24, sample_frames: [0, 240, 480], minimum_ssim: 0.98
av.resources memory_mb: 4096, jobs: 4, animation_jobs: 2, decode_ahead: 6,
  segments_ahead: 3, disk_reserve_mb: 1024, timeout: 3600, native_timeout_ms: 30000,
  retries: 2, cache_days: 30
av.publish "upload", root: "~/videos-to-upload", profiles: ["master", "share"], layout: :flat
# Explicit argv, run before inputs are frozen. No shell expansion.
av.prepare "assets", argv: ["{python}", "tools/build_assets.py"]
av.input "data", path: "data"
av.gate "data/checks.txt", pattern: "^checks: ([0-9]+) failures=(0)$"
av.gate "data/checks.txt", pattern: "^controls: ([0-9]+) failed as expected: ([0-9]+)$", equal: [1, 2]
```

A trailing comma continues a directive on the next line. Lists and hashes may
also span lines. The supplied `examples/Bitfile` is a minimal runnable template.

Video codecs: `h264`, `hevc` (8-bit 4:2:0), `hevc10` (10-bit 4:2:0),
`prores422`, `prores422hq`, `prores422lt`, `prores422proxy` (10-bit 4:2:2).
`depth` and `chroma` assertions must match the codec. `bitrate` is bits/second
or a `k`/`M` string; `quality` is 0..1 and mutually exclusive with bitrate.
ProRes uses its codec quality tier. Video also accepts `backend` (`auto`,
`metal`, `cpu`, `vimage`), `level`, `gop`, `reorder`, `speed`, `crop`, `rect`.
An independent output can select `timeline: "studio/short.json", cut: "full"`
and optional `mix:` instead of a `from:` dependency. Outputs support `fit` (`stretch`, `contain`, `cover`), `filter` (`lanczos3`,
`bicubic`, `bilinear`), `start_frame`, `frames`, `rate`, `faststart`, `edit_lists`.
Frame-rate conversion is explicit upstream; output rates must match the input.

Audio: `aac`, `pcm`, `copy`, `none`. PCM formats are `s16le`, `s24le`, `s32le`,
`f32le`, in MOV. Sample rates: 32000/44100/48000/88200/96000; one or two channels
with matching `mono`/`stereo` layout. `source` selects external audio. Resampling
and channel conversion are explicit FFmpeg preparation; native muxing/encoding
produces the final file. Strict `edit_lists: false` requires PCM or no audio in
MOV. Every duration must be a whole number of output audio samples.

Chapter JSON is `[["Title", frame], ...]` or objects with `title` and `frame` or
`seconds`. Text chapters use `HH:MM:SS Title`. Chapters must increase within the
output duration. Subtitles are UTF-8 SRT, optionally selected with `profile`.
`language` names the sidecar. A timeline project can use `mode: :timeline` to
burn exact font outlines before compression. Configure the same timeline caption
source/layout for its output family; dependent profiles scale that picture.
`av.text burned: true` also checks encoded caption ROIs against the reference.
The comparison measures edge retention/error; it does not claim OCR accuracy.

Colour is an explicit BT.709 limited-range SDR contract. HDR, wide gamut,
4:4:4/12-bit sources and conflicting tags are rejected. Missing tags are rejected
unless the author explicitly declares `untagged: :bt709`. The pipeline does not
silently tone-map or relabel conflicting colour spaces.

`av.banding "PROFILE", ...` accepts the shared toolkit's analytical gradient,
mask, temporal and per-shot settings. A source project needs explicit samples;
`auto: true` derives samples from a timeline. See
`apps/studio/tools/tw/README.md` for the detailed banding manifest.

`av.gate` retains source correctness checks: a file must match `pattern`, and
optional `equal: [group_a, group_b]` requires equal captured values. These reports
are frozen with the inputs and rechecked before publication.

QC is opt-in per profile and must pass before activation. Audio QC measures the
final decoded file, including AAC priming/trimming, LUFS, true peak, clipping,
silence and channel balance. Whole-film anomaly QC decodes every picture at
320-pixel width; intentional black/still/card timeline holds and configured
intervals are exempted. Set `policy: :report` to report unexpected holds without
rejecting the release. Bitrate search evaluates a bounded ladder against ProRes
references using SSIM and optionally `minimum_vmaf` (requires FFmpeg libvmaf).
It selects the lowest **tested** passing bitrate; final-file gates still apply.

## Reproducibility and recovery

Inputs are hashed and frozen under `.av/inputs` using APFS clones when available,
with portable copies otherwise. Font/data/program dependencies must be declared;
local `.w` use graphs are followed automatically. Immutable snapshots and the
actual compiler/runtime/toolkit/OS identity bind resume checkpoints. Native jobs
also reject source/audio mutation. Timelines render 10-bit 4:2:2 ProRes HQ
intermediates in a private content-addressed build, then encode delivery profiles.
Original authoring documents and assets remain editable.

Jobs, peak child RSS and native queue peaks are recorded under `.av/jobs`.
Memory and disk budgets cap work before encoding; memory pressure is sampled
again between profiles. `status` recognizes a dead writer as interrupted. A new
render can reuse complete, digest-verified GOP checkpoints. Failed jobs never
activate output aliases. Publication verifies exact copies, then atomically
switches a release pointer. Readers requiring several files together should
resolve `current` once. `gc` previews only expired failed jobs and orphaned
candidates; retained releases, their referenced jobs, sealed inputs and completed jobs are preserved.

Dependencies: native macOS media support, FFmpeg/FFprobe, Python 3.10+, and
`apps/studio/tools/tw/requirements.txt`. Use `TW_PYTHON` to select its virtualenv. The checkout launcher also discovers
`build/av-python/bin/python` when present; create it with `python3 -m venv
build/av-python` and install the requirements there.
Build only an isolated Tungsten checkout, never the shared `~/tungsten` tree.
