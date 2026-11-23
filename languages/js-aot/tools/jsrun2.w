# jsrun2 — run a JavaScript file on the new runtime with tier 0 (the tree walker).
#
#   jsrun2 file.js        JSRUN_TIME=1 adds the run time; exit 1 on an uncaught exception

JS_IC = i64[8]
use ../runtime/main
use ../tier0/walk

# Every function in this program is tier 0's.
-> js_dispatch(i, f, this, argc, a0, a1, a2, a3, more)
  wk_call(f, this, argc, a0, a1, a2, a3, more)

if ARGV.size < 1
  << "usage: jsrun2 file.js"
  exit(2)
js_new_realm()
begin
  wk_run(File.read(ARGV[0]), ARGV[0])
rescue e
  js_report_uncaught(e)
js_finish()
