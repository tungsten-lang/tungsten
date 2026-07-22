# Dynamic (untyped-receiver) dispatch of String/Symbol size and length —
# round-5, 2026-07-22. When a receiver's static type is unknown (e.g. a
# function-returned value), `.size()` goes through cached dynamic dispatch.
# The type-class cascade fails to resolve core String/Symbol SOURCE methods
# (String#size exists in core/string_native.w but the lookup misses — a
# pre-existing gap, reproducible at f8b236ce), so these died with
# "undefined method 'size' for String". size/length are now served by IC
# entries with source-identical semantics (byte length; symbols via to_s).
#
# KNOWN REMAINING GAP (documented, not fixed here): other core String
# source methods (reverse, chars, bytes, swapcase, …) are still unreachable
# through DYNAMIC dispatch for the same cascade reason. Statically-typed
# call sites are unaffected. See w_cacheable_type_class_method /
# w_type_class_method in runtime.c.
#
# Run: `bin/tungsten -o /tmp/sdd spec/compiler/string_dynamic_dispatch_spec.w && /tmp/sdd`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> f(x)
  x

check("dyn.sso_size", f("hello").size(), 5)
check("dyn.heap_size", f("hello world longer!").size(), 19)
check("dyn.empty_size", f("").size(), 0)
check("dyn.length_alias", f("hello").length(), 5)
check("dyn.utf8_bytes", f("héllo").size(), 6)
check("dyn.symbol_size", f(:hello).size(), 5)
check("dyn.symbol_length", f(:hello).length(), 5)

n = f(88172645463325252)
check("dyn.chained_to_s_size", n.to_s().size(), 17)
check("dyn.chained_in_interp", "[n.to_s().size()]", "17")
check("dyn.smallint_chain", f(12345).to_s().size(), 5)
check("dyn.cmp_in_interp", "[n.to_s().size() > 20]", "false")
