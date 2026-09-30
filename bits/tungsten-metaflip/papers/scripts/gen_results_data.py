#!/usr/bin/env python3
"""Generate the data files and the appendix table of the results paper from the release index.

usage: gen_results_data.py RECORDS_TSV PAPER_DATA_DIR OUT_DIR
  RECORDS_TSV   records.tsv of the campaign-records asset (795 rows)
  PAPER_DATA_DIR  directory of figure TSVs computed by the statistics script; also holds prior_art_flags.tsv
                (scripts/prior_art_flags.py: one prior-art flag per record from the 2026-09-29 audit)
  OUT_DIR       papers/results

Provenance corrections applied on top of the archive's index (records.tsv labels four rows
"live fleet checkpoint"; the tensors it indexes say otherwise):
  9x9x9   the indexed tensor is a 40M-move walk from Perminov's rank-486 scheme (asset D, kind walk)
  13x13x13 the indexed tensor is the July block-composition certificate (kind archived)
  7x7x7, 15x15x15 stay 'live fleet' (constructive rank 247; fleet reduction of a July rank-2008 composition)
"""
import csv, collections, shutil, sys
from pathlib import Path

records_tsv, pdata, out = map(Path, sys.argv[1:4])
rows = list(csv.DictReader(open(records_tsv), delimiter='\t'))
assert len(rows) == 795

CODE = {
    'closure product': 'C', 'closure product -> projection': 'CP', 'closure product -> walk': 'CW',
    'closure product -> projection -> walk': 'CPW',
    'July certificate': 'J', 'July certificate -> projection': 'JP', 'July certificate -> projection -> walk': 'JPW',
    'committed certificate': 'K', 'committed certificate -> projection': 'KP',
    'committed certificate -> projection -> walk': 'KPW',
    'matmulcatalog replay': 'M', 'matmulcatalog replay -> walk': 'MW', 'matmulcatalog replay -> projection': 'MP',
    'matmulcatalog replay -> projection -> walk': 'MPW',
    'public seed -> walk': 'S', 'live fleet checkpoint': 'F',
}
CORRECT = {'9x9x9': 'public seed -> walk', '13x13x13': 'July certificate'}
for r in rows:
    r['family'] = CORRECT.get(r['shape'], r['chain'])
    r['code'] = CODE[r['family']]
    r['dims'] = tuple(map(int, r['shape'].split('x')))
rows.sort(key=lambda r: (r['dims'][2], r['dims'][1], r['dims'][0]))       # by largest side, then middle, then smallest
flags = {r['shape']: r for r in csv.DictReader(open(pdata / 'prior_art_flags.tsv'), delimiter='\t')}
assert set(flags) == {r['shape'] for r in rows}
for r in rows:
    r['prior_art'] = flags[r['shape']]['flag']                            # S1 S2 M1 M2 Q none

(out / 'data').mkdir(exist_ok=True); (out / 'tables').mkdir(exist_ok=True)
with open(out / 'data' / 'records.tsv', 'w', newline='') as fh:
    w = csv.writer(fh, delimiter='\t')
    w.writerow(['shape', 'rank', 'class', 'best_listed_any_ring', 'best_listed_gf2_valid', 'family', 'code', 'prior_art'])
    for r in rows:
        w.writerow([r['shape'], r['rank'], r['class'], r['best_listed_any_ring'], r['best_listed_gf2_valid'], r['family'], r['code'], r['prior_art']])

# family table (corrected)
fam = collections.Counter(r['family'] for r in rows)
with open(out / 'data' / 'family_counts.tsv', 'w') as fh:
    fh.write('family\tcode\trecords\n')
    for f, n in fam.most_common():
        fh.write(f'{f}\t{CODE[f]}\t{n}\n')

# scatter data: relative margin (percent of the class-defining listed rank) against volume
search = lambda code: code not in ('C', 'J', 'K', 'M', 'F')
with open(out / 'data' / 'scatter_nosearch.dat', 'w') as a, open(out / 'data' / 'scatter_search.dat', 'w') as b:
    for f in (a, b):
        f.write('volume relmargin\n')
    for r in rows:
        n, m, p = r['dims']; rank = int(r['rank'])
        listed = int(r['best_listed_any_ring']) if r['class'] == 'below_all' else int(r['best_listed_gf2_valid'])
        rel = 100.0 * (listed - rank) / listed
        (b if search(r['code']) else a).write(f'{n*m*p} {rel:.4f}\n')

# two-up appendix table
def cell(r):
    n, m, p = r['dims']
    any_ = r['best_listed_any_ring']; f2 = r['best_listed_gf2_valid'] or '--'
    sup = ('\\dagger' if r['class'] == 'gf2_valid_only' else '') + {'S1': '\\mathrm{S}', 'S2': '\\mathrm{S}', 'M1': '\\mathrm{M}', 'M2': '\\mathrm{M}', 'Q': '\\mathrm{Q}'}.get(r['prior_art'], '')
    mark = r['code'] + (f'$^{{{sup}}}$' if sup else '')
    return f'${n}{{\\times}}{m}{{\\times}}{p}$ & {r["rank"]} & {any_} & {f2} & {mark}'

half = (len(rows) + 1) // 2
lines = []
for i in range(half):
    left = cell(rows[i]); right = cell(rows[i + half]) if i + half < len(rows) else ' & & & & '
    lines.append(f'{left} & {right}\\\\')
