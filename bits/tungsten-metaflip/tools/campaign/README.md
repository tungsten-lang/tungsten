# The campaign's cascade drivers (Python, as they ran)

`next_parents.py`, `project_screen.py`, `pick_children.py`, `sweep.py`, `iterate.py` and `pub.py` are copied unchanged from the working
directory of the 2026-09-26..29 record hunt, where they drove the cascade (scoreboard witnesses -> projection children -> walks -> iterative
deepening). They keep the machine-specific paths they ran with (`/Users/erik/tungsten-mf-ternary/...`, the working directory's `upstream/`
and `wide-rect-walk`), so they do not run elsewhere without edits; `spec/fixtures/gf2_cascade/generate.py` runs them from a scratch directory
with those constants rewritten and a `pub.py` that reads the fixture's tables, to produce the goldens of `spec/gf2_cascade_test.w`.

The Tungsten ports are `tools/cascade.w` (subcommands `parents`, `screen`, `pick`, `sweep`, `iterate`) and `lib/metaflip/gf2/cascade.w`.
