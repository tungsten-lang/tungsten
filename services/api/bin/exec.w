# CLI wrapper around the Tungsten execution engine — prints the response JSON.
#
# The same engine the HTTP service uses, exposed for scripting and for the
# contract spec (spec/api/api_exec_spec.w).
#
#   bin/tungsten -o /tmp/api_exec services/api/bin/exec.w
#   /tmp/api_exec check program.w
#   /tmp/api_exec run   program.w
#
# Reads the program from SOURCE.w and writes one JSON object to stdout.

use ../lib/exec

args = argv()
if args.size < 2
  eprint("usage: exec {check|run} SOURCE.w\n")
  exit 2

mode = args[0]
path = args[1]

unless mode == "check" || mode == "run"
  eprint("usage: exec {check|run} SOURCE.w\n")
  exit 2

source = File.read(path)
if source == nil
  << JSON.encode({ok: false, error: "cannot read source", diagnostics: []})
  exit 1

<< JSON.encode(ApiExec.execute(source, mode))
