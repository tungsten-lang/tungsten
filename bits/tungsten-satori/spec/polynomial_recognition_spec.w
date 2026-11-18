use ../lib/satori

k = KKernel.new
n = mk_var("n", ty_nat)
a = mk_var("a", ty_nat)
add = k.mk_const("+", ty_funs([ty_nat, ty_nat], ty_nat))
mul = k.mk_const("*", ty_funs([ty_nat, ty_nat], ty_nat))
pow = k.mk_const("^", ty_funs([ty_nat, ty_nat], ty_nat))
sub = k.mk_const("-", ty_funs([ty_nat, ty_nat], ty_nat))
two = mk_lit(2, ty_nat)
term = mk_apps(mul, [n, mk_apps(add, [n, two])])
recognized = recurrence_coefficients(k, term, n)
if recognized[0] != 2 || recognized[1][0].val != 0 || recognized[1][1].val != 2 || recognized[1][2].val != 1
  raise "factored quadratic coefficients were not recognized"

# These are valid terms but outside the bounded polynomial recognizer:
# natural truncation, index-dependent opaque atoms, degree four, large powers,
# and a product whose expansion exceeds the monomial limit.
k.declare_const("sequence", ty_fun(ty_nat, ty_nat))
wide = mk_apps(add, [n, a])
i = 0
while i < 6
  wide = mk_apps(mul, [wide, mk_apps(add, [n, a])])
  i += 1
bad = [mk_apps(sub, [n, two]), mk_app(k.mk_const("sequence", ty_fun(ty_nat, ty_nat)), n), mk_apps(pow, [n, mk_lit(4, ty_nat)]), mk_apps(pow, [a, mk_lit(1000, ty_nat)]), wide]
bad.each -> (value)
  rejected = false
  begin
    recurrence_coefficients(k, value, n)
  rescue e
    rejected = true
  if !rejected
    raise "polynomial recognition exceeded its supported algebra or expansion limit"
<< "Polynomial recognition bounds passed"
