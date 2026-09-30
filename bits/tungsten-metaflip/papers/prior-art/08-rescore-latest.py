#!/usr/bin/env python3
"""Part A of the 2026-09-29 prior-art audit: re-score the 795 records against the latest public tables.

Every table is built by gf2_record_board.public_tables(), imported from the repository tools
directory (the scoring rule of the release), and every class by the rule in its main():
below_all if rank < best_any; gf2_valid_only if rank < best_gf2; tie if rank == best_any;
no_public_rank if best_any is None; else above.  Our ranks are never changed.

  1. Pinned reproduction.  public_tables() on the exact inputs of the 2026-09-29 scoring
     (W/upstream/{fmm_digest,fmm,merlijn} pinned clones, W/mmc_catalog_0929.json) must give
     best_listed_any_ring and best_listed_gf2_valid (and the class) of every records.tsv row:
     0 disagreements, otherwise the script aborts before anything else is computed.
  2. Clone cross-check.  The same tables rebuilt from the fresh clones under W/upstream-latest
     at the pinned revisions must equal step 1 exactly (whole tables, every shape).
  3. Latest.  Tables at the fresh clones' HEADs; the 795 records are re-classified.
  4. Attribution.  Per-source tables (public_tables() with the other sources switched off) at
     every revision after each pin give the source and the first commit that supplied each
     moved comparator (FMM: also the file names).

Writes W/paper-data/rescore_latest.tsv; prints a JSON summary on stdout.
Run: python3 08-rescore-latest.py   (needs the clones made on 2026-09-29, see W/upstream-latest)
"""
import csv
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

os.environ['GIT_NO_LAZY_FETCH'] = '1'  # never fetch into the pinned partial clones
W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
REL = W / 'release-0929/gf2-campaign-records'
UP, LATEST = W / 'upstream', W / 'upstream-latest'
EXTRACTED = LATEST / 'extracted'
OUT_TSV = W / 'paper-data/rescore_latest.tsv'
TOOLS = '/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools'
sys.path.insert(0, TOOLS)
import gf2_record_board as grb  # noqa: E402

COMP = json.loads((REL / 'comparators.json').read_text())['sources']
PIN = dict(lille=COMP['lille_digest']['commit'], mmc=COMP['matmulcatalog']['scored']['commit'],
           fmm=COMP['fast_matrix_multiplication']['scored']['commit'], merlijn=COMP['fmm_schemes']['scored']['commit'])
PIN_SHA = dict(lille=COMP['lille_digest']['sha256'], mmc=COMP['matmulcatalog']['catalog_sha256'])
REPO = dict(lille=LATEST / 'fmm_digest', mmc=LATEST / 'matmulcatalog', fmm=LATEST / 'fmm', merlijn=LATEST / 'fmm-schemes')
SOURCES = ('lille', 'mmc', 'fmm', 'merlijn')
LABEL = dict(lille='Lille fmm_digest', mmc='matmulcatalog', fmm='FastMatrixMultiplication', merlijn='fmm-schemes')


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def commit_info(repo, rev):
    h, date, subject = git(repo, 'log', '-1', '--format=%H%x09%cI%x09%s', rev).split('\t', 2)
    return dict(commit=h, date=date, subject=subject)


def after(repo, pin):
    """Commits in pin..HEAD, oldest first (first-parent order is enough: all four are linear here)."""
    out = git(repo, 'rev-list', '--reverse', f'{pin}..HEAD')
    return out.split() if out else []


def extracted(source, rev):
    """Materialise fmm_sota.json / docs/catalog.json of one revision under W/upstream-latest/extracted."""
    rel = dict(lille='fmm_sota.json', mmc='docs/catalog.json')[source]
    stem = dict(lille='fmm_sota', mmc='mmc_catalog')[source]
    full = git(REPO[source], 'rev-parse', rev)
    path = EXTRACTED / f'{stem}_{full[:12]}.json'
    if not path.exists():
        EXTRACTED.mkdir(parents=True, exist_ok=True)
        path.write_bytes(subprocess.check_output(['git', '-C', str(REPO[source]), 'show', f'{full}:{rel}']))
    return path


EMPTY_LILLE = EXTRACTED / 'empty_lille.json'


