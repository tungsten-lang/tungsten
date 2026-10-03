"""Official-like harness metric from a ljx_robust --eval SUMMARY line: mean of max(score, 0) = legal fraction x mean of the legal scores. usage: clip.py "<SUMMARY line>" """
import re, sys
s = sys.argv[1]
m = re.search(r"SUMMARY (\d+) starts: valid (\d+), fouls/too close (\d+), legal\(score>0\) (\d+), score mean (-?[\d.]+) \(all\) / (-?[\d.]+) \(legal\)", s)
n, valid, fouls, legal, mean_all, mean_legal = int(m[1]), int(m[2]), int(m[3]), int(m[4]), float(m[5]), float(m[6])
print("n %d legal %d (%.1f%%) clipped mean %.3f (score mean %.3f, legal mean %.3f)" % (n, legal, 100.0 * legal / n, legal * mean_legal / n, mean_all, mean_legal))
