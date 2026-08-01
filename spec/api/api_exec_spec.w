# Contract spec for the /api/run and /api/check execution engine
# (services/api/lib/exec.w).
#
# Agents consume these fields directly, so the shape is a contract: stdout and
# stderr must stay separate, and outcome/raised/exception must classify how a
# program ended without the caller parsing stderr.
#
# The engine is used in-process — this spec IS a compiled Tungsten program, so
# it calls ApiExec directly rather than shelling out.
#
# Run: `RUN_API_SPECS=1 make specs`, or directly:
#   bin/tungsten -o /tmp/api_spec spec/api/api_exec_spec.w && /tmp/api_spec

use ../../services/api/lib/exec

failures = 0 ## i64

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# --- a clean run -------------------------------------------------------------
r = ApiExec.run("<< \"hello\"\n<< 6 * 7\n")
check("clean.outcome_ok", r[:outcome] == "ok")
check("clean.not_raised", r[:raised] == false)
check("clean.exception_nil", r[:exception] == nil)
check("clean.stdout", r[:stdout] == "hello\n42\n")
check("clean.exit_zero", r[:exit_code] == 0)
check("clean.no_diagnostics", r[:diagnostics].size() == 0)
check("clean.compiled", r[:compiled] == true)

# --- stdout and stderr stay on separate channels -----------------------------
r = ApiExec.run("<< \"to stdout\"\neprint(\"to stderr\\n\")\n")
check("streams.stdout_only", r[:stdout] == "to stdout\n")
check("streams.stderr_only", r[:stderr].strip == "to stderr")
check("streams.outcome_ok", r[:outcome] == "ok")

# --- an uncaught raise is a crash, and partial stdout survives ---------------
r = ApiExec.run("<< \"before\"\nraise \"boom\"\n<< \"after\"\n")
check("raise.outcome", r[:outcome] == "raised")
check("raise.raised_true", r[:raised] == true)
check("raise.partial_stdout", r[:stdout] == "before\n")
check("raise.message", r[:exception][:message] == "boom")
check("raise.located", r[:exception][:line] == 2)
check("raise.file_is_program", r[:exception][:file] == "program.w")
check("raise.is_uncaught_raise", r[:exception][:uncaught_raise] == true)

# --- a rescued raise is NOT a crash ------------------------------------------
r = ApiExec.run("begin\n  raise \"caught\"\nrescue e\n  << \"rescued\"\n")
check("rescued.outcome_ok", r[:outcome] == "ok")
check("rescued.not_raised", r[:raised] == false)
check("rescued.stdout", r[:stdout] == "rescued\n")

# --- a fatal runtime fault: raised, but NOT a catchable raise ----------------
# `undefined method` unwinds past any rescue, so uncaught_raise must be false:
# the fix is in the code, not a begin/rescue.
r = ApiExec.run("x = nil\n<< x.no_such_method\n")
check("fault.outcome", r[:outcome] == "raised")
check("fault.raised_true", r[:raised] == true)
check("fault.not_uncaught_raise", r[:exception][:uncaught_raise] == false)

# --- a deliberate non-zero exit is not a crash -------------------------------
r = ApiExec.run("<< \"done\"\nexit 3\n")
check("exit.outcome", r[:outcome] == "exit")
check("exit.not_raised", r[:raised] == false)
check("exit.code", r[:exit_code] == 3)

# --- check mode: diagnostics, never execution --------------------------------
r = ApiExec.check("<< \"unterminated\n")
check("check.outcome", r[:outcome] == "compile_error")
check("check.not_ok", r[:ok] == false)
check("check.has_diagnostic", r[:diagnostics].size() >= 1)
d = r[:diagnostics][0]
check("check.diag_line", d[:line] == 1)
check("check.diag_file", d[:file] == "program.w")
check("check.diag_code", d[:code] != nil)
check("check.diag_not_runtime", d[:runtime] == false)
check("check.no_stdout", r[:stdout] == "")

# A valid typed signature must NOT be reported as a syntax error: `tungsten -c`
# false-rejects this, which is why check compiles for real.
r = ApiExec.check("fn add(a ## i64, b ## i64) ## i64\n  a + b\n\n<< add(2, 3)\n")
check("check.typed_signature_ok", r[:ok] == true)
check("check.typed_no_diagnostics", r[:diagnostics].size() == 0)

# --- the sandbox gate reports what a program reached for ---------------------
r = ApiExec.run("begin\n  File.read(\"/etc/passwd\")\nrescue e\n  << \"blocked\"\n")
check("sandbox.program_continued", r[:outcome] == "ok")
check("sandbox.attempt_counted", r[:sandbox][:attempts] >= 1)
entry = r[:sandbox][:log][0]
check("sandbox.op_logged", entry["op"] == "read_file")
check("sandbox.target_captured", entry["detail"] == "/etc/passwd")
check("sandbox.blocked_not_stubbed", entry["sandbox"] == "block")

<< "api_exec_spec: all checks passed"