def tables(lille=None, mmc=None, fmm=None, extra=None):
    """public_tables() of the release tool; a source left None is switched off (Lille -> empty list)."""
    if lille is None:
        EXTRACTED.mkdir(parents=True, exist_ok=True)
        if not EMPTY_LILLE.exists():
            EMPTY_LILLE.write_text('{"entries": []}\n')
        lille = EMPTY_LILLE
    args = SimpleNamespace(lille=str(lille), matmulcatalog=str(mmc) if mmc else None,
                           fmm_repo=str(fmm[0]) if fmm else None, fmm_revision=fmm[1] if fmm else 'HEAD',
                           extra_repo=[str(extra)] if extra else [])
    _, any_ring, gf2 = grb.public_tables(args)
    return any_ring, gf2


def per_source(inputs):
    """{source: (any_ring, gf2)} with only that source switched on, plus the merged tables."""
    parts = dict(lille=tables(lille=inputs['lille']), mmc=tables(mmc=inputs['mmc']),
                 fmm=tables(fmm=inputs['fmm']), merlijn=tables(extra=inputs['merlijn']))
    merged = tables(**{k: inputs[s] for k, s in (('lille', 'lille'), ('mmc', 'mmc'), ('fmm', 'fmm'), ('extra', 'merlijn'))})
    # the merged table must be the key-wise minimum of the four single-source tables
    for i in (0, 1):
        union = {}
        for s in SOURCES:
            for k, v in parts[s][i].items():
                union[k] = min(v, union.get(k, v))
        assert union == merged[i], 'merged table is not the minimum of the per-source tables'
    return parts, merged


def classify(rank, best_any, best_gf2):
    """The rule in gf2_record_board.main()."""
    if best_any is not None and rank < best_any:
        return 'below_all'
    if best_gf2 is not None and rank < best_gf2:
        return 'gf2_valid_only'
    if best_any is not None and rank == best_any:
        return 'tie'
    if best_any is None:
        return 'no_public_rank'
    return 'above'


def rglob_names(extra):
    return sorted(str(p.relative_to(extra)) for p in Path(extra).rglob('*.json'))


def fmt(v):
    return '' if v is None else str(v)


