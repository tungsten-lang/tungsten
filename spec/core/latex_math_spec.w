# Focused interpreted/native checks for typed semantic LaTeX mathematics.
#
# Run interpreted:
#   bin/tungsten run spec/core/latex_math_spec.w
# Run compiled:
#   bin/tungsten compile spec/core/latex_math_spec.w --out /tmp/latex-math-spec
#   /tmp/latex-math-spec

use core/expression

-> latex_math_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

x = LatexMath.symbol(:x)
y = LatexMath.symbol(:y)
one = LatexMath.number(1)
nested = LatexMath.product([LatexMath.sum([x, one]), y])

latex_math_check("surface.concept", nested.concept, "times")
latex_math_check("surface.sort", nested.sort, :scalar)
latex_math_check("surface.number_value", one.number_value, 1)
latex_math_check("surface.symbol_name", x.symbol_name, "x")
latex_math_check("surface.fragment", nested.to_latex.class_name, "LatexFragment")
latex_math_check(
  "precedence.product_sum",
  nested.to_latex.to_s,
  "\\left(x + 1\\right)\\,y")
latex_math_check("render.integration", LaTeX.render(nested).to_s, nested.to_s)
latex_math_check("semantic.integration", LaTeX.semantic(:x).concept, "identifier")

a = LatexMath.symbol(:a)
b = LatexMath.symbol(:b)
c = LatexMath.symbol(:c)
latex_math_check(
  "precedence.quotient_sum",
  LatexMath.quotient(a, LatexMath.sum([b, c])).to_s,
  "\\frac{a}{b + c}")
latex_math_check(
  "precedence.power_base",
  LatexMath.power(LatexMath.power(a, b), c).to_s,
  "\\left(a^{b}\\right)^{c}")
latex_math_check(
  "precedence.power_exponent",
  LatexMath.power(a, LatexMath.power(b, c)).to_s,
  "a^{b^{c}}")
latex_math_check(
  "precedence.negative_integer_base",
  LatexMath.power(LatexMath.number(-2), x).to_s,
  "\\left(-2\\right)^{x}")
latex_math_check(
  "precedence.negative_rational_base",
  LatexMath.power(LatexMath.number(Rational.new(-1, 2)), x).to_s,
  "\\left(-\\frac{1}{2}\\right)^{x}")

nary_sum = LatexMath.sum([x, y, LatexMath.number(2)])
nary_product = LatexMath.product([x, y, LatexMath.number(2)])
latex_math_check("nary.sum", nary_sum.to_s, "x + y + 2")
latex_math_check("nary.product", nary_product.to_s, "x\\,y\\,2")
latex_math_check(
  "nary.negative_later_factor",
  LatexMath.product([x, LatexMath.number(-2)]).to_s,
  "x\\,\\left(-2\\right)")
latex_math_check(
  "nary.two_negative_ones",
  LatexMath.product([LatexMath.number(-1), LatexMath.number(-1)]).to_s,
  "-\\left(-1\\right)")
negative_y = LatexMath.product([LatexMath.number(-1), y])
latex_math_check(
  "nary.negative_summand",
  LatexMath.sum([x, negative_y]).to_s,
  "x - y")

z = Expression.variable(:z)
expression = (z**2 + 1) / (z - 1)
semantic_expression = LaTeX.semantic(expression)
latex_math_check("expression.concept", semantic_expression.concept, "quotient")
latex_math_check(
  "expression.presentation_parity",
  semantic_expression.to_s,
  LaTeX.render(expression).to_s)

absolute = LatexMath.absolute_value(LatexMath.symbol(:A))
determinant = LatexMath.determinant(LatexMath.symbol(:A, :matrix))
latex_math_check("intent.bars_same_source", absolute.to_s, determinant.to_s)
latex_math_check("intent.absolute_concept", absolute.concept, "absolute-value")
latex_math_check("intent.determinant_concept", determinant.concept, "determinant")

set_product = LatexMath.cartesian_product(
  LatexMath.symbol(:A, :set), LatexMath.symbol(:B, :set))
matrix_product = LatexMath.matrix_product(
  LatexMath.symbol(:A, :matrix), LatexMath.symbol(:B, :matrix))
latex_math_check("intent.products_same_source", set_product.to_s, matrix_product.to_s)
latex_math_check("intent.set_product_sort", set_product.sort, :set)
latex_math_check("intent.matrix_product_sort", matrix_product.sort, :matrix)

set_c = LatexMath.symbol(:C, :set)
left_grouped_set_product = LatexMath.cartesian_product(set_product, set_c)
right_grouped_set_product = LatexMath.cartesian_product(
  LatexMath.symbol(:A, :set),
  LatexMath.cartesian_product(LatexMath.symbol(:B, :set), set_c))
latex_math_check(
  "intent.cartesian_left_grouping",
  left_grouped_set_product.to_s,
  "\\left(A \\times B\\right) \\times C")
latex_math_check(
  "intent.cartesian_right_grouping",
  right_grouped_set_product.to_s,
  "A \\times \\left(B \\times C\\right)")

