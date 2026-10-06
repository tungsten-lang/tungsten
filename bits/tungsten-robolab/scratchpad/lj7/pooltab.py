"""pooltab (L7): P(best of k legal marks > T), exact, pooled over json files; usage: pooltab.py label file1.json [file2.json ...]"""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj6")
import numpy as np
import bo6
label, files = sys.argv[1], sys.argv[2:]
seeds, marks, rows = bo6.load(files)
print("== %s: n %d starts, legal %.1f %%, per-attempt P(>8.95) %.1f %%, mean mark %.3f (LABELLED beyond-human body, unlimited run-up)" % (label, len(marks), 100 * (marks > 0).mean(), 100 * (marks > 8.95).mean(), marks.mean()))
print("| T \\ k | " + " | ".join(str(k) for k in range(1, 7)) + " |")
for T in (8.50, 8.75, 8.95, 9.20, 9.50):
    print("| %.2f | " % T + " | ".join("%.1f %%" % (100 * bo6.compete_exact(marks, T, k)["p_gt"]) for k in range(1, 7)) + " |")
bs = bo6.bootstrap(marks, 8.95, 6, 2000)
print("best of six > 8.95: %.1f %% exact, bootstrap 95 %% [%.1f, %.1f]" % (100 * bo6.compete_exact(marks, 8.95, 6)["p_gt"], 100 * bs["p6"][0], 100 * bs["p6"][1]))