def main():
    rows = list(csv.DictReader((REL / 'records.tsv').open(), delimiter='\t'))
    assert len(rows) == 795, len(rows)
    keys = [tuple(map(int, r['shape'].split('x'))) for r in rows]
    assert all(list(k) == sorted(k) for k in keys)

    # ---- 1. pinned reproduction with the exact inputs of the release scoring
    assert sha256(UP / 'fmm_digest/fmm_sota.json') == PIN_SHA['lille']
    assert git(UP / 'fmm_digest', 'rev-parse', 'HEAD') == PIN['lille']
    assert sha256(W / 'mmc_catalog_0929.json') == PIN_SHA['mmc']
    assert git(UP / 'fmm', 'rev-parse', 'HEAD') == PIN['fmm']
    assert git(UP / 'merlijn', 'rev-parse', 'HEAD') == PIN['merlijn']
    assert git(UP / 'merlijn', '--no-optional-locks', 'status', '--porcelain') == '', 'pinned fmm-schemes working tree is not clean'
    pinned_inputs = dict(lille=UP / 'fmm_digest/fmm_sota.json', mmc=W / 'mmc_catalog_0929.json',
                         fmm=(UP / 'fmm', PIN['fmm']), merlijn=UP / 'merlijn')
    pinned_parts, (pin_any, pin_gf2) = per_source(pinned_inputs)
    disagreements = []
    for r, k in zip(rows, keys):
        old_any = int(r['best_listed_any_ring']) if r['best_listed_any_ring'] else None
        old_gf2 = int(r['best_listed_gf2_valid']) if r['best_listed_gf2_valid'] else None
        cls = classify(int(r['rank']), pin_any.get(k), pin_gf2.get(k))
        if (pin_any.get(k), pin_gf2.get(k), cls) != (old_any, old_gf2, r['class']):
            disagreements.append((r['shape'], old_any, pin_any.get(k), old_gf2, pin_gf2.get(k), r['class'], cls))
    if disagreements:
        print(json.dumps(dict(pinned_disagreements=disagreements)), file=sys.stderr)
        sys.exit('ABORT: pinned tables do not reproduce records.tsv')
    # the release tool globbed the pinned fmm-schemes working tree; it holds the files git tracks
    assert rglob_names(UP / 'merlijn') == sorted(n for n in git(UP / 'merlijn', 'ls-tree', '-r', '--name-only', 'HEAD').split('\n') if n.endswith('.json'))

    # ---- 2. the fresh clones at the pinned revisions give the identical tables
    for s in SOURCES:
        assert git(REPO[s], 'merge-base', '--is-ancestor', PIN[s], 'HEAD') == ''  # raises if not an ancestor
    assert sha256(extracted('lille', PIN['lille'])) == PIN_SHA['lille']
    assert sha256(extracted('mmc', PIN['mmc'])) == PIN_SHA['mmc']
    merlijn_moved = git(REPO['merlijn'], 'rev-parse', 'HEAD') != PIN['merlijn']
    clone_pinned_inputs = dict(lille=extracted('lille', PIN['lille']), mmc=extracted('mmc', PIN['mmc']),
                               fmm=(REPO['fmm'], PIN['fmm']), merlijn=REPO['merlijn'] if not merlijn_moved else None)
    if not merlijn_moved:
        clone_parts, clone_tables = per_source(clone_pinned_inputs)
        assert clone_tables == (pin_any, pin_gf2), 'fresh clones at the pinned revisions disagree with the pinned clones'
        for s in SOURCES:
            assert clone_parts[s] == pinned_parts[s], s

    # ---- 3. latest tables
    heads = {s: commit_info(REPO[s], 'HEAD') for s in SOURCES}
    assert git(REPO['merlijn'], '--no-optional-locks', 'status', '--porcelain') == ''
    assert rglob_names(REPO['merlijn']) == sorted(n for n in git(REPO['merlijn'], 'ls-tree', '-r', '--name-only', 'HEAD').split('\n') if n.endswith('.json'))
    latest_inputs = dict(lille=extracted('lille', 'HEAD'), mmc=extracted('mmc', 'HEAD'),
                         fmm=(REPO['fmm'], heads['fmm']['commit']), merlijn=REPO['merlijn'])
    latest_parts, (new_any_t, new_gf2_t) = per_source(latest_inputs)

    # ---- 4. per-revision single-source tables for attribution
    history = {}  # source -> [(commit info, (any, gf2))] for commits after the pin
    for s in ('lille', 'mmc', 'fmm'):
        seq = []
        for c in after(REPO[s], PIN[s]):
            if s == 'fmm':
                t = tables(fmm=(REPO['fmm'], c))
            else:
                t = tables(**{s: extracted(s, c)})
            seq.append((commit_info(REPO[s], c), t))
        history[s] = seq
    history['merlijn'] = []  # HEAD == pin (asserted below for the report)

    def first_commit(source, idx, key, value):
        """First post-pin commit whose single-source table reaches `value` at `key`."""
        for info, t in history[source]:
            if t[idx].get(key) is not None and t[idx][key] <= value:
                return info
        return None

    fmm_names_head = git(REPO['fmm'], 'ls-tree', '-r', '--name-only', heads['fmm']['commit'], 'schemes').split('\n')

    def fmm_files(key, value, rings):
        out = []
        for n in fmm_names_head:
            m = grb.RING.search(n)
            if m and '/known/' not in n and tuple(sorted(map(int, m.group(1, 2, 3)))) == key \
                    and int(m.group(4)) == value and m.group(5) in rings:
                out.append(n)
        return out

    def mmc_entries(catalog_path, key, value, f2_only):
        out = []
        for e in json.loads(Path(catalog_path).read_text())['schemes']:
            if e.get('commutative') or tuple(sorted(e['format'])) != key or e['rank'] != value:
                continue
            if f2_only and 'F2' not in e['fields']:
                continue
            out.append(f"{e['source']}|{e['file']}")
        return out

    # ---- per-record re-classification
    out_rows, moved_records = [], []
    source_moves = {s: dict(any_dec=0, any_inc=0, gf2_dec=0, gf2_inc=0, any_new=0, gf2_new=0,
                            any_dec_795=0, gf2_dec_795=0, any_new_795=0, gf2_new_795=0,
                            supplied_any_795=0, supplied_gf2_795=0) for s in SOURCES}
    for s in SOURCES:
        for idx, tag in ((0, 'any'), (1, 'gf2')):
            old_t, new_t = pinned_parts[s][idx], latest_parts[s][idx]
            for k in set(old_t) | set(new_t):
                o, n = old_t.get(k), new_t.get(k)
                if o is None and n is not None:
                    source_moves[s][f'{tag}_new'] += 1
                elif o is not None and n is None:
                    source_moves[s][f'{tag}_inc'] += 1  # entry disappeared
                elif n < o:
                    source_moves[s][f'{tag}_dec'] += 1
                elif n > o:
                    source_moves[s][f'{tag}_inc'] += 1
    key_set = set(keys)
    for s in SOURCES:
        for idx, tag in ((0, 'any'), (1, 'gf2')):
            old_t, new_t = pinned_parts[s][idx], latest_parts[s][idx]
            for k in key_set:
                o, n = old_t.get(k), new_t.get(k)
                if o is None and n is not None:
                    source_moves[s][f'{tag}_new_795'] += 1
                elif o is not None and n is not None and n < o:
                    source_moves[s][f'{tag}_dec_795'] += 1

    counts_new, transitions = {}, {}
    comparator_increases = []
    for r, k in zip(rows, keys):
        rank = int(r['rank'])
        o_any, o_gf2 = pin_any.get(k), pin_gf2.get(k)
        n_any, n_gf2 = new_any_t.get(k), new_gf2_t.get(k)
        new_cls = classify(rank, n_any, n_gf2)
        counts_new[new_cls] = counts_new.get(new_cls, 0) + 1
        transitions[f"{r['class']}->{new_cls}"] = transitions.get(f"{r['class']}->{new_cls}", 0) + 1
        if (n_any is not None and o_any is not None and n_any > o_any) or (o_gf2 is not None and (n_gf2 is None or n_gf2 > o_gf2)):
            comparator_increases.append(r['shape'])
        any_moved = n_any != o_any
        gf2_moved = n_gf2 != o_gf2
        sup_any = [s for s in SOURCES if latest_parts[s][0].get(k) == n_any] if n_any is not None else []
        sup_gf2 = [s for s in SOURCES if latest_parts[s][1].get(k) == n_gf2] if n_gf2 is not None else []
        moved_by, files = [], []
        if any_moved or gf2_moved:
            for idx, tag, val, sups in ((0, 'any', n_any, sup_any), (1, 'gf2', n_gf2, sup_gf2)):
                if (idx == 0 and not any_moved) or (idx == 1 and not gf2_moved) or val is None:
                    continue
                for s in sups:
                    before = pinned_parts[s][idx].get(k)
                    if before is not None and before <= val:
                        continue  # this source already listed the value at the pin
                    info = first_commit(s, idx, k, val) if s != 'merlijn' else None
                    moved_by.append(f"{tag}:{s}@{info['commit'][:10]} {info['date']}" if info else f'{tag}:{s}@?')
                    source_moves[s][f'supplied_{tag}_795'] += 1
                    if s == 'fmm':
                        files += fmm_files(k, val, ('ZT', 'Z', 'Q') if idx == 0 else ('ZT', 'Z'))
                    if s == 'mmc':
                        files += mmc_entries(latest_inputs['mmc'], k, val, idx == 1)
        status = 'unchanged'
        if new_cls != r['class']:
            status = 'no_longer_record' if new_cls in ('tie', 'above', 'no_public_rank') else 'downgraded'
        elif any_moved or gf2_moved:
            status = 'margin_shrank' if ((n_any is not None and o_any is not None and n_any < o_any) or
                                         (n_gf2 is not None and (o_gf2 is None or n_gf2 < o_gf2))) else 'comparator_changed'
        row = dict(shape=r['shape'], rank=rank, old_class=r['class'], new_class=new_cls, status=status,
                   old_best_any=fmt(o_any), new_best_any=fmt(n_any), old_best_gf2=fmt(o_gf2), new_best_gf2=fmt(n_gf2),
                   old_margin_any=fmt(None if o_any is None else rank - o_any), new_margin_any=fmt(None if n_any is None else rank - n_any),
                   old_margin_gf2=fmt(None if o_gf2 is None else rank - o_gf2), new_margin_gf2=fmt(None if n_gf2 is None else rank - n_gf2),
                   lille_latest=fmt(latest_parts['lille'][0].get(k)),
                   mmc_any_latest=fmt(latest_parts['mmc'][0].get(k)), mmc_f2_latest=fmt(latest_parts['mmc'][1].get(k)),
                   fmm_any_latest=fmt(latest_parts['fmm'][0].get(k)), fmm_gf2_latest=fmt(latest_parts['fmm'][1].get(k)),
                   fmmschemes_any_latest=fmt(latest_parts['merlijn'][0].get(k)), fmmschemes_gf2_latest=fmt(latest_parts['merlijn'][1].get(k)),
                   new_any_suppliers=','.join(sup_any), new_gf2_suppliers=','.join(sup_gf2),
                   moved_by=';'.join(moved_by), new_comparator_files=';'.join(files),
                   chain=r['chain'], tensor_sha256=r['tensor_sha256'])
        out_rows.append(row)
        if status != 'unchanged':
            moved_records.append(row)

    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(out_rows[0]), delimiter='\t', lineterminator='\n')
        w.writeheader()
        w.writerows(out_rows)

    # ---- 7x7x7 in every source now (and at the pin)
    k7 = (7, 7, 7)

    def seven(inputs, parts, fmm_rev):
        names = git(inputs['fmm'][0], 'ls-tree', '-r', '--name-only', fmm_rev, 'schemes').split('\n')
        fmm_all = sorted(n for n in names if n.split('/')[-1].startswith('7x7x7_') or '/777/' in n or '/known/meta_flip_graph/777' in n)
        mm = [dict(rank=e['rank'], fields=e['fields'], source=e['source'], commutative=bool(e.get('commutative')), file=e['file'])
              for e in json.loads(Path(inputs['mmc']).read_text())['schemes'] if tuple(sorted(e['format'])) == k7]
        extra = sorted(n for n in rglob_names(inputs['merlijn']) if n.split('/')[-1].startswith('7x7x7'))
        return dict(lille=parts['lille'][0].get(k7), mmc_any=parts['mmc'][0].get(k7), mmc_f2=parts['mmc'][1].get(k7),
                    mmc_entries=sorted(mm, key=lambda e: e['rank']), fmm_any=parts['fmm'][0].get(k7), fmm_gf2=parts['fmm'][1].get(k7),
                    fmm_files=fmm_all, fmmschemes_any=parts['merlijn'][0].get(k7), fmmschemes_files=extra)

    summary = dict(
        run_utc=subprocess.check_output(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ'], text=True).strip(),
        fetched_utc=(LATEST / 'fetched_at_utc.txt').read_text().strip(),
        pinned={s: commit_info(REPO[s], PIN[s]) for s in SOURCES},
        latest=heads,
        commits_after_pin={s: [info for info, _ in history[s]] for s in SOURCES},
        fmm_schemes_head_equals_pin=not merlijn_moved,
        pinned_reproduction=dict(rows=len(rows), disagreements=0),
        clone_cross_check='identical' if not merlijn_moved else 'skipped (fmm-schemes moved)',
        table_sizes=dict(pinned=dict(any=len(pin_any), gf2=len(pin_gf2)), latest=dict(any=len(new_any_t), gf2=len(new_gf2_t))),
        old_class_counts={c: sum(1 for r in rows if r['class'] == c) for c in ('below_all', 'gf2_valid_only')},
        new_class_counts=counts_new, transitions=transitions,
        status_counts={s: sum(1 for r in out_rows if r['status'] == s) for s in
                       ('unchanged', 'margin_shrank', 'comparator_changed', 'downgraded', 'no_longer_record')},
        comparator_increases=comparator_increases,
        source_moves=source_moves,
        changed_records=[{k: row[k] for k in ('shape', 'rank', 'old_class', 'new_class', 'status', 'old_best_any', 'new_best_any',
                                             'old_best_gf2', 'new_best_gf2', 'new_any_suppliers', 'new_gf2_suppliers', 'moved_by',
                                             'new_comparator_files')} for row in moved_records],
        seven_by_seven=dict(pinned=seven(pinned_inputs, pinned_parts, PIN['fmm']),
                            latest=seven(latest_inputs, latest_parts, heads['fmm']['commit'])),
    )
    print(json.dumps(summary, indent=1))


if __name__ == '__main__':
    main()
