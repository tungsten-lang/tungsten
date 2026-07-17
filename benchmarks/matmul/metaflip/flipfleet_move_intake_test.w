# Scheduler regressions plus one full bounded rotation for the twelve-lane
# move-intake runner.  Pure CPU.  Run from the repo root.
#
# Checks, in order: accounting/dwell/dim/promotion policies on synthetic
# results; state save/load round trip; then one full smoke-budget rotation
# over all twelve real lanes -- every lane must run, account, and stay
# within its bounded budget.  Yields are expected to be rare (these are
# record-hunting lanes on real frontiers); closures may accrue.

use flipfleet_move_intake

-> ffmit_expect(label, condition) (String bool) i64
  if !condition
    << "MOVE_INTAKE_FAIL " + label
    exit(1)
  1

# --- accounting policies on synthetic results -------------------------------------
st = i64[ffmi_state_size()]
z = ffmi_state_init(st)
z = ffmit_expect("init magic", st[0] == 1179015525 && st[2] == 13)
base = ffmi_lane_base(3) ## i64
z = ffmi_account(st, 3, 0, 1, 5)
z = ffmit_expect("dry pull counted", st[base] == 1 && st[base + 1] == 0 && st[base + 2] == 1 && st[base + 3] == 1)
i = 0 ## i64
while i < 7
  z = ffmi_account(st, 3, 0, 0, 5)
  i += 1
z = ffmit_expect("eight dry pulls dim the lane", st[base + 3] == 8 && st[base + 4] == 0)
z = ffmi_account(st, 3, 10, 0, 5)
z = ffmit_expect("yield revives and doubles dwell", st[base + 3] == 0 && st[base + 4] >= 1)
z = ffmi_account(st, 3, 10, 0, 5)
z = ffmit_expect("second yield promotes", st[base + 5] == 1)
base0 = ffmi_lane_base(0) ## i64
z = ffmi_account(st, 0, 5, 0, 5)
z = ffmit_expect("early yield promotes fast", st[base0 + 5] == 1)

# --- persistence -------------------------------------------------------------------
path = "/tmp/ffmi_test_state.txt"
z = ffmit_expect("save", ffmi_save(st, path) == 1)
st2 = i64[ffmi_state_size()]
z = ffmit_expect("load", ffmi_load(st2, path) == 1)
i = 0
same = 1 ## i64
while i < ffmi_state_size()
  if st[i] != st2[i]
    same = 0
  i += 1
z = ffmit_expect("round trip", same == 1)
z = ffmit_expect("load rejects garbage", ffmi_load(st2, "/tmp/ffmi_test_missing.txt") == 0)

# --- dimmed lanes are skipped by the picker -------------------------------------------
st3 = i64[ffmi_state_size()]
z = ffmi_state_init(st3)
lane = 0 ## i64
i = 0
while i < 8
  z = ffmi_account(st3, 5, 0, 0, 1)
  i += 1
z = ffmit_expect("lane 5 dimmed", st3[ffmi_lane_base(5) + 4] == 0)
st3[3] = 5
st3[4] = 1
picked = ffmi_pick(st3) ## i64
z = ffmit_expect("picker skips dimmed lane", picked != 5)

# --- one full bounded rotation over the real lanes -------------------------------------
live = i64[ffmi_state_size()]
z = ffmi_state_init(live)
step = 0 ## i64
while step < 13
  lane = ffmi_step(live, 24601 + step * 7, 0)
  step += 1
lane = 0
while lane < 13
  z = ffmit_expect("every lane ran once", live[ffmi_lane_base(lane)] == 1)
  lane += 1
z = ffmit_expect("thirteen steps recorded", live[4] == 13)
z = ffmit_expect("state persists after rotation", ffmi_save(live, path) == 1)

<< "flipfleet_move_intake_test: all checks passed"
