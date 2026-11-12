#!/usr/bin/env python3
"""Golden data for lib/metaflip/gf2/fsx.w, produced by Python's pathlib/os.path (the oracle).

usage: gen_fsx_goldens.py OUTDIR [WORK_DIR]     (python3 >= 3.14: suffix/stem rules changed in 3.14)

Writes, deterministically (fixed seed, no absolute paths, no timestamps):
  paths.tsv    pure path arithmetic: path, str(Path(path)), parts, name, parent, stem, suffix,
               is_absolute                       (parts joined with '|')
  join.tsv     str(PurePosixPath(*args)) for argument lists joined with '|'
  relative.tsv path, base, path.relative_to(base) or '!' (ValueError)
  parents.tsv  path, levels, path.parents[levels-1] or '!' (IndexError)
  expand.tsv   path, os.path.abspath(os.path.join('/base/dir', path))
  tree.txt     a directory tree for the disk cases: `d NAME`, `f NAME`, `l NAME TARGET` (a
               TARGET starting with ABS: is an absolute link into the tree's root)
  glob.tsv     pattern, mode (all|files), sorted(Path(root).glob(pattern)) relative to root,
               each result once, in pathlib's sorted-path order, joined with '|' ('.' = the root)
  resolve.tsv  path relative to root, Path(root / path).resolve() relative to root.resolve()
               ('OUTSIDE' when it leaves the root)
  real_glob.tsv  (only with WORK_DIR, the record-hunt work directory) real trees: root relative to
               WORK_DIR, pattern, mode, match count, SHA-256 of the matches (relative to the root,
               in sorted-Path order, joined with newlines plus a final newline)
Every field avoids tab, newline and '|'.
"""
import hashlib
import os
import pathlib
import random
import sys
import tempfile

TREE = """\
d a
d a/b
f a/b/f.txt
f a/g.txt
f a.b
f a-b
d a-dir
f a-dir/1.txt
d a.dir
f a.dir/2.txt
d .hid
f .hid/h.txt
f .dot.txt
d sp ace
f sp ace/3.txt
d é
f é/ü.txt
f é/plain.md
d empty
d deep
d deep/x
d deep/x/y
f deep/x/y/z.mfw
f deep/x/y/z.mfw.gz.b64
f deep/x/w.mfw
f deep/top.mfw
f best.txt
f matmul_2x3x5_gf2.txt
f matmul_4x4_gf2.txt
f 7
d mat
f mat/seeds.json
d mat_r1
f mat_r1/seeds.json
d mat-x
f mat-x/seeds.json
d checkpoints
d checkpoints/gf2
d checkpoints/gf2/run1
f checkpoints/gf2/run1/best.txt
d checkpoints/gf2/run2
f checkpoints/gf2/run2/best.txt
f checkpoints/gf2/run2/other.txt
l lnk a
l loop .
l dangling nowhere
l a/up ..
l r_abs ABS:a/b
l r_rel a/b
l r_chain1 r_chain2
l r_chain2 a
l r_dd lnk/b
l r_loop1 r_loop2
l r_loop2 r_loop1
l r_self r_self
l r_tri1 r_tri2
l r_tri2 r_tri3
l r_tri3 r_tri1
"""

GLOBS = [
    '*', '.*', '*.txt', 'a*', 'a?b', '?', '??', '*.md', 'é/*', 'é/?.txt', '*/*.txt', '*/*/*.txt',
    '**', '**/*', '**/*.txt', '**/*.mfw', '**/*.mfw.gz.b64', '**/best.txt', 'checkpoints/gf2/*/best.txt',
    'checkpoints/**/best.txt', 'mat*/seeds.json', '*_r1/seeds.json', '?at*/seeds.json',
    'matmul_*_gf2.txt', 'matmul_*x*_gf2.txt', 'lnk/*', 'lnk/b/*', 'lnk/**', 'loop/*', 'loop/a/*',
    'dangling', 'd*', 'nowhere', 'a/up/*', '**/z.mfw', 'deep/**/*.mfw', 'deep/**', '**/x', '**/y/*',
    'sp ace/*', '*ace*', 'a/b/f.txt', 'a/b/nothere.txt', 'empty/*', '**/empty', 'a/**/f.txt',
    '**/**/f.txt', '*/**/*.txt', '7', 'r_*', '**/r_a*',
]
FILE_GLOBS = ['*', '**', '**/*', '*/*', 'lnk/*', 'r_*', 'd*', '**/*.txt']

