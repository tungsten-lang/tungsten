# Satori — a concise proof language with a small LCF-style kernel.
#
# Trusted base: term.w (data), kernel.w, eval.w, checkers.w.
# Everything else (elaboration, tactics, automation) builds theorems only
# through the kernel's rules.

use term
use printer
use checkers
use eval
use kernel
use derived
use lexer
use parser
use elab
use simp
use arith
use satbridge
use tactics
use pattern
use session

SATORI_VERSION = "0.1.0"

-> satori_usage
  << "Satori [SATORI_VERSION] — a concise proof language with a small kernel"
  << ""
  << "USAGE"
  << "    satori check FILE.sat ...     check proofs (default command)"
  << "    satori stats FILE.sat ...     check and print line/theorem counts"
  << "    satori version"
  << ""
  << "ENVIRONMENT"
  << "    SATORI_ROOT     Tungsten checkout (prelude + SAT solver); default: cwd"
  << "    SATORI_SOLVER   external SAT solver emitting LRAT (default: wassat)"

-> satori_main(args)
  if args.size == 0 || args[0] == "help" || args[0] == "--help"
    satori_usage
    return 0
  if args[0] == "version"
    << "satori " + SATORI_VERSION
    return 0
  files = args
  stats = false
  if args[0] == "check" || args[0] == "stats"
    stats = args[0] == "stats"
    files = args.slice(1, args.size - 1)
  root = Env.get("SATORI_ROOT")
  if root == nil || root == ""
    root = Dir.pwd
  failures = 0
  files.each -> (f)
    s = Session.new(root)
    s.load_prelude
    t0 = ccall("__w_clock")
    s.run_file(f)
    dt = ccall("__w_clock") - t0
    failures += s.failures
    st = s.stats
    status = "OK"
    if s.failures > 0
      status = "FAILED (" + s.failures.to_s + ")"
    << "── " + f + ": " + status + " — " + s.stats_line + ", " + (st["lines"]).to_s + " lines, " + ((dt * ~1000.0).round / ~1000.0).to_s + " s"
  if failures > 0
    return 1
  0
