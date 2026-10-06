"""poolsum.py NAME: falls of every variant of scan NAME split into the development pool (seeds < 30000) and the fresh pool (>= 30000). Agent S6."""
import json, re, sys
name = sys.argv[1]
root = '/Users/erik/tungsten/bits/tungsten-robolab/out/sprint6/'
lab = re.findall(r"^\[(.*?)\] \[", open(root + f'scan_{name}.log').read(), flags=re.M)
for i, l in enumerate(lab, 1):
    try:
        rows = [json.loads(x) for x in open(root + f'scan_{name}_{i}.jsonl') if x.strip()]
    except FileNotFoundError:
        continue
    dev = [r for r in rows if r['seed'] < 30000]; fr = [r for r in rows if r['seed'] >= 30000]
    print('%-100s dev %3d/%-3d fresh %3d/%-3d total %3d/%d' % (l[:100], sum(r['fell'] for r in dev), len(dev), sum(r['fell'] for r in fr), len(fr), sum(r['fell'] for r in rows), len(rows)))
