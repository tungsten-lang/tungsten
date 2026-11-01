# Native Tungsten AV library

`av` is the package name, so its `commands/*.w` files provide `bit av COMMAND`.
Every command is a `Tungsten:Bit:Command` subclass and defines its own `execute`,
`summary` and `usage`. Shared AV functionality is a native Tungsten library:

Add `requires ["tungsten-av"]` to the importing project's Bitfile to use this
toolchain's native AV library and its C companion. Then:

```tungsten
use av
project = Av:Project.load(".")
runner = Av:Runner.new(3600)
media = Av:Media.new(project.toolchain, project.toolchain + "/bits/tungsten-av", runner)
plan = Av:Planner.new(project, media).build(nil, false)
<< JSON.encode(plan)
```

All library files live directly in `lib/`. `lib/av.w` imports the modules;
`config.w`, `planner.w`, `pipeline.w`, `timeline.w`, `inputs.w`, `qc.w`,
`text.w`, `pixels.w`, `banding.w`, `quality.w` and `release.w` implement the
pipeline. `media_worker.w` and the selected toolchain's `apps/studio/tools/av_plan.w`
are supervised native Tungsten workers. `native/platform.c` supplies POSIX locks, durable copies, streaming hashes
and process supervision. Native font-file shaping uses CoreText outlines through
`runtime/quartz.c`, with explicit failure for missing glyphs or fallback fonts.

There is no Python launcher, virtualenv, Python module dependency or `TW_PYTHON`
selection. Video encoding, scaling, timeline rendering and muxing use Tungsten's
media APIs and native macOS frameworks. FFmpeg/FFprobe remain external tools for
independent inspection, audio preparation, decode-based QC and SSIM/VMAF metrics.
Project-declared `av.prepare` stages use explicit argument arrays.

```
bit av init --source source.mov
bit av doctor
bit av plan --profile share
bit av render
bit av share
bit av short
bit av quality --profile share
bit av verify
bit av qc
bit av status
bit av stage --target upload
bit av publish --target upload
bit av gc                # preview
bit av gc --apply
bit av files
```

Commands accept `--project DIR`, repeated `--profile NAME` and `--json`. Plan and
doctor do not create project artifacts or execute prepare/generator stages.
Selected profile dependencies are included in topological order. Use an isolated
Tungsten toolchain; builds in `~/tungsten` are intentionally rejected.

## Project Bitfile

A project-root `Bitfile` uses `Tungsten:Bit:Bitfile.parse` from `tungsten-bit`, with the `av` namespace enabled. The shared parser reads literal declarations without evaluating project code; `config.w` supplies the AV schema and validation.
Multiline lists/hashes, comments, quoted Unicode strings, symbols, booleans and
finite numbers are supported. Unknown directives/options, duplicate keys,
cyclic profiles and conflicting delivery contracts fail before media writes.

```tungsten
name "film"
av.project "film", source: "source.mov", toolchain: "/path/to/isolated/tungsten"
# For authored projects use timeline: "studio/episode.json", cut: "full", mix: "mix.wav".
av.output "master", path: "render/master.mov", format: :mov
av.video "master", codec: :hevc10, quality: 0.85, depth: 10, chroma: "420"
av.audio "master", codec: :pcm, sample_format: :s24le, sample_rate: 48000, channels: 2
av.output "share", from: "master", path: "render/share.mp4", format: :mp4, width: 1280, height: 720
av.video "share", codec: :hevc10, bitrate: "1800k"
av.audio "share", codec: :aac, bitrate: "192k"
av.colour "all", primaries: :bt709, transfer: :bt709, matrix: :bt709, range: :limited, untagged: :reject
av.subtitles "captions.srt", language: "en", mode: :sidecar
av.chapters "chapters.json"
av.resources memory_mb: 4096, jobs: 4, animation_jobs: 4, decode_ahead: 6, segments_ahead: 3, disk_reserve_mb: 1024, timeout: 3600, native_timeout_ms: 30000, retries: 2, cache_days: 30
av.publish "upload", root: "upload", profiles: ["master", "share"], layout: :flat
```

