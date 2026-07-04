# BitOrdered trait
#
# Include in classes whose values fit in a single i64 wvalue AND where the
# bit-level i64 order corresponds to the desired total ordering of values.
# Subsumes BitEqual. Provides a deterministic O(1) <=> over the underlying
# bits — sort-in-bit-order — which matches the natural ordering for any
# encoding chosen with that property.
#
# Contract: the including class must define -> wvalue_bits returning an i64
# AND the encoding must be designed so that bit-level i64 ordering produces
# the desired value ordering. (For Date/DateTime/Month/Week/Time-of-day, this
# falls out automatically when the encoding stores time-since-epoch in the
# low bits with type-tag bits at the top.)
#
# Examples where this works without further effort:
#   - Date  (days-since-epoch in low bits)
#   - Time  (seconds-since-midnight in low bits)
#   - IP4   (network byte order packed into 32 bits)
#   - Char  (codepoint in low bits)
#
# Examples where this does NOT work (don't include this trait):
#   - Color (component channels — bit order ≠ perceptual order)
#   - UUID  (random — bit order is meaningless)
trait BitOrdered
  with BitEqual

  -> <=>(other)
    if self.class == other.class
      self.wvalue_bits <=> other.wvalue_bits
    else
      nil

  -> <(other)
    self.<=>(other) < 0

  -> <=(other)
    self.<=>(other) <= 0

  -> >(other)
    self.<=>(other) > 0

  -> >=(other)
    self.<=>(other) >= 0
