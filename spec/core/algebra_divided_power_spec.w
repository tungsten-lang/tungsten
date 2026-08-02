# Exact characteristic-two divided squares and binary carry.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_divided_power_spec.w
#   bin/tungsten compile spec/core/algebra_divided_power_spec.w \
#     --out /tmp/algebra-divided-power-spec

use algebra

-> divided_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> divided_same_vector?(left, right)
  return false if left.size != right.size
  i = 0
  while i < left.size
    return false if left[i] != right[i]
    i += 1
  true

space = DividedSquareSpace.new(3)
divided_check("dimension", space.divided_dimension == 6)
divided_check("basis_pairs",
              space.basis_pairs.to_s ==
                "\[\[0, 0\], \[0, 1\], \[0, 2\], \[1, 1\], \[1, 2\], \[2, 2\]\]")
divided_check("square",
              divided_same_vector?(
                space.square([1, 0, 1]), [1, 0, 1, 0, 0, 1]))
divided_check("polarization.diagonal_zero",
              divided_same_vector?(
                space.polarization([1, 0, 0], [0, 1, 0]),
                [0, 1, 0, 0, 0, 0]))
divided_check("quadratic.identity",
              divided_same_vector?(
                space.square(space.add([1, 0, 1], [0, 1, 1])),
                space.add_divided(
                  space.add_divided(
                    space.square([1, 0, 1]), space.square([0, 1, 1])),
                  space.polarization([1, 0, 1], [0, 1, 1]))))

swap = [[0, 1, 0], [1, 0, 0], [0, 0, 1]]
swap_certificate = space.action_certificate(swap)
divided_check("action.kind",
              swap_certificate.proof_kind == :exact_f2_divided_square_action)
divided_check("action.swap.verified", swap_certificate.verified?)
shear = [[1, 1, 0], [0, 1, 1], [0, 0, 1]]
divided_check("action.shear.verified",
              space.action_certificate(shear).verified?)

# For the direct law every nonidentity element has order two. The carry law
# has order-four elements because c(l,l) retains the divided-square diagonal.
group = BinaryCarryGroup.new(2)
generator = group.element([1, 0])
divided_check("direct.order_two", group.order(generator, :direct) == 2)
divided_check("carry.order_four", group.order(generator, :carry) == 4)
square = group.carry_product(generator, generator)
divided_check("carry.square.linear_zero",
              divided_same_vector?(square[0], [0, 0]))
divided_check("carry.square.diagonal",
              divided_same_vector?(square[1], [1, 0, 0]))
divided_check("carry.inverse",
              group.identity?(
                group.carry_product(generator, group.inverse(generator))))

# Exhaust pairwise commutativity in the 32-element rank-two group. For
# associativity it is enough (and much cheaper in the interpreter) to replay
# the bilinear cocycle identity on all 4^3 triples of linear coordinates:
# the quadratic coordinates enter the product only by ordinary addition.
elements = group.elements
commutative = true
elements.each -> (left)
  elements.each -> (right)
    commutative = false if !group.same_element?(
      group.carry_product(left, right), group.carry_product(right, left))
divided_check("carry.commutative.exhaustive", commutative)

linear_vectors = [[0, 0], [0, 1], [1, 0], [1, 1]]
cocycle = true
linear_vectors.each -> (left)
  linear_vectors.each -> (middle)
    linear_vectors.each -> (right)
      first = group.space.add_divided(
        group.space.carry(left, middle),
        group.space.carry(group.space.add(left, middle), right))
      second = group.space.add_divided(
        group.space.carry(middle, right),
        group.space.carry(left, group.space.add(middle, right)))
      cocycle = false if !divided_same_vector?(first, second)
divided_check("carry.associative.cocycle_exhaustive", cocycle)

<< "algebra_divided_power_spec: all checks passed"
