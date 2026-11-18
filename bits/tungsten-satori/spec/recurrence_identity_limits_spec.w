use ../lib/satori

k = KKernel.new
n = mk_var("n", ty_nat)
r = mk_var("r", ty_nat)
plus = k.mk_const("+", ty_funs([ty_nat, ty_nat], ty_nat))
power = k.mk_const("^", ty_funs([ty_nat, ty_nat], ty_nat))
shift3 = mk_apps(power, [r, mk_apps(plus, [n, mk_lit(3, ty_nat)])])
if !recurrence_formula?(k, shift3, n, [64])
  raise "recurrence identity did not recognize the supported successor boundary"
k.declare_const("unknown", ty_fun(ty_nat, ty_nat))
unsupported = [mk_apps(power, [r, mk_apps(plus, [n, mk_lit(4, ty_nat)])]), mk_apps(power, [n, n]), mk_app(k.mk_const("unknown", ty_fun(ty_nat, ty_nat)), n), mk_apps(power, [n, mk_lit(4, ty_nat)])]
unsupported.each -> (value)
  if recurrence_formula?(k, value, n, [64])
    raise "recurrence identity accepted an unsupported closed form"
if recurrence_formula?(k, shift3, n, [0])
  raise "recurrence identity ignored its formula budget"
sequence = mk_app(k.mk_const("unknown", ty_fun(ty_nat, ty_nat)), n)
slots = [4, []]
if !recurrence_formula?(k, sequence, n, [64], slots) || slots[0] != 3
  raise "coupled recurrence did not count its sequence atom"
repeated_sum = mk_apps(plus, [sequence, mk_apps(plus, [sequence, mk_apps(plus, [sequence, sequence])])])
if !recurrence_formula?(k, repeated_sum, n, [64], [1, []])
  raise "coupled recurrence counted repeated occurrences as distinct sequences"
atoms = [sequence]
["second", "third", "fourth", "fifth"].each -> (name)
  k.declare_const(name, ty_fun(ty_nat, ty_nat))
  atoms.push(mk_app(k.mk_const(name, ty_fun(ty_nat, ty_nat)), n))
four = mk_apps(plus, [atoms[0], mk_apps(plus, [atoms[1], mk_apps(plus, [atoms[2], atoms[3]])])])
if !recurrence_formula?(k, four, n, [64], [4, []]) || recurrence_formula?(k, four, n, [64], [3, []])
  raise "coupled recurrence ignored its four-sequence bound"
five = mk_apps(plus, [four, atoms[4]])
shifted = mk_app(k.mk_const("unknown", ty_fun(ty_nat, ty_nat)), mk_apps(plus, [n, mk_lit(1, ty_nat)]))
nested = mk_app(k.mk_const("unknown", ty_fun(ty_nat, ty_nat)), sequence)
k.declare_const("family", ty_funs([ty_nat, ty_nat], ty_nat))
repeated = mk_apps(k.mk_const("family", ty_funs([ty_nat, ty_nat], ty_nat)), [n, n])
[five, shifted, nested, repeated].each -> (value)
  if recurrence_formula?(k, value, n, [64], [4, []])
    raise "coupled recurrence accepted an unsupported sequence shape"
if recurrence_formula?(k, sequence, n, [64], [0, []]) || recurrence_formula?(k, sequence, n, [0], [4, []])
  raise "coupled recurrence ignored its exhausted budget"
<< "Recurrence identity bounds passed"
