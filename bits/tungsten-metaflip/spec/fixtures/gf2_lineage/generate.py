#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_lineage/ from the ORIGINAL verifier (tools/verify_gf2_lineage.py, the oracle).

  generate.py

writes, next to this file:

  in/repo/...              the two rank-29 seeds of the 3x3x4 format, at the paths `retained` rows name
  in/history/...           a tree whose commit holds an old copy of one seed (the `archived` rows' upstream)
  in/schemes/...           a tree whose commit holds one public integer scheme (the `public-mod2` rows' upstream)
  in/bundles/<name>/       lineage bundles: a good one with every derived kind (closure, basis, walk, projection with and without a
                           basis rewrite), tampered copies of it that must be rejected, and bundles for the seed kinds
  in/walker-copy.sh, in/walker-corrupt.sh   stand-ins for the compiled walker
  cases.json               per case: the bundle, the options (sources, repo root, walker) and `ok` or `rejected` for the original
  expected/<case>.txt      what the original prints for a bundle it accepts

The trees are committed with fixed author, committer and date (the test builds the same commits, so the hashes in the manifests hold).
Everything here is derived from the Python original, never from the Tungsten port.
"""
import base64
import contextlib
import copy
import gzip
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
REPO = BIT.parents[1]
sys.path[:0] = [str(BIT / 'tools'), str(BIT / 'spec'), str(REPO / 'benchmarks/matmul/metaflip')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import gf2_record_board as grb  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402
import verify_gf2_lineage as V  # noqa: E402
from screen_public_ternary_gf2 import reduce_mod2  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
import mmc_gf2_alg as G  # noqa: E402
import mmc_gf2_replay as MR  # noqa: E402

IN = HERE / 'in'
EXPECTED = HERE / 'expected'
SEEDS = BIT / 'lib/metaflip/seeds/gf2'
SEED_NAME = 'matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt'
OTHER_NAME = 'matmul_3x3x4_rank29_gf2.txt'
SEED_REL = 'lib/metaflip/seeds/gf2/' + SEED_NAME
OTHER_REL = 'lib/metaflip/seeds/gf2/' + OTHER_NAME
GIT_ENV = {'GIT_AUTHOR_NAME': 'fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
           'GIT_COMMITTER_NAME': 'fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
           'GIT_AUTHOR_DATE': '2026-09-30T12:00:00+0000', 'GIT_COMMITTER_DATE': '2026-09-30T12:00:00+0000',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null'}
HISTORY_PATH = 'benchmarks/matmul_3x3x4_rank29_archive_gf2.txt'
SCHEME_PATH = 'schemes/found/Z/2x2x2_m7_Z.json'
SCHEMES_URL = 'https://example.invalid/fixture-schemes'
HISTORY_URL = 'https://example.invalid/tungsten-history'


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True,
                          env={**os.environ, **GIT_ENV}).stdout


def commit_tree(tree, scratch):
    target = scratch / tree.name
    shutil.copytree(tree, target)
    git(target, 'init', '-q')
    git(target, 'add', '-f', '.')
    git(target, 'commit', '-q', '-m', 'fixture')
    return target, git(target, 'rev-parse', 'HEAD').strip()


def add_row(bundle, rows, terms, shape, kind, parent, details, raw=None, rank=None):
    raw = top.blob(shape, terms) if raw is None else raw
    digest = hashlib.sha256(raw).hexdigest()
    name = f"{'x'.join(map(str, shape))}-r{len(terms) if rank is None else rank}-{digest[:8]}.mfw.gz.b64"
    (bundle / name).write_bytes(base64.encodebytes(gzip.compress(raw, mtime=0)))
    rows.append(dict(kind=kind, parent=parent, shape='x'.join(map(str, shape)), rank=len(terms) if rank is None else rank,
                     sha256=digest, file=name, details=details))
    return digest


def write_manifest(bundle, rows, **header):
    manifest = dict(schema=1, field='GF(2)', record_claim=False, rows=rows)
    manifest.update(header)
    (bundle / 'manifest.json').write_text(json.dumps(manifest, indent=1) + '\n')


def main():
    if IN.exists():
        shutil.rmtree(IN)
    if EXPECTED.exists():
        shutil.rmtree(EXPECTED)
    (IN / 'bundles').mkdir(parents=True)
    EXPECTED.mkdir()
    (IN / 'repo/lib/metaflip/seeds/gf2').mkdir(parents=True)
    for name in (SEED_NAME, OTHER_NAME):
        shutil.copy(SEEDS / name, IN / 'repo/lib/metaflip/seeds/gf2' / name)
    (IN / 'history/benchmarks').mkdir(parents=True)
    shutil.copy(SEEDS / SEED_NAME, IN / 'history' / HISTORY_PATH)
    (IN / 'schemes/schemes/found/Z').mkdir(parents=True)
    scheme_text = None
    # the Strassen scheme with odd coefficients, as the public-scheme fixture has it
    sys.path.insert(0, str(BIT / 'spec/fixtures/gf2_public_ternary'))
    import generate as public_fixture  # noqa: E402
    scheme_text = json.dumps(public_fixture.oddify(public_fixture.strassen()), separators=(',', ':')) + '\n'
    (IN / 'schemes' / SCHEME_PATH).write_text(scheme_text)

    scratch = Path(tempfile.mkdtemp(prefix='gf2-lineage-'))
    try:
        history, history_rev = commit_tree(IN / 'history', scratch)
        schemes, schemes_rev = commit_tree(IN / 'schemes', scratch)
        catalogue, catalogue_rev = commit_tree(HERE.parent / 'gf2_catalogue' / 'tree', scratch)
        build(scratch, history, history_rev, schemes, schemes_rev, catalogue, catalogue_rev)
    finally:
        shutil.rmtree(scratch)


def build(scratch, history, history_rev, schemes, schemes_rev, catalogue_repo, catalogue_rev):
    seed = SEEDS / SEED_NAME
    shape, seed_terms = grb.decode(seed, grb.load(seed))
    base = sorted(seed_terms)
    bundles = IN / 'bundles'

    # ---- the good bundle: every derived kind
    good = bundles / 'good'
    good.mkdir()
    rows = []
    recipe = dict(kind='seed', rank=len(base), shape=list(shape), source='metaflip/seeds/gf2/' + SEED_NAME,
                  source_sha256=hashlib.sha256(seed.read_bytes()).hexdigest())
    root = add_row(good, rows, base, shape, 'closure', None, dict(recipe=recipe))
    outs = {mode: two_pass(base, shape, mode) for mode in range(6, 12)}
    blobs = {mode: top.blob(shape, terms) for mode, terms in outs.items()}
    mode_a = next(mode for mode in outs if blobs[mode] != top.blob(shape, base))
    mode_b = next(mode for mode in outs if blobs[mode] not in (top.blob(shape, base), blobs[mode_a]))
    basis_terms = list(outs[mode_a])
    basis = add_row(good, rows, basis_terms, shape, 'basis', root, dict(mode=mode_a))
    add_row(good, rows, basis_terms, shape, 'walk', basis, dict(steps=1000, nonce=7))

    def projection(parent_terms, axis, coordinate):
        child_shape, projected = top.project(shape, parent_terms, axis, coordinate)
        width = max(child_shape[0] * child_shape[1], child_shape[1] * child_shape[2], child_shape[0] * child_shape[2])
        child, _ = top.compress_shared(projected, max_bits=width)
        return child_shape, child
    child_shape, child = projection(base, 2, 0)
    add_row(good, rows, child, child_shape, 'projection', root, dict(mode=None, axis=2, coordinate=0))
    other_shape, other = projection(base, 2, 3)
    assert top.blob(other_shape, other) != top.blob(child_shape, child)
    ruled_shape, ruled = projection(outs[mode_b], 1, 1)
    add_row(good, rows, ruled, ruled_shape, 'projection', root, dict(mode=mode_b, axis=1, coordinate=1))
    write_manifest(good, rows)
    good_rows = rows

    cases = []

    def case(name, bundle, options=None, expect='ok'):
        cases.append(dict(name=name, bundle=bundle, options=options or {}, expect=expect))

    def tampered(label, mutate, header=None, replace_files=None):
        bad = bundles / label
        shutil.copytree(good, bad)
        manifest = json.loads((bad / 'manifest.json').read_text())
        mutate(bad, manifest['rows'])
        if header:
            manifest.update(header)
        (bad / 'manifest.json').write_text(json.dumps(manifest))
        case(label, label, expect='rejected')

    case('good', 'good')

    def file_swap(bundle, rows_):
        rows_[0]['file'] = rows_[3]['file']
    tampered('file-swap', file_swap)

    def recipe_rank(bundle, rows_):
        rows_[0]['details']['recipe']['rank'] = 30
    tampered('recipe-rank', recipe_rank)

    def projection_coordinate(bundle, rows_):
        rows_[3]['details']['coordinate'] = 3
    tampered('projection-coordinate', projection_coordinate)

    def projection_mode(bundle, rows_):
        rows_[4]['details']['mode'] = None
    tampered('projection-mode', projection_mode)

    def basis_mode(bundle, rows_):
        rows_[1]['details']['mode'] = mode_b
    tampered('basis-mode', basis_mode)

    def unknown_kind(bundle, rows_):
        rows_[2]['kind'] = 'magic'
    tampered('unknown-kind', unknown_kind)

    def walk_grows(bundle, rows_):
        rows_[2], rows_[0] = rows_[0], rows_[2]
        rows_[0]['parent'], rows_[2]['parent'] = None, rows_[1]['sha256']
        rows_[1]['parent'] = rows_[0]['sha256']
    tampered('walk-shape', walk_grows)

    def missing_provenance(bundle, rows_):
        rows_[0]['kind'] = 'public-mod2'
        rows_[0]['details'] = dict(repository='https://example.org/x')
    tampered('provenance', missing_provenance)
    tampered('header', lambda bundle, rows_: None, header=dict(schema=2))
    tampered('record-claim', lambda bundle, rows_: None, header=dict(record_claim=True))

    def parent_missing(bundle, rows_):
        rows_[1]['parent'] = '0' * 64
    tampered('parent-missing', parent_missing)

    def parent_later(bundle, rows_):
        rows_[0], rows_[1] = rows_[1], rows_[0]
    tampered('parent-later', parent_later)

    def parent_on_seed(bundle, rows_):
        rows_[0]['parent'] = rows_[1]['sha256']
    tampered('parent-on-seed', parent_on_seed)

    def rank_field(bundle, rows_):
        rows_[0]['rank'] = 28
    tampered('rank-field', rank_field)

    def shape_field(bundle, rows_):
        rows_[0]['shape'] = '3x4x3'
    tampered('shape-field', shape_field)

    def inexact_file(bundle, rows_):
        broken = list(base)
        broken[0] = (broken[0][0] ^ 1, broken[0][1], broken[0][2])
        raw = top.blob(shape, broken)
        digest = hashlib.sha256(raw).hexdigest()
        name = f"3x3x4-r29-{digest[:8]}.mfw.gz.b64"
        (bundle / name).write_bytes(base64.encodebytes(gzip.compress(raw, mtime=0)))
        rows_[0]['file'], rows_[0]['sha256'] = name, digest
        rows_[1]['parent'] = digest
        rows_[3]['parent'] = digest
        rows_[4]['parent'] = digest
    tampered('inexact-tensor', inexact_file)

    def uncanonical_file(bundle, rows_):
        raw = top.blob(shape, base)
        lines = raw.decode().split('\n')
        lines[1], lines[2] = lines[2], lines[1]
        raw = '\n'.join(lines).encode()
        digest = hashlib.sha256(raw).hexdigest()
        name = f"3x3x4-r29-{digest[:8]}.mfw.gz.b64"
        (bundle / name).write_bytes(base64.encodebytes(gzip.compress(raw, mtime=0)))
        rows_[0]['file'], rows_[0]['sha256'] = name, digest
        for row in rows_[1:]:
            if row['parent'] == good_rows[0]['sha256']:
                row['parent'] = digest
    tampered('uncanonical-text', uncanonical_file)

    # ---- walk replay with stand-in walkers
    replay = bundles / 'replay'
    replay.mkdir()
    rows = []
    root = add_row(replay, rows, base, shape, 'closure', None, dict(recipe=recipe))
    add_row(replay, rows, base, shape, 'walk', root, dict(steps=1000, nonce=7))
    write_manifest(replay, rows)
    (IN / 'walker-copy.sh').write_text('#!/bin/sh\ncp "$2" "$3"\n')
    (IN / 'walker-corrupt.sh').write_text("#!/bin/sh\nprintf 'MFW1 3 3 4 1\\n1 1 1\\n' > \"$3\"\n")
    (IN / 'walker-fail.sh').write_text('#!/bin/sh\nexit 3\n')
    case('replay-no-walker', 'replay')
    case('replay-copy', 'replay', dict(replay_walk='$WALKER_COPY'))
    case('replay-corrupt', 'replay', dict(replay_walk='$WALKER_CORRUPT'), expect='rejected')
    case('replay-fail', 'replay', dict(replay_walk='$WALKER_FAIL'), expect='rejected')
    case('replay-skipped-by-rank', 'replay', dict(replay_walk='$WALKER_CORRUPT', replay_max_rank=5))

    # ---- retained rows
    retained = bundles / 'retained'
    retained.mkdir()
    rows = []
    add_row(retained, rows, base, shape, 'retained', None, dict(path=SEED_REL))
    write_manifest(retained, rows)
    case('retained-no-root', 'retained')
    case('retained-root', 'retained', dict(repo_root='$REPO'))
    retained_bad = bundles / 'retained-bad'
    shutil.copytree(retained, retained_bad)
    manifest = json.loads((retained_bad / 'manifest.json').read_text())
    manifest['rows'][0]['details']['path'] = OTHER_REL
    (retained_bad / 'manifest.json').write_text(json.dumps(manifest))
    case('retained-wrong-file', 'retained-bad', dict(repo_root='$REPO'), expect='rejected')

    # ---- archived rows
    archived = bundles / 'archived'
    archived.mkdir()
    rows = []
    details = dict(repository=HISTORY_URL, revision=history_rev, path=HISTORY_PATH,
                   source_sha256=hashlib.sha256(seed.read_bytes()).hexdigest())
    add_row(archived, rows, base, shape, 'archived', None, details)
    write_manifest(archived, rows)
    case('archived-no-source', 'archived')
    case('archived-source', 'archived', dict(sources={'tungsten-history': '$HISTORY'}))
    archived_bad = bundles / 'archived-bad'
    shutil.copytree(archived, archived_bad)
    manifest = json.loads((archived_bad / 'manifest.json').read_text())
    manifest['rows'][0]['details']['source_sha256'] = '0' * 64
    (archived_bad / 'manifest.json').write_text(json.dumps(manifest))
    case('archived-digest', 'archived-bad', dict(sources={'tungsten-history': '$HISTORY'}), expect='rejected')
    archived_other = bundles / 'archived-other'
    shutil.copytree(archived, archived_other)
    manifest = json.loads((archived_other / 'manifest.json').read_text())
    other_seed = SEEDS / OTHER_NAME
    other_shape, other_terms = grb.decode(other_seed, grb.load(other_seed))
    # a different tensor under the recorded digest of the archive: the row's own file is replaced by another exact tensor
    raw = top.blob(other_shape, sorted(other_terms))
    digest = hashlib.sha256(raw).hexdigest()
    name = f"3x3x4-r29-{digest[:8]}.mfw.gz.b64"
    (archived_other / name).write_bytes(base64.encodebytes(gzip.compress(raw, mtime=0)))
    manifest['rows'][0]['file'], manifest['rows'][0]['sha256'] = name, digest
    (archived_other / 'manifest.json').write_text(json.dumps(manifest))
    case('archived-other-tensor', 'archived-other', dict(sources={'tungsten-history': '$HISTORY'}), expect='rejected')

    # ---- public-mod2 rows
    public = bundles / 'public'
    public.mkdir()
    source_text = (schemes / SCHEME_PATH).read_bytes()
    public_shape, public_rank, public_terms = reduce_mod2(json.loads(source_text))
    rows = []
    details = dict(repository=SCHEMES_URL, revision=schemes_rev, path=SCHEME_PATH,
                   source_sha256=hashlib.sha256(source_text).hexdigest(), source_rank=public_rank)
    add_row(public, rows, public_terms, public_shape, 'public-mod2', None, details)
    write_manifest(public, rows)
    case('public-no-source', 'public')
    case('public-source', 'public', dict(sources={'fixture-schemes': '$SCHEMES'}))
    public_bad = bundles / 'public-bad'
    shutil.copytree(public, public_bad)
    manifest = json.loads((public_bad / 'manifest.json').read_text())
    manifest['rows'][0]['details']['source_rank'] = 8
    (public_bad / 'manifest.json').write_text(json.dumps(manifest))
    case('public-source-rank', 'public-bad', dict(sources={'fixture-schemes': '$SCHEMES'}), expect='rejected')
    public_sha = bundles / 'public-sha'
    shutil.copytree(public, public_sha)
    manifest = json.loads((public_sha / 'manifest.json').read_text())
    manifest['rows'][0]['details']['source_sha256'] = '1' * 64
    (public_sha / 'manifest.json').write_text(json.dumps(manifest))
    case('public-source-digest', 'public-sha', dict(sources={'fixture-schemes': '$SCHEMES'}), expect='rejected')

    # ---- recipe-replay rows: provenance only (the replay of the catalogue's recipes is not part of the port)
    recipe_bundle = bundles / 'recipe'
    recipe_bundle.mkdir()
    rows = []
    catalogue = dict(repository='https://github.com/solven-eu/matmulcatalog', revision='f' * 40,
                     file='derived/section18/3x14x18-r562-derived-8523d8a.json', lineage='a +p b')
    add_row(recipe_bundle, rows, base, shape, 'recipe-replay', None, dict(catalogue, rederivable=False))
    write_manifest(recipe_bundle, rows)
    case('recipe-no-source', 'recipe')
    case('recipe-equal-rank-variant', 'recipe', dict(sources={'matmulcatalog': '$HISTORY'}))
    recipe_bad = bundles / 'recipe-bad'
    shutil.copytree(recipe_bundle, recipe_bad)
    manifest = json.loads((recipe_bad / 'manifest.json').read_text())
    del manifest['rows'][0]['details']['lineage']
    (recipe_bad / 'manifest.json').write_text(json.dumps(manifest))
    case('recipe-provenance', 'recipe-bad', expect='rejected')

    # ---- recipe-replay rows with a catalogue to replay them from (the synthetic one of spec/fixtures/gf2_catalogue)
    replay_file = 'derived/s4/4x4x4-r49-derived-aaaaaaa.json'
    cache = scratch / 'mmc-cache-fixture'
    replayed = MR.Replayer(MR.Source(catalogue_repo, catalogue_rev, cache), use_disk_cache=False).materialize_file(replay_file)
    details = dict(repository='https://github.com/solven-eu/matmulcatalog', revision=catalogue_rev, file=replay_file, lineage='synthetic')
    catalogue_bundle = bundles / 'catalogue'
    catalogue_bundle.mkdir()
    rows = []
    add_row(catalogue_bundle, rows, sorted(replayed.terms), replayed.shape, 'recipe-replay', None, details)
    write_manifest(catalogue_bundle, rows)
    case('catalogue-no-source', 'catalogue')
    case('catalogue-replay', 'catalogue', dict(sources={'solven-eu': '$CATALOGUE'}, cache_dir='$CACHE'))
    wrong = bundles / 'catalogue-wrong'
    wrong.mkdir()
    rows = []
    other_replayed = MR.Replayer(MR.Source(catalogue_repo, catalogue_rev, cache), use_disk_cache=False).materialize_file(
        'derived/s4/6x4x4-r98-derived-000000b.json')
    # a different exact tensor of the same format and rank class under the row's recipe
    swapped = G.kron(G.naive(2, 2, 2), G.naive(2, 2, 2))
    add_row(wrong, rows, sorted(swapped.terms), swapped.shape, 'recipe-replay', None, details)
    write_manifest(wrong, rows)
    case('catalogue-replay-differs', 'catalogue-wrong', dict(sources={'solven-eu': '$CATALOGUE'}, cache_dir='$CACHE'), expect='rejected')
    failing = bundles / 'catalogue-failing'
    failing.mkdir()
    rows = []
    add_row(failing, rows, sorted(replayed.terms), replayed.shape, 'recipe-replay', None,
            dict(details, file='derived/s4/2x2x2-r7-derived-000001d.json'))
    write_manifest(failing, rows)
    case('catalogue-replay-fails', 'catalogue-failing', dict(sources={'solven-eu': '$CATALOGUE'}, cache_dir='$CACHE'), expect='rejected')

    # ---- run the original on every case
    (IN / 'walker-copy.sh').chmod(0o755)
    (IN / 'walker-corrupt.sh').chmod(0o755)
    (IN / 'walker-fail.sh').chmod(0o755)
    substitutions = {'$WALKER_COPY': str(IN / 'walker-copy.sh'), '$WALKER_CORRUPT': str(IN / 'walker-corrupt.sh'),
                     '$WALKER_FAIL': str(IN / 'walker-fail.sh'), '$REPO': str(IN / 'repo'), '$HISTORY': str(history),
                     '$SCHEMES': str(schemes), '$CATALOGUE': str(catalogue_repo), '$CACHE': str(scratch / 'mmc-cache-run')}
    for entry in cases:
        options = entry['options']
        argv = [str(bundles / entry['bundle']), '--no-ruby']
        for name, path in options.get('sources', {}).items():
            argv += ['--source', f'{name}={substitutions[path]}']
        if 'repo_root' in options:
            argv += ['--repo-root', substitutions[options['repo_root']]]
        if 'replay_walk' in options:
            argv += ['--replay-walk', substitutions[options['replay_walk']]]
        if 'replay_max_rank' in options:
            argv += ['--replay-max-rank', str(options['replay_max_rank'])]
        if 'cache_dir' in options:
            argv += ['--cache-dir', substitutions[options['cache_dir']]]
        out = io.StringIO()
        outcome = 'ok'
        try:
            with contextlib.redirect_stdout(out):
                V.main(argv)
        except (AssertionError, KeyError, ValueError, TypeError, MR.ReplayError, subprocess.CalledProcessError):
            outcome = 'rejected'
        assert outcome == entry['expect'], (entry['name'], outcome)
        if outcome == 'ok':
            text = out.getvalue()
            for key, value in substitutions.items():
                text = text.replace(value, key)
            (EXPECTED / f"{entry['name']}.txt").write_text(text)
    (HERE / 'cases.json').write_text(json.dumps(cases, indent=1) + '\n')
    print('wrote', len(cases), 'cases to', HERE)


if __name__ == '__main__':
    main()
