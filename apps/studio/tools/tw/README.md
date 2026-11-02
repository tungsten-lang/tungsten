# Shared film toolkit

The versioned toolkit is here; `~/videos/tools/tw` points here. Film folders keep
`tools/tw.json`, compatibility entry points, and their authored scene/compositor,
importer and data-generation sources. Common orchestration, animation caching,
background plates, mix fitting, JPEG scaling, banding and glyph outlines have one
implementation.

The installed four-film migration covers ancient Egypt, ancient Mesopotamia,
ancient China and Biblical Wisdom. Original scripts are in
`~/videos/tools/tw-migration-backups/20261031T130117587576/` with their film paths.
No film media was published or staged during migration.

Existing entry points continue to work:

```sh
tools/tw_render.sh all
tools/tw_render.sh share
tools/tw_short.sh
tools/tw_thumbs.sh
tools/tw_publish.sh render
tools/tw_publish.sh stage
python3 ~/videos/tools/tw/tw.py --film "$PWD" banding short
```

The wrappers select `TW_FILM_ROOT` and call the shared driver. `STUDIO_TW`
overrides `tw.json`'s isolated compiler checkout; builds in `~/tungsten` are refused.
`JOBS`, `AJOBS`, `COLD`, `IMPORT_OPTS`, `RENDER_OPTS`, `MIX_OPTS`, `SHARE_CODEC`,
`SHARE_KBPS`, `GUARD_MB` and `GUARD_S` retain their roles. Each invocation keeps
its film's `heavy.sh` episode lock, machine heavy slot, caffeinate and guard,
and records a log under `render/tungsten`. `TW_PYTHON` selects a Python environment.
Install `requirements.txt` there; NumPy and Pillow run the banding checks,
fontTools and HarfBuzz generate script outlines.

`tw.json` supplies the compiler path, ordered `before_anims` commands (repeated
layout/cue passes are significant), optional regex validation `gates`, the
`short_sources` concatenation order, thumbnail output settings and publication
mappings. Scene generation, narrative timing and the film's compositor remain
film-authored sources. `tw_mix.w` compatibility files use the canonical shared
source so nested Tungsten imports resolve correctly.

Install another compatible film with a dry run first:

```sh
python3 ~/videos/tools/tw/install.py /path/to/film
python3 ~/videos/tools/tw/install.py /path/to/film --apply
```

The installer refuses unfamiliar layouts and existing toolkit directories pointing
elsewhere. It saves every replaced file before writing a config/wrapper; rerunning
it retains existing configuration. Restore originals by copying the corresponding
backup files over the film's `tools/` entries (remove symlinks first).

## Cut clocks and delivery

`episode`, `cut`, `short_episode`, and `short_cut` select documents and cuts.
Build paths and variant prefixes follow studio's document naming. Rates use
positive integer pairs; frame and mix fitting use rational arithmetic, including
30000/1001. The current audio engine requires 48000 Hz. A cut ending between
audio samples is rejected before mix fitting. Resolved geometry/rate must agree
with the selected document.

For strict delivery, configure:

```json
{"delivery": {
  "master": {"format": "mov", "audio_codec": "pcm", "edit_lists": false},
  "share": {"format": "mov", "audio_codec": "pcm", "edit_lists": false,
            "codec": "hevc10", "width": 1280, "height": 720, "kbps": 1800}
}}
```

`tw_mix` accepts `--rate N/D` (`--fps N` remains compatible). Scene generators
receive `TW_RATE_NUM`, `TW_RATE_DEN`, `TW_WIDTH`, `TW_HEIGHT`. Existing authored
24-fps generators retain that declared clock by default; they fail before
rendering at a different rate. Set `generator_clock: "env-v1"` once the authored
generator consumes that environment contract, or supply `scene_rate: [N,D]`.
Studio scales authored source PNGs to cut geometry. Plates use the authored
canvas dimensions found in the source (or `authoring_geometry.film/short`).
`auto_plates: false` supports independently prepared assets; `import_command`
can replace the film importer (an empty list uses an existing document).

## Checkpoints and cancellation

Share transcodes retain closed GOPs under `render/tungsten/resume`, keyed by
source bytes and options, and rebuild audio/container metadata on resume. A
changed source or delivery recipe cannot reuse stale segments. Direct media
commands accept `--resume DIR`, `--timeout-ms N`, and `--cancel-file PATH`.

Every toolkit stage owns its subprocess group. Nested supervisors and native
Tungsten `Process.spawn` / `OS.system` workers inherit it through
`TUNGSTEN_INHERIT_PROCESS_GROUP=1`, so a hard deadline also reaches worker pools. SIGINT/SIGTERM cancels active
stages, sends TERM, then KILL after a short grace period. `stage_timeout` in
seconds (default 3600), or `TW_STAGE_TIMEOUT`, bounds stages including FFmpeg QC,
compilation and native drivers. `native_timeout_ms` bounds decoder reads.
Completed checkpoints and previously published releases survive interruption.

