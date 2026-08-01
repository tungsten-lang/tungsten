# Offline Koala state/action-value experiment for Metaflip CPU windows.
#
# Construct exact planted rank-debt states from record schemes, race four
# move families for an equal move budget, and ask whether state features plus
# the proposed arm predict rank recovery. All arms from one state stay in the
# same train/validation/test tranche, preventing sibling-state leakage.

use ../../../bits/tungsten-metaflip/lib/metaflip/scheme
use ../../../bits/tungsten-koala/lib/koala

CPU_WINDOW_FEATURES = [
  :n, :debt, :rank, :density,
  :u_weight_sum, :v_weight_sum, :w_weight_sum,
  :u_weight_max, :v_weight_max, :w_weight_max,
  :u_singletons, :v_singletons, :w_singletons,
  :u_partner_pairs, :v_partner_pairs, :w_partner_pairs,
  :pressure_sum8, :pressure_max8, :arm
]

-> ffmw_clone_current(src, seed)
  n = src[2] ## i64
  rank = src[6] ## i64
  capacity = src[4] ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  copied = ffw_export_current(src, us, vs, ws) ## i64
  return nil if copied != rank
  out = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(out, us, vs, ws, rank, n, capacity, seed, 8, 7, 25000, 10000) ## i64
  return nil if loaded != rank
  out

-> ffmw_debt_state(path, n, debt, nonce)
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source, path, n, capacity, 31001 + nonce * 97, 8, 7, 25000, 10000) ## i64
  return nil if rank < 1
  source[10] = debt
  target = rank + debt ## i64
  attempts = 0 ## i64
  while source[6] < target && attempts < 128
    z = ffw_try_split(source) ## i64
    attempts += 1
  return nil if source[6] != target
  return nil if ffw_verify_current_exact(source, n) == 0
  ffmw_clone_current(source, 41011 + nonce * 193)

-> ffmw_features(st, debt, arm)
  rank = st[6] ## i64
  weight_sum = i64[3]
  weight_max = i64[3]
  singletons = i64[3]
  partner_pairs = i64[3]
  i = 0 ## i64
  while i < rank
    slot = st[st[50] + i] ## i64
    u = st[st[44] + slot] ## i64
    v = st[st[45] + slot] ## i64
    w = st[st[46] + slot] ## i64
    uw = ffw_popcount(u) ## i64
    vw = ffw_popcount(v) ## i64
    ww = ffw_popcount(w) ## i64
    weight_sum[0] += uw
    weight_sum[1] += vw
    weight_sum[2] += ww
    weight_max[0] = uw if uw > weight_max[0]
    weight_max[1] = vw if vw > weight_max[1]
    weight_max[2] = ww if ww > weight_max[2]
    singletons[0] += 1 if uw == 1
    singletons[1] += 1 if vw == 1
    singletons[2] += 1 if ww == 1
    j = i + 1 ## i64
    while j < rank
      other = st[st[50] + j] ## i64
      partner_pairs[0] += 1 if st[st[44] + other] == u
      partner_pairs[1] += 1 if st[st[45] + other] == v
      partner_pairs[2] += 1 if st[st[46] + other] == w
      j += 1
    i += 1
  pressure_sum = 0 ## i64
  pressure_max = 0 ## i64
  samples = rank ## i64
  samples = 8 if samples > 8
  i = 0
  while i < samples
    slot = st[st[50] + i]
    pressure = ffw_pressure(st, st[st[44] + slot], st[st[45] + slot], st[st[46] + slot]) ## i64
    pressure_sum += pressure
    pressure_max = pressure if pressure > pressure_max
    i += 1
  [
    st[2], debt, rank, st[36],
    weight_sum[0], weight_sum[1], weight_sum[2],
    weight_max[0], weight_max[1], weight_max[2],
    singletons[0], singletons[1], singletons[2],
    partner_pairs[0], partner_pairs[1], partner_pairs[2],
    pressure_sum, pressure_max, arm
  ]

-> ffmw_run_arm(base, arm, budget, seed)
  state = ffmw_clone_current(base, seed)
  return 0 if state == nil
  start_rank = state[7] ## i64
  if arm == 0
    z = ffw_work(state, budget) ## i64
  if arm == 1
    z = ffw_wander(state, budget) ## i64
  controls = i64[7]
  controls[0] = 2000
  controls[1] = 6
  controls[2] = 300000
  controls[3] = 1
  controls[4] = 8
  controls[5] = 2
  controls[6] = 24
  if arm == 2
    z = ffw_walk_tuned(state, budget, controls)
  if arm == 3
    z = ffw_walk_axis_sweep_tuned(state, budget, controls)
  state[7] < start_rank ? 1 : 0

