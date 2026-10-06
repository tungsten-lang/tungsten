"""bands.py SCAN IDX... : falls by COM0 band for the given scan result files (scan6 output indices), against the deepA_1 baseline (F1). Agent S6."""
import json, sys
c = json.load(open('out/sprint6/com0_all.json'))
def read(p): return {json.loads(l)['seed']: json.loads(l) for l in open(p) if l.strip()}
base = read('out/sprint6/scan_deepA_1.jsonl')
files = sys.argv[1:]
bins = [-0.12, -0.08, -0.07, -0.065, -0.06, -0.055, -0.0525, -0.05]
rows = [read(f) for f in files]
print('band            n   F1 ' + ' '.join('%6s' % ('v%d' % i) for i in range(len(files))))
for lo, hi in zip(bins, bins[1:]):
    seeds = [s for s in base if lo <= c[str(s)]['com'] < hi]
    print('[%+.4f,%+.4f) %3d  %3d ' % (lo, hi, len(seeds), sum(1 for s in seeds if base[s]['fell'])) + ' '.join('%6d' % sum(1 for s in seeds if r[s]['fell']) for r in rows))
print('total %3d  %3d ' % (len(base), sum(1 for s in base if base[s]['fell'])) + ' '.join('%6d' % sum(1 for s in r if r[s]['fell']) for r in rows))