## Verified release bundles

Publish/stage copies **every selected source** into one candidate bundle first.
Native delivery checks, expected geometry/codec checks and background QC run on
those exact copies. SHA-256 binds output bytes, reports, timeline/configuration
and toolkit/compiler provenance. A changed candidate or configuration fails
before activation. Stage checks therefore cover the actual render publication
being copied, including share and Short files selected in its mapping. Staging
resolves each source bundle once, checks its manifest hashes, and keeps reading
that release even if its upstream `current` pointer changes during the copy.

A single atomic `current` symlink activates the immutable release directory.
Legacy destination filenames become aliases through that pointer; their original
bytes are retained in a legacy bundle. Failed verification preserves the active
release. For a coherent multi-file read, resolve `current` once and read its
`manifest.json` and files from that release. Opening separate aliases across a
promotion can naturally observe different releases.

Release directories default to `.tw-releases/<film>/<destination>` beneath the
common destination folder; override with `release_dirs.render/stage`. The
filename set is fixed per directory. Existing `[source,destination]` pairs remain
supported; explicit entries use `{source,destination,role}` with role `film`,
`short`, or `share`. Use mappings matching the selected cut and format.

## Banding

Film rendering (`all` or `banding`), Short rendering and every publish/stage step
run the same checker. Film samples derive from the current resolved timeline;
Short samples derive from the current beat timeline. Both compare only untouched
background pixels against the ideal gradient, blur by sigma 2, and exclude an
8-pixel margin around content. Short defaults mask the upper panel and caption region in normalized coordinates.
`exclude_normalized` scales with output geometry; `exclude` adds pixel rectangles. A missing
reference, empty selection or insufficient background fails the check.

Default per-sample limits are RMS after removing mean bias <= 0.75, p99 absolute
error <= 2.0 (8-bit code units), and 16-pixel boundary/interior gradient ratio <=
2.0, plus adjacent-frame background RMS <= 0.5. Override `banding.film.limits` / `banding.short.limits` in the config when an
approved delivery contract calls for different limits. JSON reports include source/movie hashes, worst frames, temporal residuals, mean
and maximum statistics; HTML, sevenfold residual images and contact sheets sit
beside them. Share references are resized to the decoded output geometry. Reports go to `render/tungsten/banding/{film,short}_0.json`. A failed gate leaves
publication destinations untouched. These are sampled background quality checks,
not a guarantee for every scene or frame.

Custom manifests are supported:

```sh
python3 ~/videos/tools/tw/banding.py manifest.json --root /film --out report.json
```

A manifest needs `movie`, `background`, `rate: [num, den]`, `gradient` with
`cx/cy/r/mid` (normalized to the frame), `samples: [{frame, source, next_source}]` (adjacent references for temporal checks), optional
`exclude: [[x,y,w,h]]`, and positive finite `limits`. Decode selection preserves
original PTS after seeking; the checker has an NTSC frame-selection regression.

## Ancient scripts

`glyphs.py` selects the exact font file, shapes text through HarfBuzz and writes
SVG paths through fontTools. It supports Avestan, Old Persian, cuneiform and
hieroglyphs without CoreText/Pango fallback. Missing glyphs raise an error.
The old `glyph_path(ch)` API remains available for cuneiform/hieroglyph generators.
For shaped text, pass a bundled font explicitly:

```sh
python3 ~/videos/tools/tw/glyphs.py '𐬀𐬁' --font fonts/NotoSansAvestan-Regular.ttf --out avestan.svg
```

The output contains outlines, so rsvg can render it without locating a font.
Use `--direction rtl` when direction cannot be inferred from the script.

## Verification

```sh
PYTHONPATH=apps/studio/tools/tw python3 -m unittest discover -s apps/studio/tools/tw/tests -v
PYTHONPATH=apps/studio/tools/tw RUN_AV_NATIVE=1 python3 -m unittest discover -s apps/studio/tools/tw/tests -p test_native_pipeline.py -v
bin/tungsten spec/core/media_precision_spec.w
bin/tungsten spec/core/media_resume_spec.w
bin/tungsten spec/core/media_delivery_spec.w
bin/tungsten spec/core/media_retry_spec.w
bin/tungsten spec/parity/media_delivery_contract_spec.w
```

Media tests use native macOS frameworks; the portable helper spec also runs with
`run --interpret` and `--ruby`. See `apps/studio/AV_PIPELINE_STATUS.md` for the
current implementation and measured evidence.

The font fixtures are generated tiny TrueType outlines, with no system fonts or
personal folders. `.github/workflows/av-pipeline.yml` runs the hermetic toolkit
suite on Linux/macOS and native precision, recovery and delivery integration on
macOS. A machine without Metal reports its capability skip separately; CPU
precision and native recovery still run.
