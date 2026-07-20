# Repro: Array#shuffle / #shuffle! were broken on the compiled and
# self-hosted engines by TWO same-disease bugs (Array#rotate was already
# fine on all three engines; it is pinned here as a cheap regression guard):
#
#   1. The bodies called `array_shuffle` / `array_shuffle!`, externs that
#      only ever existed as Ruby-engine builtins (undefined method on the
#      other two engines since inception — exactly the array_mergesort
#      disease fixed in c69d2b9).
#   2. The parameter was a `*args` splat, but variadic splat packing is not
#      implemented on the compiled/self-hosted engines — a splat binds nil
#      for zero args (and the raw first value, not a 1-element array, for
#      one), so `args.size` raised before the extern was even reached.
#
# Fixed by adding the runtime's secure unbiased Fisher-Yates w_array_shuffle
# (whitelisted in the interpreter's ccall bridge), and rewriting shuffle to a
# plain optional `sel` param (no splat). shuffle! sorts a copy back through
# `[]=` like sort!.  The Ruby engine keeps its own shuffle method builtin, so
# this source runs only on the compiled + self-hosted engines.
#
# shuffle output is random, so every assertion below is a deterministic
# PERMUTATION property (elements/size preserved) or an in-place/return
# contract — never a fixed order — so compiled and interpreted stay
# byte-identical.

# --- shuffle: fresh copy, same multiset, source untouched --------------
orig = [1, 2, 3, 4, 5, 6, 7, 8]
s = orig.shuffle
<< "shuffle_perm=" + (s.sort.to_s == orig.to_s).to_s
<< "shuffle_size=" + s.size.to_s
<< "shuffle_src_unchanged=" + orig.to_s

# --- shuffle actually randomizes (not a no-op) -------------------------
# 12 independent shuffles of 8 distinct elements: at least one differs from
# the input with overwhelming probability (a no-op returns the input every
# time, failing this).
differs = false
i = 0
while i < 12
  if orig.shuffle.to_s != orig.to_s
    differs = true
  i += 1
<< "shuffle_randomizes=" + differs.to_s

# --- shuffle!: in place, returns self, same multiset -------------------
# (`bcopy` is compared against rather than a bracketed string literal, which
# would be parsed as `[...]` string interpolation.)
b = [30, 10, 20]
bcopy = [30, 10, 20]
r = b.shuffle!
<< "shuffle_bang_perm=" + (b.sort.to_s == bcopy.sort.to_s).to_s
# The returned value IS the receiver: mutating it mutates b.
r.push(99)
<< "shuffle_bang_returns_self=" + b.include?(99).to_s

# --- indexed-gather overload (a leading Array selects positions) -------
<< "gather=" + [7, 8, 9].shuffle([2, 0, 1]).to_s

# --- empty / singleton edges -------------------------------------------
<< "shuffle_empty=" + [].shuffle.to_s
<< "shuffle_one=" + [42].shuffle.to_s

# --- rotate (already worked; regression guard) -------------------------
q = [1, 2, 3, 4]
<< "rotate1=" + q.rotate.to_s
<< "rotate2=" + q.rotate(2).to_s
<< "rotate_neg=" + q.rotate(-1).to_s
<< "rotate_wrap=" + q.rotate(6).to_s
<< "rotate0=" + q.rotate(0).to_s
<< "rotate_src_unchanged=" + q.to_s
<< "rotate_empty=" + [].rotate.to_s

# rotate!: in place, returns self.
p = [1, 2, 3, 4]
rp = p.rotate!(1)
<< "rotate_bang=" + p.to_s
rp.push(5)
<< "rotate_bang_returns_self=" + p.include?(5).to_s