head = ('\\begingroup\\scriptsize\\setlength{\\tabcolsep}{3.2pt}\n'
        '\\begin{longtable}{@{}lrrrl@{\\hspace{6mm}}lrrrl@{}}\n'
        '\\caption{All 795 records of 2026-09-29, ordered by largest, middle and smallest side (the right column continues the left). Columns: format (sorted), our rank, best listed rank in any ring, best listed GF(2)-valid rank (-- if none), family code (Appendix~\\ref{app:families}). Superscripts: $\\dagger$ below the GF(2)-valid bar only; S superseded and M matched by published constructions or claims, Q a lower rational claim exists (\\cref{sec:persistence}); no letter: no prior art found.}\\label{tab:all}\\\\\n'
        '\\toprule format & rank & any & F$_2$ & fam. & format & rank & any & F$_2$ & fam.\\\\\\midrule\\endfirsthead\n'
        '\\toprule format & rank & any & F$_2$ & fam. & format & rank & any & F$_2$ & fam.\\\\\\midrule\\endhead\n'
        '\\bottomrule\\endlastfoot\n')
(out / 'tables' / 'appendix_records.tex').write_text(head + '\n'.join(lines) + '\n\\end{longtable}\\endgroup\n')

shutil.copy(pdata / 'prior_art_flags.tsv', out / 'data' / 'prior_art_flags.tsv')
for name in ('margin_hist_log2.tsv', 'records_by_maxside.tsv'):
    shutil.copy(pdata / name, out / 'data' / name)
print('rows', len(rows), 'families', dict(fam))

# ---- family tables -------------------------------------------------------------------------
import statistics
new_flag = {}
for line in list(csv.DictReader(open(pdata / 'scatter_volume_margin.tsv'), delimiter='\t')):
    new_flag[line['shape']] = line['new_on_2026_09_29'] == 'yes'
NAME = {
 'C': 'closure product (block sums and Kronecker products of exact schemes)',
 'CP': 'closure product, then projected', 'CW': 'closure product, then walked',
 'CPW': 'closure product, projected and walked (in several rounds)',
 'J': 'July 2026 block-composition certificate', 'JP': 'July certificate, projected',
 'JPW': 'July certificate, projected and walked',
 'K': 'certificate committed 2026-09-22 to 09-26', 'KP': 'committed certificate, projected',
 'KPW': 'committed certificate, projected and walked',
 'M': 'matmulcatalog recipe replayed over $\\F$', 'MW': 'replayed recipe, then walked',
 'MP': 'replayed recipe, then projected', 'MPW': 'replayed recipe, projected and walked',
 'S': 'public integer scheme reduced mod 2, then walked', 'F': 'live-fleet construction/checkpoint'}
ORDER = ['C', 'J', 'K', 'CPW', 'MW', 'JP', 'M', 'KPW', 'JPW', 'CP', 'MPW', 'CW', 'KP', 'S', 'F', 'MP']
by = collections.defaultdict(list)
for r in rows:
    by[r['code']].append(r)
def saving(r):
    listed = int(r['best_listed_any_ring']) if r['class'] == 'below_all' else int(r['best_listed_gf2_valid'])
    return listed - int(r['rank']), 100.0 * (listed - int(r['rank'])) / listed
lines = []
for code in ORDER:
    rs = by[code]
    sv = [saving(r) for r in rs]
    new = sum(new_flag[r['shape']] for r in rs)
    lines.append(f'{NAME[code]} & {code} & {len(rs)} & {new} & {statistics.median(x for x, _ in sv):g} & {statistics.median(y for _, y in sv):.2f}\\\\')
tot = [saving(r) for r in rows]
lines.append('\\midrule')
lines.append(f'all & & {len(rows)} & {sum(new_flag[r["shape"]] for r in rows)} & {statistics.median(x for x, _ in tot):g} & {statistics.median(y for _, y in tot):.2f}\\\\')
# the last row's terminator stays in the including file: a \\ at the very end of an \input'ed file
# makes LaTeX read \bottomrule while still looking ahead for an optional argument (Misplaced \noalign)
assert lines[-1].endswith('\\\\')
lines[-1] = lines[-1][:-2]
(out / 'tables' / 'family_margins.tex').write_text('\n'.join(lines) + '\n')
# appendix A: code table (same rows, without margins)
al = [f'{code} & {NAME[code]} & {len(by[code])}\\\\' for code in ORDER]
(out / 'tables' / 'families.tex').write_text(
  '\\begin{tabular}{@{}llr@{}}\\toprule code & lineage of the recorded tensor & records\\\\\\midrule\n' + '\n'.join(al) + '\n\\bottomrule\\end{tabular}\n')
print({c: len(by[c]) for c in ORDER})

# prior-art breakdown by lineage family (persistence section): records / superseded / matched / remaining
pa = collections.defaultdict(lambda: [0, 0, 0, 0])
for r in rows:
    c = pa[r['code']]
    c[0] += 1
    c[1] += r['prior_art'] in ('S1', 'S2')
    c[2] += r['prior_art'] in ('M1', 'M2')
    c[3] += r['prior_art'] in ('none', 'Q')
body = [f'{NAME[code]} & {code} & {pa[code][0]} & {pa[code][1]} & {pa[code][2]} & {pa[code][3]}\\\\' for code in ORDER]
tot = [sum(pa[c][i] for c in ORDER) for i in range(4)]
assert tot == [795, 87, 112, 596], tot
body += ['\\midrule', f'all & & {tot[0]} & {tot[1]} & {tot[2]} & {tot[3]}\\\\']
(out / 'tables' / 'prior_art_by_family.tex').write_text(
    '\\begin{tabular}{@{}p{7.2cm}lrrrr@{}}\\toprule\nlineage of the recorded tensor & code & records & superseded & matched & remaining\\\\\\midrule\n'
    + '\n'.join(body) + '\n\\bottomrule\\end{tabular}\n')
print('prior art by family:', {c: pa[c] for c in ORDER})
