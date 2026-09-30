#!/usr/bin/env python3
"""Section C of 08-rescore-and-prior-art.md: one flag per record from the outputs of the other 08 scripts.

Inputs (JSON printed by the scripts, run on 2026-09-29):
  --rescore      08-rescore-latest.py
  --literature   08-literature-check.py --json
  --closure      08-composition-closure.py
  --serendipity  08-serendipitous-check.py --with-q --rich
  --sweep        08-composition-verify.py --all

Flag order (a record gets the first that applies):
  S1  superseded, verified: an explicit GF(2) scheme below our rank that we built from published files and
      checked exactly (Medley's 7x7x7, a rebuilt serendipitous product, or an explicit composition)
  S2  superseded, claimed only: a GF(2)-valid rank claim below ours (paper table, or a matmulcatalog
      cited/derived bound) that we did not rebuild
  M1  matched, verified: an explicit GF(2) scheme or composition at exactly our rank, built and checked
  M2  matched, claimed only: a GF(2)-valid rank claim equal to ours
  Q   class caveat: our class is below_all but a characteristic-0-only (Q) catalogue claim is lower
Prints a Markdown table (all flagged records) and the counts.
Run: python3 08-consolidate.py --rescore R.json --literature L.json --closure C.json --serendipity S.json --sweep X.json
"""
import argparse
import csv
import json
from collections import Counter
from pathlib import Path

W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
RECORDS = W / 'release-0929/gf2-campaign-records/records.tsv'


TAGS = [(r'adap:data/455_73\.m', 'Arai 455:73'), (r'adap:data/555_94\.m', 'Arai 555:94'), (r'medley:2609\.17533', 'Medley 777:245'),
        (r'kauers:(\d)(\d)(\d)/[^\]]*mod2\.exp', r'KW-Z2 \1\2\3'), (r'kauers:(\d)(\d)(\d)/[^\]]*', r'KW \1\2\3'),
        (r'mmc:known/section\d+/[^\]]*alphatensor_F2[^\]]*', 'AlphaTensor-F2'), (r'mmc:known/section\d+/[^\]]*flips_mod2[^\]]*', 'KM-F2'),
        (r'mmc:known/section\d+/[^\]]*alphaevolve[^\]]*', 'AlphaEvolve'), (r'mmc:known/section\d+/[^\]]*perminov[^\]]*', 'Perminov-ZT'),
        (r'mmc:constructed/section\d+/[^\]]*hk71[^\]]*', 'HK71'), (r'mmc:[a-z-]+/section\d+/[^\]]*', 'mmc'),
        (r'schemes/known/MerlijnW70_fmm_schemes/[^\]]*', 'fmm-schemes'), (r'schemes/results/(ZT|Z)/[^\]]*', r'FMM-\1'),
        (r'schemes/results/serendipitous_base/[^\]]*', 'FMM-ser.base'), (r'schemes/known/[^\]]*', 'FMM-known'), (r'schemes/[^\]]*', 'FMM')]


def short(recipe):
    import re
    for pat, rep in TAGS:
        recipe = re.sub(pat, rep, recipe)
    return recipe


