"""bandsum.py NAME: falls of every variant of scan NAME split by COM0 class: deep (< -0.05) and marginal ([-0.05, -0.035)). Agent S6."""
import json, re, sys
name = sys.argv[1]
root = '/Users/erik/tungsten/bits/tungsten-robolab/out/sprint6/'
c = json.load(open(root + 'com0_all.json')); c.update(json.load(open(root + 'com0_v.json')))
lab = re.findall(r"^\[(.*?)\] \[", open(root + f'scan_{name}.log').read(), flags=re.M)
for i, l in enumerate(lab, 1):
    try:
        rows = [json.loads(x) for x in open(root + f'scan_{name}_{i}.jsonl') if x.strip()]
    except FileNotFoundError:
        continue
    deep = [r for r in rows if c[str(r['seed'])]['com'] < -0.05]; mar = [r for r in rows if c[str(r['seed'])]['com'] >= -0.05]
    d, m = sum(r['fell'] for r in deep), sum(r['fell'] for r in mar)
    print('%-92s deep %3d/%-3d  marginal %3d/%-3d  sum %3d' % (l.replace('rk_thr=-0.035,rk_sr_t0=0.0,rk_ln_to=0.6,rk_st_hold=0.3,', '')[:92], d, len(deep), m, len(mar), d + m))
