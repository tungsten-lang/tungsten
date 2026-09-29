# Tungsten identity studies

Eight original concepts, two for each requested bucket:

| No. | Name | Direction |
| --- | --- | --- |
| 01 | Quicksilver | A pooled silver T with a moving reflection |
| 02 | Flux | A continuous chrome W |
| 03 | Filament | A glowing W filament with drifting embers |
| 04 | Cinder | A forged T with a hot diagonal cut |
| 05 | Cleave | A spare T assembled from two sharp pieces |
| 06 | Lattice | An open crystalline W |
| 07 | Lowercase | A compact geometric wordmark and square terminal |
| 08 | Editorial | A high-contrast italic wordmark with an elemental signature |

## Generate

`tungsten_logos.w` imports `core/animation`. It builds Plot scenes and Animation
tracks, and samples all 97 frames of each four-second, 24 fps loop in Core.
It asserts exact first/last update equality and the frame schedule. `render.py`
is a separate SVG consumer: its responsibilities are SVG materials, glyph outlines,
and exporting the already-sampled values. The browser selects Core frames; it
contains no independently implemented easing or particle simulation.

The current main checkout does not include `core/animation.w`. The run used the
existing animation checkout `/Users/erik/.codex/worktrees/923f/tungsten` at
`9bdbd7e6`. Both source staging and execution use that checkout to avoid mixing
Core and interpreter versions. The source checkout and unrelated work stay intact.

Dependencies: Python with `fonttools`, `rsvg-convert`, and macOS system fonts
Avenir Next, Futura, DIN Condensed, and Bodoni 72. The finished logo SVGs contain
outlined lettering and do not need those fonts installed to display.

From the repository root:

```sh
python3 -m venv build/logo-studies-2026-09-05/.venv
build/logo-studies-2026-09-05/.venv/bin/pip install fonttools
LOGO_PYTHON="$PWD/build/logo-studies-2026-09-05/.venv/bin/python" \
  doc/examples/animations/logo_studies/build.sh \
  /Users/erik/.codex/worktrees/923f/tungsten
```

Each concept exports a poster SVG, transparent SVG, one-color SVG, animated SVG,
and 1280 x 840 PNG. `contact-sheet.png` is the comparison board. `timelines.json`
retains the full Core descriptions and samples; `designs.json` is the compact
viewer payload. The viewer fragment offers a four-second motion preview and a
one-color comparison. It starts on a still frame and plays only when requested.
SVG animations loop independently when opened in a browser.

`render.py OUTPUT --inline-output ABSOLUTE_PATH` also writes the self-contained
comparison fragment to a conversation's visualization directory. The source
`gallery.html` is a template, with data and artwork supplied by the renderer.

These are design studies. Geometry is original; lettering uses the named system
fonts as a starting point. All files are local and unpublished.

## Filament T revision

`filament_t.w` develops the selected Filament direction into a T: a projected
22-turn incandescent coil across the top, with a straight glowing stem meeting
the bottom of the center turn. The wire's front and back use different heat
levels to make its depth visible. Core samples a four-second energize/cool loop
and asserts both exact loop closure and the center junction's position.

```sh
LOGO_PYTHON="$PWD/build/logo-studies-2026-09-05/.venv/bin/python" \
  doc/examples/animations/logo_studies/build.sh \
  /Users/erik/.codex/worktrees/923f/tungsten \
  "$PWD/build/filament-t" \
  "$PWD/doc/examples/animations/logo_studies/filament_t.w"
```

The single-design viewer provides **Energize** and **One color** controls.
The earlier eight-option gallery and its exports remain in their original output
folder.

## Refined filament and negative space

`filament_refined.w` reduces the crossbar to eight shallower turns, strengthens
the stem, and pairs the mark with a closer lowercase wordmark. It retains the
center-junction and exact-loop assertions. `negative_space.w` adds two studies:
**Counterform**, a T aperture in a circular form, and **Cut Filament**, a T cut
through a rounded square with five winding turns inside its crossbar. The
apertures are open contours, so the negative space is truly transparent in the
transparent exports. Core supplies the aperture motion and changing wire width.

After generating the earlier Filament T reference above:

```sh
LOGO_PYTHON="$PWD/build/logo-studies-2026-09-05/.venv/bin/python" \
  doc/examples/animations/logo_studies/build.sh \
  /Users/erik/.codex/worktrees/923f/tungsten \
  "$PWD/build/logo-refinement/filament" \
  "$PWD/doc/examples/animations/logo_studies/filament_refined.w"
LOGO_PYTHON="$PWD/build/logo-studies-2026-09-05/.venv/bin/python" \
  doc/examples/animations/logo_studies/build.sh \
  /Users/erik/.codex/worktrees/923f/tungsten \
  "$PWD/build/negative-space-research" \
  "$PWD/doc/examples/animations/logo_studies/negative_space.w"
python3 doc/examples/animations/logo_studies/combine_refinement.py
build/logo-studies-2026-09-05/.venv/bin/python \
  doc/examples/animations/logo_studies/render.py build/logo-refinement
```

The combined gallery keeps the earlier filament as a labeled reference beside
the three new studies. The final bundle includes the source, original Core
payloads, outlined SVG exports, PNGs, a size proof, and the comparison gallery.
