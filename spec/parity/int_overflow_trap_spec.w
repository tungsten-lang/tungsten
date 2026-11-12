# `Math.trap ->` abort: once a +,-,* result leaves the inline i48 range the
# compiled guarded arm branches to llvm.trap (SIGTRAP, exit 133, no message,
# not rescuable); the interpreter's maybe_wrap_int_arith reaches the same
# instruction through w_int_overflow_trap. The transcript is everything
# printed before the abort plus the exit status — `flush` drains stdout
# first, because a trap skips the runtime's exit-time flush on both engines.
#
# Cross-engine parity spec (scripts/parity.sh).

a = 140737488355327 ## i64
<< "trap.before [a]"
flush
begin
  Math.trap ->
    b = a + 1
    << "unreachable [b]"
rescue e
  << "unreachable.rescue [e]"
<< "unreachable.after"