`av.output` also supports alternate `timeline/cut/mix`, exact rational `rate`,
`start_frame/frames`, `fit`, scaling `filter`, `faststart` and `edit_lists`.
Video codecs are H.264, HEVC, HEVC Main10 and the four ProRes 422 variants;
video options include level/GOP/reordering, speed/backend and crop/rect.
Depth/chroma assert the codec's actual output. Audio supports PCM16/24/32/float,
AAC, copy or none; external audio sources, mono/stereo and common sample rates
are explicit. PCM requires MOV. Strict no-edit delivery uses PCM/no-audio MOV.
The current renderer rejects unsupported HDR, full-range and 4:4:4 contracts.

QC is opt-in per profile (use `"all"` for defaults):

```tungsten
av.loudness "all", enabled: true, target: -16, tolerance: 1, true_peak: -1, max_clipped_samples: 0, max_silence: 10, silence_threshold: -60, max_channel_difference: 6
av.text "all", enabled: true, font: "/path/to/font.ttf", size: 48, minimum_size: 24, box: [0.05,0.7,0.9,0.25], safe_area: 0.05, foreground: "#ffffff", background: "#000000", minimum_contrast: 4.5, burned: true, minimum_edge_recall: 0.85, max_error: 0.06
av.anomalies "all", enabled: true, black_min: 1, freeze_min: 3, noise: 0.001, allow_black: [], allow_freeze: [], policy: :fail
av.quality "share", mode: :search, minimum_bitrate: "500k", maximum_bitrate: "8M", max_probes: 6, probe_frames: 24, sample_frames: [0,240], minimum_ssim: 0.98
```

`av.subtitles mode: :timeline` burns exact-font vector outlines into the authored
reference. Text QC checks layout/contrast and every cue's encoded reference ROI;
it does not claim OCR. Anomaly detection decodes the full output and accounts for
authored black/still/card intervals. `minimum_vmaf` requires an FFmpeg build with
libvmaf. Bitrate search chooses the lowest tested passing bitrate; final-file QC
still gates delivery.

`av.banding` accepts explicit `background`, analytical radial `gradient`, frame
`samples`, metric `limits`, pixel/normalized exclusions, or `auto: true` for the
shared film/Short asset conventions; spatial and adjacent-frame checks are native.
`av.input` declares generator data; `av.gate` checks bounded source reports and
optional capture equality. `av.prepare` declares an explicit `argv` and `cwd`.
`av.publish` can include additional `files` and a separate `release_dir`.
See `lib/config.w` for the complete directive field list.

Input snapshots preserve content hashes, source identity, file extensions and
local Tungsten `use` graphs. Jobs record their toolchain identity, frozen inputs,
references and QC reports. All candidates are copied and checked before one
atomic `current` pointer activates a release. Failed jobs retain the existing
deliveries. Later verification/staging pins release manifests and frozen inputs.
GC previews by default and retains completed jobs, current/latest jobs and jobs
referenced by retained releases.

Focused checks:

```
bin/tungsten bits/tungsten-av/tests/native_spec.w
bin/tungsten bits/tungsten-av/tests/banding_spec.w
ruby bits/tungsten-av/tests/integration.rb
ruby bits/tungsten-av/tests/timeline_integration.rb
ruby bits/tungsten-av/tests/audio_formats.rb
ruby bits/tungsten-av/tests/crash.rb
ruby bits/tungsten-av/tests/cache.rb
ruby bits/tungsten-av/tests/library_import.rb
ruby bits/tungsten-av/tests/toolchain_import.rb
```

The integration harness removes Python executables from the child PATH and sets
`TW_PYTHON` to a nonexistent path. Ruby is used only as a test driver.
