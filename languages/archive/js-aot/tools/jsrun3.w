# jsrun3 — tier 0 with compiled units (PLAN.md M5, `jsrun --units`):
#
#   jsrun3 file.js [unit_base]
#
# runs file.js in tier 0; with unit_base (from tools/jsu.sh file.js unit_base) the unit
# is loaded first, so every function it compiled runs natively. JSRUN_TIME=1 prints the
# script time.
JS_IC = i64[8]
use ../runtime/main
use ../runtime/units
use ../runtime/unit_rt
use ../tier0/walk

-> js_dispatch(i, f, this, argc, a0, a1, a2, a3, more)
  c = f.code
  return js_unit_enter(c, f, this, argc, a0, a1, a2, a3, more) if c.entry != 0
  wk_call(f, this, argc, a0, a1, a2, a3, more)

js_new_realm()
JSRUN3_UNIT = [ARGV.size > 1 ? ARGV[1] : nil]
WK_PRE_RUN[0] = ->(an)
  b = JSRUN3_UNIT[0]
  if b != nil
    codes = an.funcs.map(->(jf) wk_code(jf))
    u = js_unit_load(b + ".o", File.read(b + ".json"), codes)
    if u.is_a?(String)
      ccall("w_eputs", "jsrun3: unit not loaded: " + u)
    else
      ccall("w_eputs", "jsrun3: unit loaded, " + u.nentries.to_s + " entries")
    JSRUN3_UNIT[0] = nil
  nil
begin
  wk_run(File.read(ARGV[0]), ARGV[0])
rescue e
  js_report_uncaught(e)
js_finish()
