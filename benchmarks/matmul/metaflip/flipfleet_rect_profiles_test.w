use flipfleet_rect_profiles

-> ffrpt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

labels = ["3x3x4", "3x3x5", "3x4x4", "3x4x5", "3x4x6", "3x5x5", "4x4x5", "4x5x5", "4x4x6", "4x5x6", "4x5x7"]
records = i64[11]
records[0] = 29
records[1] = 36
records[2] = 38
records[3] = 47
records[4] = 54
records[5] = 58
records[6] = 60
records[7] = 76
records[8] = 73
records[9] = 90
records[10] = 104
i = 0 ## i64
while i < labels.size()
  label = labels[i]
  n = ffrp_n(label) ## i64
  m = ffrp_m(label) ## i64
  p = ffrp_p(label) ## i64
  z = ffrpt_expect(label + " supported", ffrp_supported(n, m, p) == 1)
  z = ffrpt_expect(label + " round-trip", ffrp_label(n, m, p) == label)
  z = ffrpt_expect(label + " record", ffrp_record_rank(n, m, p) == records[i])
  z = ffrpt_expect(label + " target", ffrp_target_rank(n, m, p) == records[i] - 1)
  seed = ffrp_seed_rel(n, m, p)
  z = ffrpt_expect(label + " seed shape", seed.include?("matmul_" + label + "_rank" + records[i].to_s()))
  z = ffrpt_expect(label + " seed field", seed.ends_with?("_gf2.txt"))
  if label == "4x5x7"
    z = ffrpt_expect("457 density leader default", seed.ends_with?("matmul_4x5x7_rank104_d1160_gf2.txt"))
  if label == "3x3x5"
    z = ffrpt_expect("335 density leader default", seed.ends_with?("matmul_3x3x5_rank36_d287_gf2.txt"))
  i += 1

z = ffrpt_expect("invalid label", ffrp_supported_label("4x5") == 0 && ffrp_n("4x5") == 0)
z = ffrpt_expect("invalid shape", ffrp_supported(5, 5, 6) == 0 && ffrp_label(5, 5, 6) == "invalid")
z = ffrpt_expect("GPU profile boundary", ffrp_gpu_cap(3, 3, 5) == 77 && ffrp_gpu_cap(3, 4, 5) == 92 && ffrp_gpu_cap(3, 4, 6) == 0 && ffrp_gpu_cap(3, 5, 5) == 107 && ffrp_gpu_cap(4, 4, 5) == 112 && ffrp_gpu_cap(4, 5, 5) == 0 && ffrp_gpu_cap(4, 4, 6) == 0 && ffrp_gpu_cap(4, 5, 6) == 0 && ffrp_gpu_cap(4, 5, 7) == 0)

budgets = i64[3]
z = ffrpt_expect("100M campaign budget", ffrp_campaign_budgets(100000000, budgets) == 100000000)
z = ffrpt_expect("focused work budget", budgets[0] == 10000000)
z = ffrpt_expect("adaptive budget", budgets[1] == 70000000)
z = ffrpt_expect("guaranteed wander budget", budgets[2] == 20000000)
z = ffrpt_expect("campaign budget sum", budgets[0] + budgets[1] + budgets[2] == 100000000)
z = ffrpt_expect("zone quotas", ffrp_work_quota(100000000) == 10000000 && ffrp_wander_quota(100000000) == 4000000)
z = ffrpt_expect("tiny campaign remains bounded", ffrp_campaign_budgets(1, budgets) == 1 && budgets[0] + budgets[1] + budgets[2] == 1)

<< "PASS flipfleet rectangular profiles"
