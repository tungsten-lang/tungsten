# Tests for the small support libraries of the GF(2) toolchain port
# (lib/metaflip/gf2/): exact floats, JSON, text and ordering helpers, file
# system and git access, subprocesses, command-line parsing. Python 3.14 and
# Ruby 4.0 are the oracles; their outputs are committed as fixtures under
# spec/fixtures/gf2_support/ next to the scripts that make them.
#
#   bin/tungsten spec/gf2_support_test.w        # compiled only; about 20 s warm
#
# Environment (all optional):
#   GF2_RECORD_HUNT_WORK  the record-hunt campaign's work directory (default under
#                         $HOME). When it exists the cases also run on the real data
#                         (release tree, records.tsv, the pinned git clones, globs);
#                         without it they print SKIP and the fixtures carry the test.
#   GF2_JSON_GOLDENS      directory made by `gen_json_goldens.py DIR 20000 4242`
#                         (or `... 3000 99 150000` for the parser fuzz) for a larger
#                         differential run
#   GF2_VERBOSE=1         print every passing check and the seconds per section
# The other switches (GF2_CLI_GOLDEN, GF2_SUPPORT_FIXTURES, GF2_RELEASE_DIR) are
# described in the case files.
#
# The cases live in spec/gf2_support/<module>_cases.w; this file only runs them.
use gf2_support/check
use gf2_support/floatx_cases
use gf2_support/json_cases
use gf2_support/textx_cases
use gf2_support/fsx_cases
use gf2_support/gitx_cases
use gf2_support/cli_cases

t = Check.new
t.section("floatx")
gf2_floatx_cases(t)
gf2_textx_float_cases(t)
t.section("jsonx")
gf2_json_cases(t)
t.section("textx")
gf2_textx_cases(t)
t.section("fsx")
gf2_fsx_cases(t)
t.section("gitx")
gf2_gitx_cases(t)
t.section("cli")
gf2_cli_cases(t)
t.finish("gf2 support libraries")
