# Checking j3037_9_rggt_bm1

The scheduling verifier and event generator are in `verified58/`. Supply the original 58-slot DIMACS as `verified58/input.cnf` and PSPLIB j3037_9.mm as `verified58/job.mm`. The verifier authenticates the DIMACS with SHA-256. Extract the event traces from the local `build/sc2026-j3037/verified58.tar.gz` bundle into `verified58/traces/`, or regenerate each branch using the modes in `cases.json` and the command in `generator/README.md`. Run `python3 verify.py` from that directory. A complete replay verifies the 59-slot schedule and the scheduling refutation at 58.

The separate competition certificates cover restricted branches. Their replay programs, clause translator and budget counter are in `competition/`. Each proof archive listed in the scheduling report contains the required child proofs and its replay instructions. For example, after extracting `tail2-second8-58.tar`, run `python3 replay_second8.py --cake /path/to/cake_pb_cnf` there. The expected results are a guarded exclusion on the original and UNSAT on the restricted input. The multi-gigabyte child proofs remain in the local build archives.

## Remaining start pairs

From a scratch directory, run the following with the two original inputs in place. Python with NumPy and a C++17 compiler are required. Set `frontier` to the absolute path of the `frontier` directory here.

```sh
python3 "$frontier/pair_prices.py"
python3 "$frontier/interface.py" 10 19
python3 "$frontier/interface_data.py" 10 19
c++ -O2 -std=c++17 "$frontier/interface_filter.cpp" -o interface_filter
./interface_filter interface-10-19.dat interface-10-19.states 19 > survivors
```

Each state fixes which jobs have finished when job 8 runs and selects a mode for each simultaneous job. The filter applies precedences, mandatory renewable loads and the project budgets. Its survivors are necessary conditions for a schedule. The earliest start pair has 5,265 states, with 2,290 surviving. At the opposite pair, 17 and 28, all 9,054 survive. Across all 52 pairs none of the 13 integer price profiles produces a contradiction, even after restricting the slot capacities and mode placements to the start pair.
