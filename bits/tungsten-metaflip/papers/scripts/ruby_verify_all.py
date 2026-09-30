#!/usr/bin/env python3
"""Run the independent Ruby exactness check (tools/verify_tensor.rb) over every tensor behind the results paper:

  * the 985 distinct tensors of the four release bundles (manifest rows, distinct by SHA-256),
  * the 102 committed certificates that the record index points at inside the repository,
  * the two fleet checkpoints of the record index (7x7x7 and 15x15x15): MFW1 as is, or converted from the fleet's decimal
    text format (rank on the first line, then one `a b c` decimal triple per term, bit layout as MFW1).

usage: ruby_verify_all.py RELEASE_DIR [--repo-root DIR] [--jobs N] > ruby_all.log
RELEASE_DIR is the work directory's release-0929/ (bundles + gf2-campaign-records/records.tsv).
Prints one line per tensor, `ok|FAIL <group> <shape> <rank> <sha256[:16]>`, then a summary; exit status 1 on any failure.
"""
import base64, concurrent.futures, csv, gzip, hashlib, json, subprocess, sys, tempfile
from pathlib import Path

args = [a for a in sys.argv[1:]]
release = Path(args.pop(0))
repo = Path(__file__).resolve().parents[4]                       # papers/scripts -> repo root
jobs_n = 8
while args:
    a = args.pop(0)
    if a == '--repo-root':
        repo = Path(args.pop(0))
    elif a == '--jobs':
        jobs_n = int(args.pop(0))
RUBY = repo / 'bits/tungsten-metaflip/tools/verify_tensor.rb'
BUNDLES = ['gf2-searched-records', 'gf2-closure-products', 'gf2-block47-certificates-2026-07', 'gf2-public-ternary-walks-2026-09-26']


def unb64(path):
    return gzip.decompress(base64.b64decode(Path(path).read_bytes().replace(b'\n', b''), validate=True))


def fleet_to_mfw(path, shape):
    n, m, p = map(int, shape.split('x'))
    text = Path(path).read_text()
    if text.startswith('MFW1'):                                     # some fleet files are already canonical MFW1
        return text.encode()
    lines = text.split('\n')
    rank = int(lines[0])
    terms = sorted(tuple(int(x) for x in ln.split()) for ln in lines[1:] if ln.strip())
    assert len(terms) == rank, (path, len(terms), rank)
    return (f'MFW1 {n} {m} {p} {rank}\n' + ''.join(f'{a:x} {b:x} {c:x}\n' for a, b, c in terms)).encode()


jobs, seen = [], set()
for b in BUNDLES:
    man = json.loads((release / b / 'manifest.json').read_text())
    for row in man['rows']:
        if row['sha256'] in seen:
            continue
        seen.add(row['sha256'])
        jobs.append(('bundle:' + b, release / b / row['file'], int(row['rank']), row['sha256'], None))
n_bundle = len(jobs)
for row in csv.DictReader(open(release / 'gf2-campaign-records/records.tsv'), delimiter='\t'):
    if row['asset'] == 'bits/tungsten-metaflip (committed certificate)':
        jobs.append(('committed', repo / row['file'], int(row['rank']), row['tensor_sha256'], None))
    elif row['asset'] == '2026-09-29-gf2-campaign-records.tar.gz':
        jobs.append(('fleet', release / 'gf2-campaign-records' / row['file'], int(row['rank']), row['tensor_sha256'], row['shape']))


def check(job):
    group, path, rank, sha, fleet_shape = job
    raw = fleet_to_mfw(path, fleet_shape) if fleet_shape else unb64(path)
    head = raw.split(b'\n', 1)[0].split()
    shape = 'x'.join(x.decode() for x in head[1:4])
    digest = hashlib.sha256(raw).hexdigest()
    with tempfile.TemporaryDirectory() as t:
        f = Path(t) / 'x.mfw'
        f.write_bytes(raw)
        out = json.loads(subprocess.check_output(['ruby', str(RUBY), '--shape', shape, str(f)], text=True))[0]
    ok = bool(out['exact'] and out['rank'] == rank and int(head[4]) == rank)
    if group.startswith('bundle') and digest != sha:
        ok = False                                                # a bundle file must hash to its manifest row
    return ok, group, shape, rank, digest


bad, counts = 0, {}
with concurrent.futures.ThreadPoolExecutor(jobs_n) as pool:
    for ok, group, shape, rank, digest in pool.map(check, jobs):
        bad += not ok
        counts.setdefault(group.split(':')[0], [0, 0])[0 if ok else 1] += 1
        print(('ok  ' if ok else 'FAIL'), group, shape, rank, digest[:16], flush=True)
print(f'RUBY exact: bundle tensors {counts.get("bundle", [0, 0])[0]}/{n_bundle}, committed certificates {counts.get("committed", [0, 0])[0]}/102, '
      f'fleet checkpoints {counts.get("fleet", [0, 0])[0]}/2; failures {bad}')
sys.exit(1 if bad else 0)