equality = LatexMath.equals(x, y)
latex_math_check("equality.source", equality.to_s, "x = y")
latex_math_check("equality.sort", equality.sort, :proposition)
latex_math_check(
  "equality.equation_integration",
  LaTeX.equation(equality, "eq:semantic").to_s.include?("x = y"),
  true)

terms = [x, y]
copied_sum = LatexMath.sum(terms)
terms.push(one)
returned_children = copied_sum.children
returned_children.push(one)
latex_math_check("immutability.input_copy", copied_sum.children.size, 2)
latex_math_check("immutability.output_copy", copied_sum.to_s, "x + y")

latex_math_check("constants.pi", LatexMath.named_constant(:pi).to_s, "\\pi")
latex_math_check("constants.e", LatexMath.named_constant(:e).to_s, "\\mathrm{e}")
latex_math_check(
  "constants.euler_gamma",
  LatexMath.named_constant(:euler_gamma).to_s,
  "\\gamma")

hostile = LatexMath.symbol("x}\\input{secrets}").to_s
latex_math_check("safety.symbol_escaped", hostile.include?("\\textbackslash{}input"), true)
latex_math_check("safety.no_live_input", hostile.include?("\\input"), false)

scalar_x = LatexMath.symbol(:x)
set_x = LatexMath.symbol(:x, :set)
proposition = LatexMath.equals(x, y)

determinant_scalar_rejected = false
begin
  LatexMath.determinant(scalar_x)
rescue error
  determinant_scalar_rejected = true
latex_math_check("reject.determinant_scalar", determinant_scalar_rejected, true)

cartesian_scalar_rejected = false
begin
  LatexMath.cartesian_product(scalar_x, set_x)
rescue error
  cartesian_scalar_rejected = true
latex_math_check("reject.cartesian_scalar", cartesian_scalar_rejected, true)

mixed_equality_rejected = false
begin
  LatexMath.equals(scalar_x, set_x)
rescue error
  mixed_equality_rejected = true
latex_math_check("reject.mixed_equality", mixed_equality_rejected, true)

proposition_equality_rejected = false
begin
  LatexMath.equals(proposition, proposition)
rescue error
  proposition_equality_rejected = true
latex_math_check("reject.proposition_equality", proposition_equality_rejected, true)

empty_sum_rejected = false
begin
  LatexMath.sum([])
rescue error
  empty_sum_rejected = true
latex_math_check("reject.empty_sum", empty_sum_rejected, true)

one_factor_rejected = false
begin
  LatexMath.product([x])
rescue error
  one_factor_rejected = true
latex_math_check("reject.one_factor", one_factor_rejected, true)

unknown_sort_rejected = false
begin
  LatexMath.symbol(:x, :vector)
rescue error
  unknown_sort_rejected = true
latex_math_check("reject.unknown_sort", unknown_sort_rejected, true)

unknown_concept_rejected = false
begin
  LatexMath.new("custom", [], nil, :scalar)
rescue error
  unknown_concept_rejected = true
latex_math_check("reject.unknown_concept", unknown_concept_rejected, true)

hidden_payload_rejected = false
begin
  LatexMath.new("pi", [], "ignored", :scalar)
rescue error
  hidden_payload_rejected = true
latex_math_check("reject.hidden_payload", hidden_payload_rejected, true)

identifier_payload_rejected = false
begin
  LatexMath.new("identifier", [], :x, :scalar)
rescue error
  identifier_payload_rejected = true
latex_math_check("reject.identifier_payload", identifier_payload_rejected, true)

raw_fragment_rejected = false
begin
  LatexMath.from(LaTeX.raw("x"))
rescue error
  raw_fragment_rejected = true
latex_math_check("reject.raw_fragment", raw_fragment_rejected, true)

string_rejected = false
begin
  LatexMath.from("x")
rescue error
  string_rejected = true
latex_math_check("reject.string", string_rejected, true)

named_constant_rejected = false
begin
  LatexMath.named_constant(:tau)
rescue error
  named_constant_rejected = true
latex_math_check("reject.named_constant", named_constant_rejected, true)

unsupported_expression_rejected = false
begin
  LatexMath.from(Expression.variable(:x).sin)
rescue error
  unsupported_expression_rejected = true
latex_math_check("reject.unsupported_expression", unsupported_expression_rejected, true)

extra_divide_operand_rejected = false
begin
  LatexMath.from(Expression.node("divide", [
    Expression.variable(:x),
    Expression.variable(:y),
    Expression.variable(:z)
  ]))
rescue error
  extra_divide_operand_rejected = true
latex_math_check("reject.extra_divide_operand", extra_divide_operand_rejected, true)

missing_power_operand_rejected = false
begin
  LatexMath.from(Expression.node("power", [Expression.variable(:x)]))
rescue error
  missing_power_operand_rejected = true
latex_math_check("reject.missing_power_operand", missing_power_operand_rejected, true)

extra_abs_operand_rejected = false
begin
  LatexMath.from(Expression.node("abs", [Expression.variable(:x), Expression.variable(:y)]))
rescue error
  extra_abs_operand_rejected = true
latex_math_check("reject.extra_abs_operand", extra_abs_operand_rejected, true)

<< "latex_math_spec: all checks passed"
