#!/usr/bin/env python3
"""Replay exact GF(2) middle-mask projection descendants from a pinned parent."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import screen_middle_shear_children as middle
import screen_top_two_projection_children as top
from wide_matrix_cleanup_parity_test import read_blob

HERE = Path(__file__).resolve().parent
DEFAULT_MANIFEST = HERE / 'certificates/middle-mask-cascade-20260923/manifest.json'
PORTFOLIO = HERE / 'certificates/structured-parent-portfolio-20260922/manifest.json'
MIDDLE_SHEAR = HERE / 'certificates/middle-shear-children-20260923/manifest.json'


def replay_source(source, root):
    if source.get('kind') == 'structured-portfolio':
        matches = [row for row in json.loads(PORTFOLIO.read_text())['rows']
                   if row['shape'] == source['portfolio_shape']]
        if (len(matches) != 1 or matches[0]['result_shape'] != source['oriented_shape'] or
                matches[0]['rank'] != source['rank'] or
                matches[0]['result_sha256'] != source['scheme_sha256']):
            raise ValueError('source portfolio pin mismatch')
        subprocess.run(['ruby', str(HERE / 'replay_structured_parent_portfolio.rb'),
                        '--output', str(root), '--only',
                        'x'.join(map(str, source['portfolio_shape']))],
                       check=True, capture_output=True, text=True)
        return (root / 'x'.join(map(str, source['portfolio_shape'])) /
                ('x'.join(map(str, source['oriented_shape'])) + '.mfw'))
    if source.get('kind') == 'middle-shear':
        if hashlib.sha256(MIDDLE_SHEAR.read_bytes()).hexdigest() != source['manifest_sha256']:
            raise ValueError('middle-shear source manifest changed')
        old = json.loads(MIDDLE_SHEAR.read_text())['row']
        if (old['oriented_shape'] != source['oriented_shape'] or
                old['rank'] != source['rank'] or old['sha256'] != source['mfw_sha256']):
            raise ValueError('middle-shear source pin mismatch')
        destination = root / 'source'
        subprocess.run(['python3', str(HERE / 'screen_middle_shear_children.py'),
                        '--replay-manifest', str(MIDDLE_SHEAR), '--output-dir', str(destination)],
                       check=True, capture_output=True, text=True)
        return (destination / ('x'.join(map(str, source['oriented_shape'])) +
                               f'-r{source["rank"]}-{source["mfw_sha256"][:12]}.mfw'))
    raise ValueError('unknown source kind')


def replay(manifest, output_dir):
    if (manifest.get('schema') != 1 or manifest.get('field') != 'GF(2)' or
            manifest.get('record_claim') is not False or
            not isinstance(manifest.get('steps'), list) or not manifest['steps']):
        raise ValueError('invalid cascade manifest')
    source = manifest['source']
    with tempfile.TemporaryDirectory(prefix='metaflip-middle-mask-cascade-') as temp:
        root = Path(temp)
        parent = replay_source(source, root)
        payload = parent.read_bytes()
        if hashlib.sha256(payload).hexdigest() != source['mfw_sha256']:
            raise ValueError('source tensor hash mismatch')
        shape, terms = read_blob(payload)
        if tuple(source['oriented_shape']) != shape or len(terms) != source['rank']:
            raise ValueError('source shape or rank mismatch')
        top.exact(shape, terms)
        results = []
        if output_dir:
            output_dir.mkdir(parents=True, exist_ok=False)
        for step in manifest['steps']:
            if step['axis'] != 1:
                raise ValueError('unsupported projection axis')
            target, raw, cleaned, history = middle.child_mask(
                shape, terms, step['deleted_coordinate'], step['shear_mask'],
                independent=True)
            payload = top.blob(target, cleaned)
            digest = hashlib.sha256(payload).hexdigest()
            if (list(target) != step['oriented_shape'] or
                    len(raw) != step['raw_rank'] or len(history) != step['cleanup_steps'] or
                    len(cleaned) != step['rank'] or digest != step['sha256']):
                raise ValueError('projection or cleanup mismatch')
            if output_dir:
                path = output_dir / ('x'.join(map(str, target)) +
                                     f'-r{len(cleaned)}-{digest[:12]}.mfw')
                path.write_bytes(payload)
                check = json.loads(subprocess.check_output(
                    ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
                     'x'.join(map(str, target)), str(path)], text=True))[0]
                if not check['exact'] or check['rank'] != len(cleaned) or check['sha256'] != digest:
                    raise ValueError('independent tensor verification failed')
            results.append({'shape': list(target), 'rank': len(cleaned), 'sha256': digest})
            shape, terms = target, cleaned
        return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    print(json.dumps(replay(json.loads(args.manifest.read_text()), args.output_dir), indent=2))


if __name__ == '__main__':
    main()
