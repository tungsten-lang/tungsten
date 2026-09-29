#!/usr/bin/env python3
"""Combine the retained reference and three Core-generated refinement studies.

Run from repo root after building filament_refined.w and negative_space.w.
The earlier Filament T is retained as a clearly labeled comparison reference.
"""
import argparse
import copy
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--reference', type=Path, default=Path('build/filament-t/timelines.json'))
parser.add_argument('--filament', type=Path, default=Path('build/logo-refinement/filament/timelines.json'))
parser.add_argument('--negative', type=Path, default=Path('build/negative-space-research/timelines.json'))
parser.add_argument('--output', type=Path, default=Path('build/logo-refinement'))
args = parser.parse_args()

def read_studies(path):
    data = json.loads(path.read_text())
    assert data['schema'] == 'tungsten.logo-studies/v1'
    return copy.deepcopy(data['studies'])

reference = read_studies(args.reference)[0]
refined = read_studies(args.filament)[0]
negative = read_studies(args.negative)
assert len(negative) == 2
reference['timeline']['scene']['metadata'].update(name='Earlier filament', bucket='Reference', number=1)
refined['timeline']['scene']['metadata'].update(name='Refined filament', bucket='Eight coils · stronger stem', number=2)
studies = [reference, refined, *negative]
for i, study in enumerate(studies, start=1):
    study['timeline']['scene']['metadata']['number'] = i
    assert len(study['samples']) == 97
    assert study['samples'][0]['updates'] == study['samples'][-1]['updates']
args.output.mkdir(parents=True, exist_ok=True)
(args.output / 'timelines.json').write_text(json.dumps({
    'schema': 'tungsten.logo-studies/v1',
    'title': 'Filament and counterform.',
    'slug': 'tungsten-logo-refinement',
    'studies': studies,
}, separators=(',', ':')))
print(f'Combined {len(studies)} Core timelines, including the labeled reference.')
