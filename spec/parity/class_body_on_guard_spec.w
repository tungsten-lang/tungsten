# Class-body platform guards: `on <target>` inside a class body holds MEMBERS
# of that class — methods, class methods, accessors — on every engine. A
# matching guard's definition replaces an unguarded fallback of the same
# name; a guard that does not match contributes nothing. Before 2026-09-22
# the compiled registration prepass never saw guarded members (lowered but
# unregistered: "undefined method") and the interpreter evaluated the guard
# as a statement, defining its methods as global functions.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Chip
  -> new
    @label = "chip"

  # Platform fallback, replaced by the guarded definition below.
  -> tier
    "fallback"

  on arm64 || x86_64
    ro :label
    -> tier
      "guarded"
    -> bits
      64
    -> .vendor
      "silicon"

  on riscv64
    -> tier
      "riscv"
    -> exotic
      "never"

  -> describe
    tier + "/" + bits.to_s + "/" + label

c = Chip.new
<< "guarded.method [c.tier]"
<< "guarded.bits [c.bits]"
<< "guarded.accessor [c.label]"
<< "guarded.class_method [Chip.vendor]"
<< "bare.self [c.describe]"
missing = "present"
begin
  c.exotic
rescue error
  missing = "absent"
<< "unmatched.guard [missing]"
