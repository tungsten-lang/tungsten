#!/usr/bin/env python3
"""Build an arXiv source bundle for one paper directory and check that it compiles on its own.

usage: pack_arxiv.py methods|results [--final] [--no-build] [--no-verify]

The bundle (dist/<paper>-arxiv.tar.gz) contains main.tex, every file that main.tex reaches through
\\input, \\includegraphics, pgfplots `table {...}` and \\bibliography, plus main.bbl and refs.bib.
Nothing else (no PDF, no aux files, no unused data).  --final refuses to pack while any \\todo{...}
remains in the sources.  Unless --no-verify, the bundle is unpacked into a temporary directory and
compiled with tectonic from scratch (the .bbl is what arXiv will use).
"""
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
args = [a for a in sys.argv[1:] if not a.startswith('--')]
flags = {a for a in sys.argv[1:] if a.startswith('--')}
if len(args) != 1 or args[0] not in ('methods', 'results'):
    sys.exit(__doc__)
name = args[0]
paper = ROOT / name

if '--no-build' not in flags:
    subprocess.run([sys.executable, str(ROOT / 'scripts' / 'mkbib.py'), name], check=True)
    subprocess.run(['tectonic', '-X', 'compile', 'main.tex', '--keep-intermediates', '--keep-logs'], cwd=paper, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

PATTERNS = [
    (r'\\input\{([^}]+)\}', ('.tex',)),
    (r'\\include\{([^}]+)\}', ('.tex',)),
    (r'\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}', ('', '.pdf', '.png', '.jpg')),
    (r'table\s*(?:\[[^\]]*\])?\s*\{([^}]+)\}', ('',)),
    (r'\\bibliography\{([^}]+)\}', ('.bib',)),
]


def closure(entry):
    seen, todo = [], [entry]
    while todo:
        f = todo.pop()
        if f in seen:
            continue
        seen.append(f)
        if f.suffix != '.tex':
            continue
        text = re.sub(r'(?m)(?<!\\)%.*$', '', f.read_text())
        for pat, exts in PATTERNS:
            for m in re.finditer(pat, text):
                for ref in m.group(1).split(','):
                    ref = ref.strip()
                    for ext in exts:
                        cand = paper / (ref if ref.endswith(ext) and ext else ref + ext)
                        if cand.is_file():
                            todo.append(cand)
                            break
                    else:
                        print(f'warning: {f.relative_to(paper)}: no file for {ref!r}', file=sys.stderr)
    return seen


files = closure(paper / 'main.tex')
bbl = paper / 'main.bbl'
if not bbl.is_file():
    sys.exit('main.bbl missing: build first (drop --no-build)')
if bbl not in files:
    files.append(bbl)

todos = []
for f in files:
    if f.suffix == '.tex':
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if '\\todo' in line and not line.lstrip().startswith(('\\newcommand', '%')):
                todos.append(f'{f.relative_to(paper)}:{i}')
if todos:
    print(f'{len(todos)} \\todo remain:', ', '.join(todos), file=sys.stderr)
    if '--final' in flags:
        sys.exit('refusing to pack a final bundle with TODOs')

dist = ROOT / 'dist'
dist.mkdir(exist_ok=True)
out = dist / f'{name}-arxiv.tar.gz'
with tarfile.open(out, 'w:gz') as tf:
    for f in sorted(files):
        info = tf.gettarinfo(str(f), arcname=str(f.relative_to(paper)))
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        info.mtime = 0
        with open(f, 'rb') as fh:
            tf.addfile(info, fh)
print(f'{out.relative_to(ROOT)}: {len(files)} files, {out.stat().st_size} bytes')

if '--no-verify' not in flags:
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(out) as tf:
            tf.extractall(tmp, filter='data')
        r = subprocess.run(['tectonic', '-X', 'compile', 'main.tex', '--keep-logs'], cwd=tmp, capture_output=True, text=True)
        pdf = Path(tmp) / 'main.pdf'
        log = (Path(tmp) / 'main.log').read_text() if (Path(tmp) / 'main.log').exists() else ''
        undefined = re.findall(r'(?:Reference|Citation) `[^\']+\' .*undefined', log)
        if r.returncode != 0 or not pdf.exists():
            print(r.stderr[-2000:], file=sys.stderr)
            sys.exit('verification build FAILED')
        print(f'verification build ok: {pdf.stat().st_size} bytes, {len(undefined)} undefined references')
        if undefined:
            print('\n'.join(undefined[:10]), file=sys.stderr)
            sys.exit('undefined references in the standalone build')
