# Postfix `rescue` (rescue_expr) must not crash the compiler's loader walkers.
#
# rescue_expr packs its body and fallback as SINGLE AST nodes in :ast fields.
# The loader's autoload/array-literal walkers treated every body-ish field as
# a node list and called .size() on it — nil on an AST node — so `i < nil`
# raised "expected int, got nil" inside the compiled compiler as soon as a
# program contained a postfix rescue (the reduced form of the carbide/forge
# regression: `@socket.close rescue nil` in forge's connection.w). Before the
# ops.w raw-compare guard (272bb50) the miscompiled compare nanunboxed nil to
# 0 and the walk silently no-oped — hiding both the crash AND the autoload
# holes below. Compiling this file at all is the regression test; the checks
# pin the semantics on both engines.
#
# Run both engines:
#   bin/tungsten-compiler run spec/compiler/postfix_rescue_loader_spec.w
#   bin/tungsten -o /tmp/prl spec/compiler/postfix_rescue_loader_spec.w && /tmp/prl

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> boom
  <! Error.new("boom")

# --- the reduced crasher: statement-form postfix rescue in a method body ----
+ PostfixRescueProbe
  -> close
    boom() rescue nil
    "closed"

probe = PostfixRescueProbe.new
check("rescue_expr.statement.catches", probe.close == "closed")

# --- value forms -------------------------------------------------------------
ok = 7 rescue "nope"
check("rescue_expr.value.try_side", ok == 7)

caught = (boom() rescue "caught")
check("rescue_expr.value.fallback_side", caught == "caught")

# --- the fallback runs exactly when the guarded expression raises ------------
log = []
boom() rescue log.push("hit")
7 rescue log.push("miss")
check("rescue_expr.fallback.side_effects", log.size() == 1 && log[0] == "hit")

# --- autoload reaches classes named ONLY inside a postfix rescue -------------
# JSON appears only in the guarded expression; Base64 only in a fallback.
# Pre-fix, the loader never walked either position (silently on the old
# compiler, crashing on the new one), so these constants resolved to nil.
encoded = JSON.encode({k: 1}) rescue "none"
check("rescue_expr.autoload.body", encoded.include?("k"))

fell = (boom() rescue Base64.encode("z"))
check("rescue_expr.autoload.fallback", fell != nil && fell != "")

# --- array literals inside a rescue arm keep the array analysis walking ------
arr = [1, 2, 3] rescue nil
check("rescue_expr.array_literal.body", arr.size() == 3 && arr.uniq.size() == 3)

<< "PASS postfix rescue loader"
