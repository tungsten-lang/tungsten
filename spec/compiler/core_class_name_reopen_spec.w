# A user `+ Name` whose Name is a core autoload entry REOPENS the core class
# (the same rule as `+ Int` / `+ String`) on every engine: the core
# definition loads first, then the user's body adds to or overrides it.
# There is one class namespace.
#
# Regression: `+ Curve` (core/tungsten.w: `auto :Curve, "algebra"`) forces
# an autoload of core/algebra.w. When that load failed (core/algebra/
# polynomial.w did not parse), the loader skipped it but left the files its
# `use` walk had reached (core/integer.w) marked loaded, so Integer was never
# defined and main referenced an undefined `@class.Integer`. A failing core
# load is now an error, and algebra loads: the user's `new(@p)` sits beside
# core's two-argument constructor in the reopened class.
#
# Run:
#   bin/tungsten spec/compiler/core_class_name_reopen_spec.w
#   bin/tungsten run --interpret spec/compiler/core_class_name_reopen_spec.w
#   bin/tungsten --ruby spec/compiler/core_class_name_reopen_spec.w

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# --- reopen: core methods survive, user methods are added or win -----------
# Interval is demand-loaded (core/numeric/interval.w), not a primitive. The
# Ruby implementation used to define a fresh class here, without core's
# methods, and a later lazy load would have let core's `width` override ours.
+ Interval
  -> width
    "mine"
  -> span
    hi - lo

iv = Interval.new(1, 4)
check("reopen.core_method", iv.contains?(2))
check("reopen.user_override", iv.width == "mine")
check("reopen.user_method", iv.span == 3)

# --- the reported program: a user class named Curve, plus Int -------------
+ Curve
  ro :p
  -> new(@p)

c = Curve("7".to_i)
check("curve_reopen.int_parent_defined", c.p == 7)
check("curve_reopen.int_is_integer", c.p.is_a?(Integer))