RESOLVES = [
    'a', 'a/b', 'a/./b/../g.txt', 'lnk', 'lnk/b/f.txt', 'lnk/../a', 'lnk/../x', 'a/up/a/b',
    'dangling', 'dangling/x', 'nowhere/../a', 'nonexist/../a/b', 'nonexist/x/y', 'r_abs',
    'r_abs/f.txt', 'r_rel', 'r_chain1', 'r_chain1/b', 'r_dd/f.txt', 'r_loop1', 'r_loop1/x',
    'r_loop2', 'r_self', 'r_self/x', 'r_tri1', 'r_tri2/x', 'loop/loop/loop/a', '.', 'a//b/./',
    'deep/x/../top.mfw', 'a-b',
]

ALPHABET = ['', '.', '..', 'a', 'b', '.x', 'x.', 'c.tar.gz', 'é', ' s', 'a..', '..a', 'q.r']
ROOTS = ['', '/', '//', '///']


def sample_paths(rng, count):
    seen, out = set(), []
    fixed = ['', '.', '..', '/', '//', '///', 'a', '/a', '//a', 'a/', 'a//b', './a/./b', 'x/../y',
             '/a/b/c.txt', 'a.tar.gz', '.bashrc', 'a.', 'a..', '...', '.a.', '..a', '/a/b/.',
             'dir.d/file.txt', 'é/ü.txt', ' lead', 'trail ', 'a b/c d', '.hidden/.f', 'x' * 40]
    for p in fixed:
        if p not in seen:
            seen.add(p)
            out.append(p)
    while len(out) < count:
        n = rng.choice([0, 1, 1, 2, 2, 3, 3, 4])
        p = rng.choice(ROOTS) + '/'.join(rng.choice(ALPHABET) for _ in range(n))
        if rng.random() < 0.15:
            p += '/'
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def parts_of(p):
    return '|'.join(pathlib.PurePosixPath(p).parts)


def write(outdir, name, lines):
    for line in lines:
        assert '\n' not in line
    with open(os.path.join(outdir, name), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(lines) + '\n')


def build_tree(root):
    for line in TREE.splitlines():
        kind, _, rest = line.partition(' ')
        if kind == 'd':
            os.makedirs(os.path.join(root, rest), exist_ok=True)
        elif kind == 'f':
            os.makedirs(os.path.dirname(os.path.join(root, rest)), exist_ok=True)
            open(os.path.join(root, rest), 'w').close()
        else:
            name, target = rest.rsplit(' ', 1)
            if target.startswith('ABS:'):
                target = os.path.join(root, target[4:])
            os.symlink(target, os.path.join(root, name))


REAL_TREES = [
    ('upstream-latest/fmm-tree-ac13ca8855', '**/*.json', 'all'),
    ('upstream-latest/fmm-tree-ac13ca8855', 'schemes/known/*/*.json', 'all'),
    ('upstream-latest/fmm-tree-ac13ca8855', '**', 'files'),
    ('release-0929/gf2-searched-records', '*.mfw.gz.b64', 'all'),
    ('release-0929/gf2-searched-records', '**/*', 'files'),
    ('release-0929/gf2-closure-products', '*.mfw.gz.b64', 'all'),
    ('release-0929/gf2-campaign-records', '**/*.jsonl', 'all'),
    ('release-0929/gf2-campaign-records', '*/*.json', 'all'),
    ('release-0929/gf2-campaign-records/seeds', '**/seeds.json', 'all'),
    ('.', '*.jsonl', 'all'),
    ('.', 'mat*/seeds.json', 'all'),
    ('.', 'release-0929/gf2-*', 'all'),
    ('.', '*_mfw/*.mfw', 'all'),
    ('port-corpus', 'mfw/*.mfw', 'all'),
]


