use ../tools/bud_holdout

-> require_holdout(ok, label) (bool String) i64
  if !ok
    << "FAIL " + label
    exit(1)
  1

capacity = ffr_default_capacity(2,2,5) ## i64
words = ffr_state_size(capacity) ## i64
original = i64[words]
residual = i64[words]
whole = i64[words]
probe = i64[words]
indices = i64[2]
held = i64[6]
indices[0] = 0
indices[1] = 1
path = "lib/metaflip/seeds/gf2/matmul_2x2x5_rank18_d84_gf2.txt"
loaded = ffbp_load(original,path,2,2,5,capacity,17,16) ## i64
z = require_holdout(loaded == 18,"source load")
z = ffbp_copy(original,residual,words)
z = require_holdout(ffbh_extract(residual,indices,held,2) == 1,"extract")
z = require_holdout(ffbh_remove(residual,held,2) == 1,"remove")
z = require_holdout(residual[6] == 16 && residual[7] == 16,"partial rank")
z = ffbp_copy(residual,probe,words)
z = require_holdout(ffbp_verify(probe,2,2,5) == 0,"partial is NOT full tensor")
z = require_holdout(ffbh_join(residual,whole,words,held,2) == 0,"join")
z = require_holdout(ffbp_verify(whole,2,2,5) == 1 && whole[6] == 18,"identity gate")
z = require_holdout(ffw_view_bits(whole,whole[44],whole[45],whole[46],whole[50],whole[6]) == ffr_current_bits(whole),"density sync")
z = require_holdout(residual[6] == 16 && residual[7] == 16,"observer does not replace partial target")

stride = 21 ## i64
prices = i64[3 * stride]
keys = i64[capacity]
counts = i64[capacity]
grids = i64[3]
j = 0 ## i64
while j < 3 * stride
  prices[j] = j % stride
  j += 1
z = require_holdout(ffbh_cost(whole,residual,0,1,prices,stride,keys,counts,grids) == 17,"fixed cover price")
z = require_holdout(ffbh_cost(whole,residual,0,3,prices,stride,keys,counts,grids) == 18,"ordinary cover wins")
z = require_holdout(ffbh_cost(whole,residual,1,1,prices,stride,keys,counts,grids) == 18,"cancelled holdout cannot claim cover")
z = require_holdout(ffbh_cost(whole,residual,0,0,prices,stride,keys,counts,grids) == 18,"disabled cover preserves old score")
z = require_holdout(residual[6] == 16 && whole[6] == 18,"cost leaves states untouched")
z = ffbp_copy(residual,probe,words)
probe[6] = stride
z = require_holdout(ffbh_cost(whole,probe,0,1,prices,stride,keys,counts,grids) == 18,"sentinel cannot overflow")
probe[6] = 0
z = require_holdout(ffbh_cost(whole,probe,0,1,prices,stride,keys,counts,grids) == 1,"empty remainder cost")
z = require_holdout(ffbh_join(original,whole,words,held,2) == 2 && whole[6] == 16,"join cancellation accounting")
z = require_holdout(ffbp_verify(whole,2,2,5) == 0 && original[6] == 18,"cancelled wrong target rejected without source mutation")
z = ffbp_copy(original,probe,words)
probe[4] = 18
z = require_holdout(ffbh_join(probe,whole,words,held,2) == 0-1,"join capacity gate")

# Invalid index/missing-term gates cannot mutate the source state.
indices[1] = 0
z = require_holdout(ffbh_extract(original,indices,held,2) == 0,"duplicate index")
indices[1] = 18
z = require_holdout(ffbh_extract(original,indices,held,2) == 0,"out-of-range index")
indices[1] = 1
z = require_holdout(ffbh_extract(original,indices,held,2) == 1,"re-extract")
z = require_holdout(ffbh_remove(residual,held,2) == 0 && residual[6] == 16,"missing held term")
held[0] = held[0] ^ 2
z = require_holdout(ffbh_join(residual,whole,words,held,2) >= 0,"mutant reinsert")
z = require_holdout(ffbp_verify(whole,2,2,5) == 0,"wrong held coefficients rejected")
z = require_holdout(ffbh_extract(original,indices,held,2) == 1,"restore held coefficients")

# Walk the arbitrary residual target, then check the complete tensor after
# every span, including the periodic rectangular split at attempt 2000.
i = 0 ## i64
while i < 80
  z = ffbp_wander(residual,128,2,2,5)
  joined = ffbh_join(residual,whole,words,held,2) ## i64
  z = require_holdout(joined >= 0 && ffbp_verify(whole,2,2,5) == 1,"walk identity")
  z = require_holdout(ffw_view_bits(whole,whole[44],whole[45],whole[46],whole[50],whole[6]) == ffr_current_bits(whole),"walk density")
  i += 1
<< "PASS holdout residual and full tensor gates"
