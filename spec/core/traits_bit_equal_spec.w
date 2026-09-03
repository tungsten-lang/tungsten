# BitEqual trait (core/traits/bit_equal.w): a class whose whole identity is
# one i64 (`wvalue_bits`) gets ==, !=, eql? and hash from the trait —
# equality iff same class and same bits, hash == the bits themselves — and
# different classes never compare equal. (Hash *keys* remain identity-keyed
# for object values by runtime design, so the trait is a value predicate,
# not a re-keying hook; that is asserted below too.) The trait is not in the
# autoload manifest, so user code loads it with `use core/traits/bit_equal`.
#
# Run in both engines:
#   bin/tungsten run --interpret spec/core/traits_bit_equal_spec.w
#   bin/tungsten -o /tmp/traits-bit-equal-spec spec/core/traits_bit_equal_spec.w && /tmp/traits-bit-equal-spec

use core/traits/bit_equal

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# A packed RGB colour: identity is the 24-bit integer, nothing else.
+ Rgb
  is BitEqual

  -> new(bits)
    @bits = bits

  -> wvalue_bits
    @bits

# A different class carrying the same bits must not compare equal.
+ Opaque
  is BitEqual

  -> new(bits)
    @bits = bits

  -> wvalue_bits
    @bits

red = Rgb.new(0xFF0000)
red_again = Rgb.new(0xFF0000)
blue = Rgb.new(0x0000FF)
big = Rgb.new(4611686018427387903)
big_again = Rgb.new(4611686018427387903)
neg = Rgb.new(-42)
neg_again = Rgb.new(-42)

check("eq.same_bits", red == red_again)
check("eq.self", red == red)
check("eq.different_bits", !(red == blue))
check("ne.different_bits", red != blue)
check("ne.same_bits", !(red != red_again))
check("eql.same_bits", red.eql?(red_again))
check("eql.different_bits", !red.eql?(blue))
check("eq.large_bits", big == big_again)
check("eq.large_vs_small", !(big == red))
check("eq.negative_bits", neg == neg_again)
check("ne.negative_vs_positive", neg != red)

# hash is exactly the bits, so equal values hash equal and distinct values
# with distinct bits hash differently
check("hash.is_bits", red.hash == 0xFF0000)
check("hash.equal_values", red.hash == red_again.hash)
check("hash.distinct_values", red.hash != blue.hash)
check("hash.negative", neg.hash == -42)
check("hash.large", big.hash == 4611686018427387903)

# cross-class: same bits, different class
other = Opaque.new(0xFF0000)
check("cross.eq_false", !(red == other))
check("cross.ne_true", red != other)
check("cross.eql_false", !red.eql?(other))
check("cross.hash_collides", red.hash == other.hash)

# Hash keys: object keys are IDENTITY-keyed by design (runtime.c: hash-table
# probing uses w_hash_value, which is identity for object values, and
# w_hash_key_eq never dispatches a user-defined `eql?`). So the trait gives
# value-level `==`/`eql?`/`hash` predicates, not Hash re-keying: three
# distinct objects are three distinct keys even when two are `==`.
table = {}
table[red] = "first"
table[red_again] = "second"
table[blue] = "third"
check("hashkey.identity_keyed", table.size == 3)
check("hashkey.own_key", table[red] == "first")
check("hashkey.equal_object_is_a_separate_key", table[red_again] == "second")
check("hashkey.fresh_equal_object_misses", table[Rgb.new(0xFF0000)] == nil)
check("hashkey.lookup_other", table[blue] == "third")

# Symmetry and transitivity on a few values
a = Rgb.new(7)
b = Rgb.new(7)
c = Rgb.new(7)
check("eq.symmetric", (a == b) == (b == a))
check("eq.transitive", (a == b) && (b == c) && (a == c))

<< "traits_bit_equal_spec: all checks passed"
