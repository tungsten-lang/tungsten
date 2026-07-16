# Standalone sector-suture sweep driver (move 8).
#
# Usage: flipfleet_sector_suture_sweep <parentA> <parentB> <n> <m> <p>
# Runs the full (sector x mode x orientation) crossover sweep between two
# exact same-shape parents and reports the defect-rank histogram, gated
# children, rank wins, and off-dictionary equal-rank ties -- the two
# payoff modes.  Grep-able: SECTOR_SUTURE_SWEEP line.

use flipfleet_sector_suture

args = argv()
if args.size() < 5
  << "usage: flipfleet_sector_suture_sweep <parentA> <parentB> <n> <m> <p>"
  exit(2)
pa = args[0]
pb = args[1]
n = args[2].to_i() ## i64
m = args[3].to_i() ## i64
p = args[4].to_i() ## i64
if n < 2 || m < 2 || p < 2
  << "usage: flipfleet_sector_suture_sweep <parentA> <parentB> <n> <m> <p>"
  exit(2)

hist = i64[5]
counters = i64[16]
wins = ffss_sweep(pa, pb, n, m, p, "", hist, counters) ## i64
if wins < 0
  << "SECTOR_SUTURE_SWEEP_ERROR code=" + wins.to_s()
  exit(2)
<< "SECTOR_SUTURE_SWEEP pair=" + pa + " x " + pb + " attempts=" + counters[0].to_s() + " gated=" + counters[2].to_s() + " abstain=" + counters[11].to_s() + " h0=" + hist[0].to_s() + " h1=" + hist[1].to_s() + " h2=" + hist[2].to_s() + " h3=" + hist[3].to_s() + " wins=" + counters[4].to_s() + " offdict_equal=" + counters[5].to_s() + " ms=" + counters[15].to_s()