-> ffmw_append_shape(path, n, variants, budget, train_x, train_y, valid_x, valid_y, test_x, test_y)
  created = 0 ## i64
  variant = 0 ## i64
  while variant < variants
    debt = 1 + (variant % 2) ## i64
    base = ffmw_debt_state(path, n, debt, variant)
    if base != nil
      bucket = variant % 10 ## i64
      arm = 0 ## i64
      while arm < 4
        features = ffmw_features(base, debt, arm)
        label = ffmw_run_arm(base, arm, budget, 51001 + n * 100003 + variant * 257) ## i64
        if bucket < 6
          train_x.push(features)
          train_y.push(label)
        elsif bucket < 8
          valid_x.push(features)
          valid_y.push(label)
        else
          test_x.push(features)
          test_y.push(label)
        arm += 1
      created += 1
    variant += 1
  created

-> ffmw_weights(labels)
  positives = 0
  labels.each -> (label)
    positives += label
  negatives = labels.size - positives
  positive_weight = 1.to_f
  positive_weight = negatives.to_f / positives.to_f if positives > 0
  positive_weight = 8.to_f if positive_weight > 8.to_f
  out = []
  labels.each -> (label)
    out.push(label == 1 ? positive_weight : 1.to_f)
  out

-> ffmw_arm_rates(name, x, y)
  success = i64[4]
  total = i64[4]
  i = 0 ## i64
  while i < y.size
    arm = x[i][18] ## i64
    total[arm] += 1
    success[arm] += y[i]
    i += 1
  << "CPU_WINDOW_ARMS split=" + name + " success=" + success[0].to_s + "/" + success[1].to_s + "/" + success[2].to_s + "/" + success[3].to_s + " total=" + total[0].to_s + "/" + total[1].to_s + "/" + total[2].to_s + "/" + total[3].to_s
  best = 0 ## i64
  arm = 1 ## i64
  while arm < 4
    if success[arm] * total[best] > success[best] * total[arm]
      best = arm
    arm += 1
  best

-> ffmw_policy_report(name, model, x, y, fixed_arm)
  probabilities = model.predict_proba(x, 1)
  selected_hits = 0 ## i64
  fixed_hits = 0 ## i64
  oracle_hits = 0 ## i64
  groups = y.size / 4 ## i64
  g = 0 ## i64
  while g < groups
    base = g * 4 ## i64
    selected = 0 ## i64
    arm = 1 ## i64
    while arm < 4
      selected = arm if probabilities[base + arm] > probabilities[base + selected]
      arm += 1
    selected_hits += y[base + selected]
    fixed_hits += y[base + fixed_arm]
    any = 0 ## i64
    arm = 0
    while arm < 4
      any = 1 if y[base + arm] == 1
      arm += 1
    oracle_hits += any
    g += 1
  coverage = selected_hits.to_f / groups.to_f
  << "CPU_WINDOW_POLICY model=" + name + " groups=" + groups.to_s + " selected=" + selected_hits.to_s + " fixed=" + fixed_hits.to_s + " oracle=" + oracle_hits.to_s + " coverage=" + coverage.to_s

-> ffmw_importances(name, values)
  order = []
  i = 0 ## i64
  while i < values.size
    order.push(i)
    slot = order.size - 1
    while slot > 0 && values[order[slot]] > values[order[slot - 1]]
      tmp = order[slot - 1]
      order[slot - 1] = order[slot]
      order[slot] = tmp
      slot -= 1
    i += 1
  i = 0
  while i < 8
    feature = order[i] ## i64
    << "CPU_WINDOW_IMPORTANCE model=" + name + " rank=" + (i + 1).to_s + " feature=" + CPU_WINDOW_FEATURES[feature].to_s + " value=" + values[feature].to_s
    i += 1

-> ffmw_arm_subset(x, y, wanted)
  out_x = []
  out_y = []
  i = 0 ## i64
  while i < y.size
    if x[i][18] == wanted
      out_x.push(x[i])
      out_y.push(y[i])
    i += 1
  { x: out_x, y: out_y }

-> ffmw_shape_subset(x, y, wanted_n)
  out_x = []
  out_y = []
  i = 0 ## i64
  while i < y.size
    if x[i][0] == wanted_n
      out_x.push(x[i])
      out_y.push(y[i])
    i += 1
  { x: out_x, y: out_y }

-> ffmw_ranking_report(name, model, x, y)
  probabilities = model.predict_proba(x, 1)
  order = []
  i = 0 ## i64
  while i < y.size
    order.push(i)
    slot = order.size - 1
    while slot > 0 && probabilities[order[slot]] > probabilities[order[slot - 1]]
      tmp = order[slot - 1]
      order[slot - 1] = order[slot]
      order[slot] = tmp
      slot -= 1
    i += 1
  total_hits = 0 ## i64
  y.each -> (label)
    total_hits += label
  quarter = y.size / 4 ## i64
  quarter = 1 if quarter < 1
  half = y.size / 2 ## i64
  half = 1 if half < 1
  quarter_hits = 0 ## i64
  half_hits = 0 ## i64
  i = 0
  while i < half
    half_hits += y[order[i]]
    quarter_hits += y[order[i]] if i < quarter
    i += 1
  << "CPU_WINDOW_RANKING model=" + name + " rows=" + y.size.to_s + " positives=" + total_hits.to_s + " top_quarter=" + quarter_hits.to_s + "/" + quarter.to_s + " top_half=" + half_hits.to_s + "/" + half.to_s

