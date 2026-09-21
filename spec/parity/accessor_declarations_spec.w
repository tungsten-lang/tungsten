# Accessor declarations: class-level `ro` / `rw`, several names per line, in
# classes, subclasses and traits. `ro :f` is the method `f` with the body `@f`;
# `rw :f` adds `f=(value)`. Hand-written trivial getters are not idiomatic
# Tungsten, so every engine must agree on the declared form.
#
# Cross-engine parity spec (scripts/parity.sh).

trait Tagged
  ro :tag
  rw :weight

+ Certificate
  ro :proof, :level
  rw :note

  -> new(@proof, @level)
    @note = "none"

  -> describe
    "[proof]/[level]/[note]"

+ SignedCertificate < Certificate
  is Tagged

  -> new(@proof, @level, @tag)
    @note = "signed"
    @weight = 1

c = Certificate.new("abc", 3)
<< "ro [c.proof] [c.level]"
c.note = "changed"
<< "rw [c.note]"
c.note += "!"
<< "rw.op_assign [c.note]"
<< "bare.self [c.describe]"

s = SignedCertificate.new("xyz", 1, "T")
<< "inherited.ro [s.proof] [s.level]"
<< "inherited.rw [s.note]"
<< "trait.ro [s.tag]"
s.weight = s.weight + 41
<< "trait.rw [s.weight]"
<< "inherited.bare.self [s.describe]"
