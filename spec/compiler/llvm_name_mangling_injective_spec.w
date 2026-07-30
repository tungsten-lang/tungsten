# LLVM symbol mangling must be injective. `α` transliterates to `_u0003b1_`,
# and `_u0003b1_` is itself a legal identifier -- before the marker-escape
# rule in llvm_safe_name (lowering/pass_registry.w), a program using both
# names collapsed them onto one LLVM symbol: clang rejected the duplicate
# global, and same-scope locals silently merged. The literal spelling now
# escapes its leading underscore (`_u00005f_u0003b1_`), so the two names
# stay distinct symbols.
#
# Run: `bin/tungsten -o /tmp/lnmi spec/compiler/llvm_name_mangling_injective_spec.w && /tmp/lnmi`

α = 100
_u0003b1_ = 200

-> check(label, got, want)
  if got == want
    << "PASS " + label
  else
    << "FAIL " + label + " got " + got.to_s() + " want " + want.to_s()

check("global.greek", α, 100)
check("global.marker_literal", _u0003b1_, 200)
check("global.distinct", α != _u0003b1_, true)

α = α + 1
check("global.greek_write", α, 101)
check("global.marker_untouched", _u0003b1_, 200)

_u0003b1_ = _u0003b1_ + 5
check("global.marker_write", _u0003b1_, 205)
check("global.greek_untouched", α, 101)

-> local_pair
  β = 7
  _u0003b2_ = 11
  β * 1000 + _u0003b2_

check("local.distinct", local_pair, 7011)
