# A user `+ Name` whose Name is a core autoload entry REOPENS the core class
# (the same rule as `+ Int` / `+ String`) on every engine: the core
# definition loads first, then the user's body adds to or overrides it.
# There is one class namespace.
#
# Regression: `+ Curve` (core/tungsten.w: `auto :Curve, "algebra"`) forces
# an autoload of core/algebra.w. That load is tolerant: when it fails (today
# core/algebra/polynomial.w does not parse), the loader skips it. But the
# failed load's `use` walk had already spliced core/numeric/rational.w, which
# `use`s core/integer.w, and those files stayed marked loaded while their
# expressions were thrown away. A later autoload of Integer (Int < Integer)
# then deduplicated to an empty program, Integer was never defined, and main
# registered Int against `@class.Integer`, an undefined LLVM global, so
# clang rejected the module. The loader now rolls a failed load's files back
# out of @loaded_files. Compiling this file at all is the regression test.
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

# --- a failed tolerant core load must not swallow its dependencies ----------
+ Curve
  ro :p
  -> new(@p)

c = Curve("7".to_i)
check("failed_autoload.int_parent_defined", c.p == 7)
check("failed_autoload.int_is_integer", c.p.is_a?(Integer))
