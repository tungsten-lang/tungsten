# Promotion determinism — compiled-engine semantics (wrap by design).
#
# (a) Raw-int promotion of a top-level var must not depend on the NAME of
# the var. The promotion verifier used to walk autoloaded core class/method
# bodies position-blind, so any name that happened to be a core-method
# local (x, q, …) escaped and stayed boxed while ab/foo promoted — the same
# program changed answers under alpha-renaming. Nested definitions are
# their own scope: only FREE reads (read before any binding assignment)
# reach the enclosing global slot.
#
# (b) A nested definition that DOES free-read an enclosing top-level var
# must keep pinning it boxed — reads resolve to the global slot, assigns
# shadow from the point of assignment onward (both engines agree).
#
# (c) A boxed `:int` value crossing into a machine-typed slot truncates
# DEFINED (w_to_i64 family, low 64 bits) — never nanunbox, which reads
# pointer bits from a promoted BigInt (nondeterministic allocator garbage).
#
# Compiled-only: (a)'s wrap answers are the i64-default machine semantics;
# the walker's exact answers differ by design on unhinted overflow shapes.
# Run: bin/tungsten -o /tmp/pd spec/compiler/promotion_determinism_spec.w && /tmp/pd

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# (a) Alpha-renaming invariance: identical shape under five names, spanning
# the ones core methods use heavily (x, q) and ones they don't (ab, foo).
# Each var gets a beyond-i64 integer from to_i, then reduces mod 97 — the
# promoted raw slot holds the defined low-64 truncation, so every name must
# give the same answer.
nines = "9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
x = nines.to_i
check("alpha.x", x % 97, -1)
q = nines.to_i
check("alpha.q", q % 97, -1)
z = nines.to_i
check("alpha.z", z % 97, -1)
ab = nines.to_i
check("alpha.ab", ab % 97, -1)
foo = nines.to_i
check("alpha.foo", foo % 97, -1)

# (b) Free reads from nested definitions still pin the var boxed — the
# global slot stays live and exact.
gx_read = 41
-> peek_gx
  gx_read + 1
check("freeread.fn_sees_global", peek_gx, 42)

gx_cls = 5
+ PromoSpecPeek
  -> peek
    gx_cls + 2
check("freeread.method_sees_global", PromoSpecPeek.new.peek, 7)

# Assign-shadowing: a nested def that assigns the name binds a fresh local
# (point of assignment onward); the outer var is untouched, and because the
# def's reads are all bound, the outer var is free to promote.
gx_shadow = 5
-> bump_shadow
  gx_shadow = 9
  gx_shadow
check("shadow.inner_local", bump_shadow, 9)
check("shadow.outer_untouched", gx_shadow, 5)

# (c) Defined truncation: the RHS multiply promotes to a heap BigInt at
# runtime (beyond-i64 literal operand), and the `## u64` machine slot must
# receive its low 64 bits — 7 * (2^64 - 1) ≡ -7 ≡ 2^64 - 7 (mod 2^64).
-> wrap_u64(v, doit)
  if doit
    v = (v * 18446744073709551615) ## u64
  v
check("defined_trunc.u64", wrap_u64(7, true).to_s(), "18446744073709551609")
check("defined_trunc.untouched", wrap_u64(7, false), 7)

<< "promotion_determinism_spec: all checks passed"
