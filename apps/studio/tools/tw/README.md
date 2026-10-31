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

## Banding

Film rendering (`all` or `banding`), Short rendering and every publish/stage step
run the same checker. Film samples derive from the current resolved timeline;
Short samples derive from the current beat timeline. Both compare only untouched
background pixels against the ideal gradient, blur by sigma 2, and exclude an
8-pixel margin around content. Short defaults mask the upper panel and captions
at y=1370..1530; per-film `exclude` rectangles override these defaults. A missing
reference, empty selection or insufficient background fails the check.

Default per-sample limits are RMS after removing mean bias <= 0.75, p99 absolute
error <= 2.0 (8-bit code units), and 16-pixel boundary/interior gradient ratio <=
2.0. Override `banding.film.limits` / `banding.short.limits` in the config when an
approved delivery contract calls for different limits. JSON reports include every
sample and go to `render/tungsten/banding/{film,short}_0.json`. A failed gate leaves
publication destinations untouched. These are sampled background quality checks,
not a guarantee for every scene or frame.

Custom manifests are supported:

```sh
python3 ~/videos/tools/tw/banding.py manifest.json --root /film --out report.json
```

A manifest needs `movie`, `background`, `rate: [num, den]`, `gradient` with
`cx/cy/r/mid` (normalized to the frame), `samples: [{frame, source}]`, optional
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
PYTHONPATH=apps/studio/tools/tw python3 apps/studio/tools/tw/tests/test_toolkit.py -v
bin/tungsten spec/core/media_delivery_spec.w
bin/tungsten spec/core/media_retry_spec.w
bin/tungsten spec/parity/media_delivery_contract_spec.w
```

Media tests use native macOS frameworks; the portable helper spec also runs with
`run --interpret` and `--ruby`. See `apps/studio/AV_PIPELINE_STATUS.md` for the
current implementation and measured evidence.
