#!/usr/bin/env python3
"""Select packing representatives with explicit equality-partition bijections.

Every unmatched or budget-limited parent remains represented. Full tensors
are retained elsewhere; this portfolio is for current bud/grid packing only.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import time

from extend_composition_parents import identity
from packing_incidence import find_permutation, profile
from verify_representation_portfolio import parse_terms


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--new-from', type=int, required=True)
    p.add_argument('--max-rank', type=int, default=256)
    p.add_argument('--max-states', type=int, default=2000)
    p.add_argument('--max-comparisons', type=int, default=16)
    args = p.parse_args()
    assert not args.output.exists() and args.new_from >= 0 and min(args.max_rank, args.max_states, args.max_comparisons) > 0
    pins = {}
    def blob(path):
        path = Path(path).resolve()
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert pins.get(str(path), digest) == digest
        pins[str(path)] = digest
        return raw
    inputs = json.loads(blob(args.inputs))
    assert inputs['complete'] and inputs['field'] == 'GF(2)' and not inputs['record_claim']
    for name in ('packing_incidence_portfolio.py', 'packing_incidence.py'):
        blob(Path(__file__).with_name(name))
    selected = [(i, parent) for i, parent in enumerate(inputs['parents'])
                if min(parent['shape']) >= 2 and parent['rank'] <= args.max_rank]
    args.output.mkdir()
    report = dict(complete=False, field='GF(2)', record_claim=False, packing_only=True,
        canonical_archive_changed=False, source_sha256=pins, parents=len(selected), processed=0,
        classes=[], matches=[], limits=dict(new_from=args.new_from, max_rank=args.max_rank,
            max_states=args.max_states, max_comparisons=args.max_comparisons))
    bins, cached, stats = defaultdict(list), {}, Counter()
    start = time.monotonic()
    def save():
        report['stats'] = dict(stats)
        report['elapsed_seconds'] = time.monotonic()-start
        pending = args.output/'report.pending.json'
        pending.write_text(json.dumps(report, indent=2)+'\n')
        pending.replace(args.output/'report.json')
    save()
    for index, parent in selected:
        raw = blob(parent['path'])
        assert hashlib.sha256(raw).hexdigest() == parent['sha256']
        terms = parse_terms(raw, parent['rank'])
        assert identity(parent['shape'], terms) == parent['identity']
        view = profile(terms)
        key = tuple(parent['shape']), view['signature']
        selected_class = None
        for class_index in bins[key][:args.max_comparisons]:
            representative = report['classes'][class_index]['representative']
            result = find_permutation(cached[representative], view, max_states=args.max_states, max_terms=args.max_rank)
            stats['comparisons'] += 1
            stats['states'] += result['states']
            stats[result['status']] += 1
            if result['status'] == 'matched':
                selected_class = class_index
                report['matches'].append(dict(source=representative, target=index, permutation=result['permutation']))
                break
        if selected_class is None:
            if len(bins[key]) > args.max_comparisons:
                stats['comparison_limits'] += 1
            selected_class = len(report['classes'])
            bins[key].append(selected_class)
            report['classes'].append(dict(representative=index, shape=parent['shape'], rank=parent['rank'],
                                           members=[], touches_new=False))
            cached[index] = view
        group = report['classes'][selected_class]
        group['members'].append(index)
        group['touches_new'] |= index >= args.new_from
        report['processed'] += 1
        if report['processed'] % 500 == 0:
            save()
            print(json.dumps(dict(processed=report['processed'], total=len(selected),
                representatives=len(report['classes']), matches=len(report['matches']), elapsed=report['elapsed_seconds'])), flush=True)
    report['packing_representatives'] = [group['representative'] for group in report['classes'] if group['touches_new']]
    report['covered_new_parents'] = sum(index >= args.new_from for index, _ in selected)
    assert sum(len(group['members']) for group in report['classes']) == len(selected)
    assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in pins.items())
    report['complete'] = True
    save()
    print(json.dumps({k: v for k, v in report.items() if k not in ('source_sha256', 'classes', 'matches', 'packing_representatives')}), flush=True)
    print(json.dumps(dict(packing_representatives=len(report['packing_representatives']),
                          all_representatives=len(report['classes']))), flush=True)


if __name__ == '__main__':
    main()
