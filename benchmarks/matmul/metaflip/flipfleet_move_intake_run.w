# Standalone driver for the twelve-lane move-intake runner.
#
# Usage: flipfleet_move_intake_run <state_path> <steps> <budget_class> <seed>
# Loads (or initializes) the accounting state, runs the requested number of
# rotation steps, and saves the state after every step so a crash never
# loses accounting.  budget_class 0 = smoke, 1 = occasional.

use flipfleet_move_intake

args = argv()
if args.size() < 4
  << "usage: flipfleet_move_intake_run <state_path> <steps> <budget_class> <seed>"
  exit(2)
state_path = args[0]
steps = args[1].to_i() ## i64
budget_class = args[2].to_i() ## i64
seed = args[3].to_i() ## i64
if steps < 1 || steps > 1000 || budget_class < 0 || budget_class > 1 || seed < 1
  << "usage: flipfleet_move_intake_run <state_path> <steps> <budget_class> <seed>"
  exit(2)

st = i64[ffmi_state_size()]
if ffmi_load(st, state_path) != 1
  z = ffmi_state_init(st)
  << "MOVE_INTAKE_RUN fresh state at " + state_path

step = 0 ## i64
while step < steps
  lane = ffmi_step(st, seed + step * 101, budget_class) ## i64
  if ffmi_save(st, state_path) != 1
    << "MOVE_INTAKE_RUN state save failed at step " + step.to_s()
    exit(1)
  step += 1

promoted = 0 ## i64
lane = 0 ## i64
while lane < 12
  if st[ffmi_lane_base(lane) + 5] == 1
    promoted += 1
  lane += 1
<< "MOVE_INTAKE_RUN_DONE steps=" + st[4].to_s() + " promoted_lanes=" + promoted.to_s() + " state=" + state_path
