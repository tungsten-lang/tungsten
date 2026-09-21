#!/usr/bin/env python3
"""ast_verify.py <manifest.json> <before-root> <after-root>: prove the ro/rw rewrite is AST-equivalent."""
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
manifest, before, after = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def dump(path):
    r = subprocess.run([REPO + '/bin/tungsten', '--ast', path], capture_output=True, text=True, cwd=REPO, timeout=600)
    return r.stdout, r.stderr

def expand(text):
    """ro/rw call nodes -> the method_def nodes the compiler synthesizes."""
    L, out, i = text.split('\n'), [], 0
    while i < len(L):
        m = re.match(r'^(\s*)call name="(ro|rw)"$', L[i])
        if m and i + 1 < len(L) and L[i + 1] == m.group(1) + '  args:':
            pad, j, names = m.group(1), i + 2, []
            while j < len(L):
                s = re.match(r'^' + pad + r'    symbol value="(\w+)"$', L[j])
                if not s:
                    break
                names.append(s.group(1)); j += 1
            for n in names:
                out += [f'{pad}method_def name="{n}" is_class_method=false', f'{pad}  body:', f'{pad}    ivar name="@{n}"']
                if m.group(2) == 'rw':
                    out += [f'{pad}SETTER {n}']
            i = j
            continue
        out.append(L[i]); i += 1
    return '\n'.join(out)

def canon_before(text, rw_names):
    # `return @x` getters and hand-written trivial setters, in the shape expand() produces
    text = re.sub(r'(\n(\s*)body:\n)\s*return\n\s*value:\n\s*(ivar name="@\w+")', lambda m: m.group(1) + m.group(2) + '  ' + m.group(3), text)
    return text

def check(f):
    b, be = dump(os.path.join(before, f)); a, ae = dump(os.path.join(after, f))
    if not b.strip() or not a.strip():
        return f, 'EMPTY', (be or ae)[:300]
    rw = [c['name'] for c in manifest[f] if c['rw']]
    if rw:
        return f, 'RW-MANUAL', ''
    if expand(canon_before(b, rw)) == expand(a):
        return f, 'OK', ''
    import difflib
    d = list(difflib.unified_diff(expand(canon_before(b, rw)).split('\n'), expand(a).split('\n'), lineterm='', n=1))
    return f, 'DIFF', '\n'.join(d[:24])

files = [f for f in manifest if f.endswith('.w')]
with ThreadPoolExecutor(6) as ex:
    res = list(ex.map(check, files))
bad = [r for r in res if r[1] != 'OK']
print(f'{len(res) - len(bad)}/{len(res)} files AST-identical after expansion')
for f, s, d in bad:
    print('---', s, f); print(d)
