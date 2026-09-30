# Tests for the small support libraries of the GF(2) toolchain port
# (lib/metaflip/gf2/): exact floats, JSON, text and ordering helpers, file
# system and git access, command-line parsing. Python 3.14 and Ruby 4.0 are the
# oracles; their outputs are committed as fixtures under
# spec/fixtures/gf2_support/ next to the scripts that make them.
#
#   bin/tungsten spec/gf2_support_test.w        # native, about a minute cold
#
# Optional environment (each enables a larger check against the real campaign
# data; without it the test still runs everything the fixtures allow):
#   GF2_JSON_GOLDENS  directory made by `gen_json_goldens.py DIR 2000`
#   GF2_RELEASE_DIR   .../record-hunt-20260926/work/release-0929
#   GF2_VERBOSE=1     print every passing check too
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