args = argv()
root = args.size > 0 ? args[0] : "bits/tungsten-metaflip/lib/metaflip/seeds/gf2"
variants = args.size > 1 ? args[1].to_i : 60
# This is deliberately a short-horizon value model. At very large budgets all
# planted debts close and the labels collapse to one class, which is neither a
# useful selector task nor representative of a scarce specialist lane.
budget = args.size > 2 ? args[2].to_i : 25
train_x = []
train_y = []
valid_x = []
valid_y = []
test_x = []
test_y = []
created = 0 ## i64
created += ffmw_append_shape(root + "/matmul_3x3_rank23_d139_gf2.txt", 3, variants, budget, train_x, train_y, valid_x, valid_y, test_x, test_y)
created += ffmw_append_shape(root + "/matmul_5x5_rank93_d967_four_split_control_gf2.txt", 5, variants, budget, train_x, train_y, valid_x, valid_y, test_x, test_y)
created += ffmw_append_shape(root + "/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, variants, budget, train_x, train_y, valid_x, valid_y, test_x, test_y)
created += ffmw_append_shape(root + "/matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt", 7, variants, budget, train_x, train_y, valid_x, valid_y, test_x, test_y)

<< "CPU_WINDOW_DATA states=" + created.to_s + " train=" + train_y.size.to_s + " valid=" + valid_y.size.to_s + " test=" + test_y.size.to_s + " budget=" + budget.to_s
fixed_arm = ffmw_arm_rates("train", train_x, train_y) ## i64
z = ffmw_arm_rates("valid", valid_x, valid_y) ## i64
z = ffmw_arm_rates("test", test_x, test_y) ## i64
weights = ffmw_weights(train_y)

tree = DecisionTreeClassifier.new(6, 8, 4, :gini)
tree.fit(train_x, train_y, weights)
ffmw_policy_report("tree", tree, test_x, test_y, fixed_arm)
ffmw_importances("tree", tree.feature_importances)

forest = RandomForestClassifier.new(40, :sqrt, 7, 4, 71003)
forest.fit(train_x, train_y, weights)
ffmw_policy_report("forest", forest, test_x, test_y, fixed_arm)
ffmw_importances("forest", forest.feature_importances)

boost = GradientBoostingClassifier.new(40, 1.to_f / 10.to_f, 2, 4)
boost.fit(train_x, train_y, weights)
ffmw_policy_report("boost", boost, test_x, test_y, fixed_arm)

# Axis-sweep wins the planted-debt arm race often enough that the more useful
# ML question is which basins deserve that scarce lane. Train an arm-constant
# value model and measure enrichment among its top-ranked held-out states.
axis_train = ffmw_arm_subset(train_x, train_y, 3)
axis_test = ffmw_arm_subset(test_x, test_y, 3)
axis_weights = ffmw_weights(axis_train[:y])
axis_forest = RandomForestClassifier.new(48, :sqrt, 7, 3, 72007)
axis_forest.fit(axis_train[:x], axis_train[:y], axis_weights)
ffmw_ranking_report("axis-forest", axis_forest, axis_test[:x], axis_test[:y])
ffmw_importances("axis-forest", axis_forest.feature_importances)
axis_boost = GradientBoostingClassifier.new(48, 1.to_f / 10.to_f, 2, 3)
axis_boost.fit(axis_train[:x], axis_train[:y], axis_weights)
ffmw_ranking_report("axis-boost", axis_boost, axis_test[:x], axis_test[:y])
[3, 5, 6, 7].each -> (shape_n)
  shape_train = ffmw_shape_subset(axis_train[:x], axis_train[:y], shape_n)
  one_shape = ffmw_shape_subset(axis_test[:x], axis_test[:y], shape_n)
  ffmw_ranking_report("axis-forest-n" + shape_n.to_s, axis_forest, one_shape[:x], one_shape[:y])
  ffmw_ranking_report("axis-boost-n" + shape_n.to_s, axis_boost, one_shape[:x], one_shape[:y])
  shape_weights = ffmw_weights(shape_train[:y])
  shape_forest = RandomForestClassifier.new(48, :sqrt, 7, 3, 73009 + shape_n)
  shape_forest.fit(shape_train[:x], shape_train[:y], shape_weights)
  ffmw_ranking_report("shape-forest-n" + shape_n.to_s, shape_forest, one_shape[:x], one_shape[:y])
  shape_boost = GradientBoostingClassifier.new(48, 1.to_f / 10.to_f, 2, 3)
  shape_boost.fit(shape_train[:x], shape_train[:y], shape_weights)
  ffmw_ranking_report("shape-boost-n" + shape_n.to_s, shape_boost, one_shape[:x], one_shape[:y])
