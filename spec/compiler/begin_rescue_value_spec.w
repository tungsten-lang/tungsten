# begin/rescue is a VALUE expression: in value position (method tail, case
# arm, if arm, assignment rhs) it produces the taken arm's last expression.
# Before 2026-07-22 (round-3 bug 2) the compiled path lowered :begin as a
# statement in these positions and BOTH arms reached callers as nil (the
# interpreter was already correct). ensure runs for effect only — it never
# replaces the value (Ruby semantics).
#
# Run: `bin/tungsten -o /tmp/brv spec/compiler/begin_rescue_value_spec.w && /tmp/brv`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> boom
  raise "x"

-> r_int
  begin
    boom()
    1
  rescue e
    42

-> r_hash
  begin
    boom()
    {ok: 1}
  rescue e
    {fb: 7, reason: "caught"}

-> r_body_arm
  begin
    {ok: 5}
  rescue e
    {fb: 7}

-> r_with_ensure(log)
  begin
    boom()
    "body"
  rescue e
    "rescued"
  ensure
    log.push("ensured")

-> r_assign_rhs
  v = begin
    boom()
    10
  rescue e
    20
  v + 1

check("rescue.int", r_int(), 42)
h = r_hash()
check("rescue.hash_fb", h[:fb], 7)
check("rescue.hash_reason", h[:reason], "caught")
b = r_body_arm()
check("rescue.body_arm", b[:ok], 5)
log = []
check("rescue.value_with_ensure", r_with_ensure(log), "rescued")
check("rescue.ensure_ran", log.size(), 1)
check("rescue.assign_rhs", r_assign_rhs(), 21)
