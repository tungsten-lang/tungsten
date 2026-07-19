# Spec groups and examples — describe/context/it.
# Groups execute immediately: describe prints its heading, bumps the
# indent, snapshots the hook stacks, runs its block, then unwinds.
# `it` runs its block right away under before/after hooks; any raise
# (expectation failure or runtime error) fails the example and the
# suite continues.
#
# IMPLEMENTATION CONSTRAINTS (verified by probes; keep these invariants):
#   - A raise unwinding across a stored-lambda `.call` boundary SEGFAULTS
#     the interpreter, but raising through a direct `&()` yield rescued in
#     the same method works. So `it` and `describe` invoke their blocks
#     with a direct `&()` and rescue locally — no body-lambda indirection.
#   - A statement starting with a `$global` directly after a dedent
#     misparses (`$name` binds as a view-field postfix on the preceding
#     expression). Global mutations after dedents go through helper fns
#     (spec_depth_up/down, spec_unwind_group) whose `$` statement opens
#     the body, which is safe.
# describe and context therefore carry duplicated bodies on purpose.

-> describe(subject, &)
  << spec_indent + "[subject]"
  spec_depth_up
  nb = $spec_before_each.size
  na = $spec_after_each.size
  nz = $spec_after_all_pending.size
  &()
  spec_unwind_group(nb, na, nz)
  nil

-> context(subject, &)
  << spec_indent + "[subject]"
  spec_depth_up
  nb = $spec_before_each.size
  na = $spec_after_each.size
  nz = $spec_after_all_pending.size
  &()
  spec_unwind_group(nb, na, nz)
  nil

-> it(desc, &)
  spec_clear_failure
  err = nil
  begin
    spec_run_hooks($spec_before_each)
    &()
  rescue e
    err = e
  begin
    spec_run_hooks($spec_after_each)
  rescue e2
    if err == nil
      err = e2
  fail_msg = $spec_current_failure
  if fail_msg == nil
    fail_msg = err
  if fail_msg == nil
    spec_record_pass(desc)
  else
    spec_record_fail(desc, fail_msg)
  nil

# Pending/skipped examples — counted, never run.
-> pending(desc, &)
  spec_record_pending(desc)

-> skip(desc)
  spec_record_pending(desc)

# --- Inert stubs (documented limitations) ---
# The language has no instance_eval/method_missing, so a `let` binding
# cannot be injected as a bare name inside examples. These accept the
# call so suites parse and run; an example referencing the bare name
# fails individually with a clear "Undefined variable" message while the
# rest of the suite keeps running. Pass values explicitly instead.

-> let(name, &)
  nil

-> let!(name, &)
  nil

-> subject(&)
  nil