def main():
    ap = argparse.ArgumentParser()
    for name in ('rescore', 'literature', 'closure', 'serendipity', 'sweep'):
        ap.add_argument('--' + name, required=True)
    a = ap.parse_args()
    rec = {r['shape']: r for r in csv.DictReader(RECORDS.open(), delimiter='\t')}
    info = {s: dict(verified_below=[], verified_equal=[], claimed_below=[], claimed_equal=[], q_below=[]) for s in rec}

    lit = json.loads(Path(a.literature).read_text())
    if lit['medley']['verified_over_F2']:
        info['7x7x7']['verified_below'].append('245: Medley et al. arXiv:2609.17533 App. A, scheme decoded and verified over F2')
    for block in (lit['perminov'], lit['transcribed']):
        for label, v in block.items():
            for h in v['hits']['a']:
                target = info[h['shape']]['claimed_below' if h['paper_rank'] < h['ours'] else 'claimed_equal']
                target.append(f"{h['paper_rank']}: arXiv:{label.split()[0]} {' '.join(label.split()[1:])} line {h['line']} ({h['ring']})")

    clo = json.loads(Path(a.closure).read_text())
    for r in clo['flagged']:
        s = r['shape']
        for c in r['cited']:
            if c['field'] in ('Z', 'R/Q/Z'):
                target = info[s]['claimed_below' if c['rank'] < r['rank'] else 'claimed_equal']
                target.append(f"{c['rank']}: matmulcatalog cited-bounds ({c['source']}; {c['field']}; no factor matrices)")
            elif c['field'] == 'Q' and c['rank'] < r['rank']:
                info[s]['q_below'].append(f"{c['rank']}: matmulcatalog cited-bounds ({c['source']}; Q)")
        for d in r['derived']:
            if d['field'] == 'F2':
                target = info[s]['claimed_below' if d['rank'] < r['rank'] else 'claimed_equal']
                target.append(f"{d['rank']}: matmulcatalog derived-from-cited-bounds (F2; {d['breakdown']})")
        for name in ('L2S', 'L2', 'L0S', 'L0'):
            if r[name] < r['rank']:
                info[s]['claimed_below'].append(f"{r[name]}: composition of listed / published GF(2) ranks ({name}): {short(r['derivation_L2S'])[:300]}")
                break
            if r[name] == r['rank']:
                info[s]['claimed_equal'].append(f"{r[name]}: composition of listed / published GF(2) ranks ({name}): {short(r['derivation_L2S'])[:300]}")
                break

    ser = json.loads(Path(a.serendipity).read_text())
    for r in ser['rows']:
        if r.get('verified_over_F2') and r['built'] <= r['ours']:
            target = info[r['shape']]['verified_below' if r['built'] < r['ours'] else 'verified_equal']
            target.append(f"{r['built']}: serendipitous product {r['s1']} x {r['s2']} of FMM {r['base'].split('/')[-1][:32]}.. "
                          f"(matmulcatalog claim {r['claim']}), rebuilt and verified over F2")

    sw = json.loads(Path(a.sweep).read_text())
    for r in sw['below'] + sw['equal']:
        if r.get('verified_over_F2') and r['built'] is not None and r['built'] <= r['ours']:
            target = info[r['shape']]['verified_below' if r['built'] < r['ours'] else 'verified_equal']
            target.append(f"{r['built']}: explicit composition, verified over F2: {r['recipe'][:200]}")

    rows, counts = [], {}
    verified_how = {}
    for r in sw['below'] + sw['equal']:
        if r.get('verified_over_F2'):
            verified_how.setdefault(r['shape'], []).append((r['built'], 'composition: ' + short(r['recipe'])))
    for r in ser['rows']:
        if r.get('verified_over_F2') and r['built'] <= r['ours']:
            verified_how.setdefault(r['shape'], []).append(
                (r['built'], f"serendipitous product <{','.join(map(str, r['orientation'][0]))}> x <{','.join(map(str, r['orientation'][1]))}>"
                             f" of FMM {r['base'].split('/')[-1][:24]}..; bud blocks "
                             + ', '.join(f'{n} x <{b}>' for b, n in sorted(Counter(r['block_shapes']).items()))))
    if lit['medley']['verified_over_F2']:
        verified_how.setdefault('7x7x7', []).append((245, 'Medley et al. arXiv:2609.17533 App. A (F2)'))
    for s, v in info.items():
        r = rec[s]
        flag = ('S1' if v['verified_below'] else 'S2' if v['claimed_below'] else
                'M1' if v['verified_equal'] else 'M2' if v['claimed_equal'] else
                'Q' if v['q_below'] and r['class'] == 'below_all' else None)
        if flag is None:
            continue
        counts[flag] = counts.get(flag, 0) + 1
        best = min([int(x.split(':')[0]) for k in ('verified_below', 'claimed_below', 'verified_equal', 'claimed_equal', 'q_below')
                    for x in v[k]])
        evidence = (v['verified_below'] or v['claimed_below'] or v['verified_equal'] or v['claimed_equal'] or v['q_below'])[0]
        rows.append((flag, s, int(r['rank']), r['class'], best, evidence, r['chain']))
    order = {'S1': 0, 'S2': 1, 'M1': 2, 'M2': 3, 'Q': 4}
    rows.sort(key=lambda x: (order[x[0]], tuple(map(int, x[1].split('x')))))
    for flag, title in (('S1', 'S1 superseded, verified scheme built by us'), ('S2', 'S2 superseded, rank claim only'),
                        ('M1', 'M1 matched, verified'), ('M2', 'M2 matched, rank claim only'),
                        ('Q', 'Q class caveat (below_all contradicted by a characteristic-0 claim)')):
        print(f'#### {title}\n')
        print('| shape | ours | class | prior | how (smallest first) | our chain |')
        print('|---|---|---|---|---|---|')
        for f, s, rank, cls, best, ev, chain in rows:
            if f != flag:
                continue
            if flag in ('S1', 'M1'):
                b, how = min(verified_how[s])
                prior = b
            else:
                prior, how = best, ev.split(': ', 1)[1]
            print(f'| {s} | {rank} | {cls} | {prior} | {how.replace("|", "/")} | {chain} |')
        print()
    by = {}
    for flag, s, *_ in rows:
        if flag in ('S1', 'M1'):
            kinds = {('serendipitous' if h.startswith('serendipitous') else 'medley' if h.startswith('Medley') else 'composition')
                     for b, h in verified_how[s] if b == min(verified_how[s])[0]}
            key = flag + ':' + '+'.join(sorted(kinds))
            by[key] = by.get(key, 0) + 1
    q_all = sorted((s for s, v in info.items() if v['q_below'] and rec[s]['class'] == 'below_all'),
                   key=lambda t: tuple(map(int, t.split('x'))))
    by_class = {}
    for flag, s, rank, cls, *_ in rows:
        by_class[f'{flag}:{cls}'] = by_class.get(f'{flag}:{cls}', 0) + 1
    clean = [s for s in rec if s not in {x[1] for x in rows}]
    by_class.update({f'unflagged:{c}': sum(1 for s in clean if rec[s]['class'] == c) for c in ('below_all', 'gf2_valid_only')})
    # which published F2-only schemes the verified below-our-rank compositions use (08-composition-verify.py rows)
    leaf_use = {}
    for r in sw['below']:
        if not r.get('verified_over_F2'):
            continue
        for tag, pat in (('Arai <4,5,5>:73', 'adap:data/455_73.m'), ('Arai <5,5,5>:94', 'adap:data/555_94.m'),
                         ('Kauers-Wood Z2-only', 'mod2.exp'), ('Medley <7,7,7>:245', 'medley:'),
                         ('AlphaTensor F2 (matmulcatalog)', 'alphatensor_F2'), ('Kauers-Moosbauer F2 (matmulcatalog)', 'flips_mod2')):
            if any(pat in leaf for leaf in r['leaves']):
                leaf_use.setdefault(tag, []).append(r['shape'])
    print(json.dumps(dict(counts=counts, evidence=by, by_class=by_class, q_claim_below_all_records=q_all,
                          verified_below_compositions_using=leaf_use,
                          flagged=len(rows), unflagged=len(rec) - len(rows),
                          superseded_verified=sorted([x[1] for x in rows if x[0] == 'S1'], key=lambda t: tuple(map(int, t.split('x')))),
                          superseded_claimed=sorted([x[1] for x in rows if x[0] == 'S2'], key=lambda t: tuple(map(int, t.split('x')))),
                          matched=sorted([x[1] for x in rows if x[0] in ('M1', 'M2')], key=lambda t: tuple(map(int, t.split('x'))))),
                     indent=1))


if __name__ == '__main__':
    main()
