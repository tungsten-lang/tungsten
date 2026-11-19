use ../lib/satori

k = KKernel.new
rel = ty_funs([ty_rat, ty_rat], ty_bool)
le = k.mk_const("≤", rel)
lt = k.mk_const("<", rel)
first = mk_var("x0", ty_rat)
prev = first
chain = []
i = 1
while i <= 15
  x = mk_var("x" + i.to_s, ty_rat)
  chain.push(k.assume(mk_apps(le, [prev, x])))
  prev = x
  i += 1
if fm_certificate([chain[0]], "rat") != nil
  raise "a feasible inequality produced a contradiction certificate"
# Closing the cycle needs more variables than Fourier–Motzkin's round limit.
chain.push(k.assume(mk_apps(lt, [prev, first])))
proof = k.farkas(chain, fm_certificate(chain, "rat"))
if !tm_eq(proof.concl, k.false_tm) || proof.hyps.size != chain.size || proof.tags != ["oracle:arith"]
  raise "the simplex fallback lost a strict inequality or its hypotheses"
<< "Linear arithmetic certificates passed"
