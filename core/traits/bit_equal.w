# BitEqual trait
#
# Include in classes whose values fit in a single i64 wvalue (e.g. Date,
# Color, IP4, UUID, Char). Equality and hashing become i64-level operations
# with no per-class logic — the entire identity of the value lives in the
# tagged 64 bits.
#
# Contract: the including class must define -> wvalue_bits returning an i64.
# Two values are equal iff they belong to the same class AND their bits are
# equal as i64. Hash is just the i64 itself.
trait BitEqual
  -> ==(other)
    self.class == other.class && self.wvalue_bits == other.wvalue_bits

  -> !=(other)
    !(self == other)

  -> hash
    self.wvalue_bits

  -> eql?(other)
    self == other
