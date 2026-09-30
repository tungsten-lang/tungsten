"""What would composing with EVERYTHING public (and our own witnesses) give, over ALL formats, against the four tables?
Rank-only estimate: direct sums, Kronecker products and Strassen on unequal 2x2x2 splits (the operations of the audit's
08-composition-closure.py) over base tables L0 (scored tables, GF(2)-valid), L1 (+ FMM schemes/known), L2 (+ GF(2)-valid rank
claims of papers), U (L2 + our own scoreboard witnesses, which include the July/committed block-recombination certificates)."""
import csv, importlib.util, json, sys, collections
from pathlib import Path
from types import SimpleNamespace
W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
TOOLS = '/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools'
sys.path.insert(0, TOOLS)
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('cc', W / 'paper-notes/08-composition-closure.py')
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
grb = cc.grb
l0, known, heads = cc.public_gf2()
l1 = dict(l0)
for k, (r, labels) in known.items():
    for lab in labels:
        cc.offer(l1, k, r, lab)
lit = cc.literature_gf2()
l2 = dict(l1)
for k, (r, labels) in lit.items():
    for lab in labels:
        cc.offer(l2, k, r, lab)
# bars of the four tables at the latest heads (as the audit's re-score)
EXT = cc.EXTRACTED
mmc = EXT / f"mmc_catalog_{heads['mmc'][:12]}.json"
args = SimpleNamespace(lille=str(EXT / f"fmm_sota_{heads['lille'][:12]}.json"), matmulcatalog=str(mmc), fmm_repo=str(cc.LATEST / 'fmm'),
                       fmm_revision=heads['fmm'], extra_repo=[str(cc.LATEST / 'fmm-schemes')])
lille, any_ring, gf2 = grb.public_tables(args)
# our scoreboard
board = {tuple(map(int, r['shape'].split('x'))): r for r in json.load(open(W / 'board_final.json'))}
ours = {k: v['rank'] for k, v in board.items()}
u = {k: (r, ['table/lit']) for k, (r, _) in l2.items()}
for k, r in ours.items():
    if k not in u or r < u[k][0]:
        u[k] = (r, ['ours'])
res = {}
for name, base in (('L0', l0), ('L1', l1), ('L2', l2), ('U', u)):
    res[name] = {k: v[0] for k, v in cc.closure(base, strassen=True).items()}
    print(name, 'closure done', flush=True)
shapes = sorted(k for k in any_ring if k[0] >= 2 and max(k) <= 32)
assert len(shapes) == 5456, len(shapes)
def klass(rank, k):
    ba, bf = any_ring.get(k), gf2.get(k)
    if ba is not None and rank < ba: return 'below_all'
    if bf is not None and rank < bf: return 'gf2_valid_only'
    if ba is not None and rank == ba: return 'tie'
    return 'above'
out = {}
recs = {tuple(map(int, r['shape'].split('x'))): r for r in csv.DictReader(open(W / 'release-0929/gf2-campaign-records/records.tsv'), delimiter='\t')}
print('shapes', len(shapes), 'our records', len(recs))
for name in ('ours', 'L0', 'L1', 'L2', 'U'):
    cnt = collections.Counter()
    for k in shapes:
        r = ours.get(k) if name == 'ours' else res[name][k]
        if r is None: cnt['no_witness'] += 1; continue
        cnt[klass(r, k)] += 1
    print(name, dict(cnt), 'records', cnt['below_all'] + cnt['gf2_valid_only'])
    out[name] = dict(cnt)
# relation to our 795
for name in ('L0', 'L1', 'L2', 'U'):
    rec_new = beat_ours = same = 0
    for k in shapes:
        r = res[name][k]
        c = klass(r, k)
        if c in ('below_all', 'gf2_valid_only'):
            if k in recs:
                if r < int(recs[k]['rank']): beat_ours += 1
                elif r == int(recs[k]['rank']): same += 1
            else:
                rec_new += 1
    print(name, 'record-class shapes NOT among our 795:', rec_new, '| among our 795: beat ours', beat_ours, ', equal', same,
          ', worse', sum(1 for k in recs if res[name][k] > int(recs[k]['rank'])), '| our records the closure cannot reach:', sum(1 for k in recs if res[name][k] > int(recs[k]['rank'])))

import statistics
def saving(rank, k):
    ba, bf = any_ring.get(k), gf2.get(k)
    c = klass(rank, k)
    bar = ba if c == 'below_all' else bf
    return bar - rank, 100.0 * (bar - rank) / bar
for name in ('L1', 'L2', 'U'):
    new = [k for k in shapes if klass(res[name][k], k) in ('below_all', 'gf2_valid_only') and k not in recs]
    sv = [saving(res[name][k], k) for k in new]
    print(name, 'new record-class shapes', len(new), 'median saving terms', statistics.median(x for x, _ in sv) if sv else None,
          'median %', round(statistics.median(y for _, y in sv), 2) if sv else None, 'max', max((x for x, _ in sv), default=None))
    bysize = collections.Counter(('<=16' if max(k) <= 16 else '17-24' if max(k) <= 24 else '25-32') for k in new)
    print('   by largest side', dict(bysize), ' with a verified witness of ours:', sum(1 for k in new if k in ours), ' without:', sum(1 for k in new if k not in ours))
    top = sorted(new, key=lambda k: -saving(res[name][k], k)[0])[:6]
    print('   largest savings:', [('x'.join(map(str, k)), res[name][k], klass(res[name][k], k), saving(res[name][k], k)[0]) for k in top])
better = [k for k in recs if res['U'][k] < int(recs[k]['rank'])]
sv = [int(recs[k]['rank']) - res['U'][k] for k in better]
print('U beats ours on', len(better), 'of our 795; terms saved: median', statistics.median(sv), 'max', max(sv), 'total', sum(sv))
print('formats with a verified witness of ours that are NOT records but U is:', sum(1 for k in shapes if k in ours and k not in recs and klass(res['U'][k], k) in ('below_all', 'gf2_valid_only')))
json.dump({'x'.join(map(str, k)): {'L0': res['L0'][k], 'L1': res['L1'][k], 'L2': res['L2'][k], 'U': res['U'][k], 'any': any_ring.get(k), 'gf2': gf2.get(k), 'ours': ours.get(k)} for k in shapes},
          open('fullpool.json', 'w'))
print('done')