def real_rows(work):
    rows = []
    for rel, pattern, mode in REAL_TREES:
        root = pathlib.Path(work) / rel
        if not root.is_dir():
            continue
        hits = sorted(set(root.glob(pattern)))
        if mode == 'files':
            hits = [h for h in hits if h.is_file()]
        names = ['.' if h == root else str(h.relative_to(root)) for h in hits]
        digest = hashlib.sha256(('\n'.join(names) + '\n').encode()).hexdigest()
        rows.append('\t'.join([rel, pattern, mode, str(len(names)), digest]))
    return rows


def main(outdir, work=None):
    os.makedirs(outdir, exist_ok=True)
    rng = random.Random(20260929)
    paths = sample_paths(rng, 520)
    rows = []
    for p in paths:
        q = pathlib.PurePosixPath(p)
        rows.append('\t'.join([p, str(q), parts_of(p), q.name, str(q.parent), q.stem, q.suffix,
                               'true' if q.is_absolute() else 'false']))
    write(outdir, 'paths.tsv', rows)

    rows = []
    for _ in range(260):
        args = [rng.choice(paths[:120]) for _ in range(rng.choice([1, 2, 2, 3]))]
        if any('|' in a for a in args):
            continue
        rows.append('\t'.join(['|'.join(args), str(pathlib.PurePosixPath(*args))]))
    write(outdir, 'join.tsv', rows)

    small = sample_paths(random.Random(7), 60)
    rows = []
    for path in small:
        for base in small:
            if rng.random() < 0.05 or (base and path.startswith(base.rstrip('/'))):
                try:
                    result = str(pathlib.PurePosixPath(path).relative_to(base))
                except ValueError:
                    result = '!'
                rows.append('\t'.join([path, base, result]))
    write(outdir, 'relative.tsv', rows[:420])

    rows = []
    for path in paths[:90]:
        for levels in (1, 2, 3, 4):
            try:
                result = str(pathlib.PurePosixPath(path).parents[levels - 1])
            except IndexError:
                result = '!'
            rows.append('\t'.join([path, str(levels), result]))
    write(outdir, 'parents.tsv', rows)

    rows = [f'{p}\t{os.path.abspath(os.path.join("/base/dir", p))}' for p in paths[:150]]
    write(outdir, 'expand.tsv', rows)

    with open(os.path.join(outdir, 'tree.txt'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(TREE)

    with tempfile.TemporaryDirectory() as temp:
        root = pathlib.Path(temp).resolve() / 'tree'
        root.mkdir()
        build_tree(str(root))
        rows = []
        for pattern in GLOBS:
            for mode in ('all', 'files') if pattern in FILE_GLOBS else ('all',):
                hits = list(root.glob(pattern))
                if mode == 'files':
                    hits = [h for h in hits if h.is_file()]
                unique = sorted(set(hits))
                names = ['.' if h == root else str(h.relative_to(root)) for h in unique]
                rows.append('\t'.join([pattern, mode, '|'.join(names)]))
        write(outdir, 'glob.tsv', rows)
        rows = []
        for case in RESOLVES:
            resolved = (root / case).resolve()
            try:
                shown = str(resolved.relative_to(root))
            except ValueError:
                shown = 'OUTSIDE'
            rows.append('\t'.join([case, shown]))
        write(outdir, 'resolve.tsv', rows)
    if work:
        write(outdir, 'real_glob.tsv', real_rows(work))


if __name__ == '__main__':
    main(*sys.argv[1:3])
