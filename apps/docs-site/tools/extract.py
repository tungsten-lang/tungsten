#!/usr/bin/env python3
"""Extract Tungsten stdlib docs (core/*.w) into JSON for the docs site.
usage: extract.py <checkout-root> <out-dir> <sha>"""
import json, os, re, sys
from collections import defaultdict

root, out, sha = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)

CLASS_RE = re.compile(r'^(\s*)\+ ([A-Z]\w*(?:::\w+)*)(<[^>]*>)?(?:\s*<\s*([A-Z][\w:]*(?:<[^>]*>)?))?\s*(?:#.*)?$')
TRAIT_RE = re.compile(r'^(\s*)trait ([A-Z]\w*)')
METH_RE = re.compile(r'^(\s*)(->|fn) (.+)$')
CONST_RE = re.compile(r'^\s*([A-Z][A-Z0-9_]{2,})\s*=\s*(.+)$')
DIVIDER_RE = re.compile(r'^#\s*[-=─]{2,}\s*(.*?)\s*[-=─]*\s*$')
ALIAS_RE = re.compile(r'^\s*alias\s+:?([^\s,]+),?\s+:?(\S+)')


def indent_of(s):
    return len(s) - len(s.lstrip(' '))


def strip_comment(lines):
    res = []
    for l in lines:
        t = l.strip()
        t = t[1:] if t.startswith('#') else t
        res.append(t[1:] if t.startswith(' ') else t)
    while res and not res[0].strip():
        res.pop(0)
    while res and not res[-1].strip():
        res.pop()
    return '\n'.join(res)


def split_sig(sig):
    """'name(a, b)  # note' -> (name, params, note)"""
    note = ''
    depth, instr = 0, False
    for i, ch in enumerate(sig):
        if ch == '"':
            instr = not instr
        elif not instr:
            if ch in '([':
                depth += 1
            elif ch in ')]':
                depth -= 1
            elif ch == '#' and depth == 0 and i > 0 and sig[i - 1] == ' ':
                note = sig[i + 1:].strip()
                sig = sig[:i].rstrip()
                break
    m = re.match(r'^((?:self)?\.)?(\[\]=?|[^\s(/]+|/)(.*)$', sig)
    if not m:
        return sig, '', note, False
    return m.group(2), m.group(3).strip(), note, bool(m.group(1))


classes = {}     # name -> dict
functions = []   # top-level fns
files = {}


def get_class(name, kind):
    c = classes.get(name)
    if not c:
        c = classes[name] = dict(name=name, kind=kind, parent=None, generic=None, traits=[], doc='',
                                 files=[], methods=[], consts=[], fields=[], aliases=[], outer=None)
    return c


core = os.path.join(root, 'core')
paths = []
for d, _, fs in os.walk(core):
    for f in fs:
        if f.endswith('.w'):
            paths.append(os.path.join(d, f))
paths.sort()

autoload = {}
total_lines = 0
for path in paths:
    rel = os.path.relpath(path, root)
    lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    total_lines += len(lines)
    if rel == 'core/tungsten.w':
        for l in lines:
            m = re.match(r'^\s*auto :(\w+),\s*"([^"]+)"', l)
            if m:
                autoload[m.group(1)] = m.group(2)
    # file header
    h = 0
    while h < len(lines) and lines[h].startswith('#'):
        h += 1
    files[rel] = dict(lines=len(lines))
    stack = []  # (indent, class dict)
    section = ''
    n = len(lines)
    i = 0
    while i < n:
        line = lines[i]
        s = line.strip()
        if not s:
            i += 1
            continue
        ind = indent_of(line)
        if not s.startswith('#'):
            while stack and ind <= stack[-1][0]:
                stack.pop()
                section = ''
        # preceding comment block
        def doc_above(idx, at_indent):
            j = idx - 1
            buf = []
            while j >= 0 and lines[j].strip().startswith('#') and indent_of(lines[j]) == at_indent:
                buf.append(lines[j])
                j -= 1
            buf.reverse()
            buf = [b for b in buf if not DIVIDER_RE.match(b.strip()) and not re.match(r'^#\s*@author', b.strip())]
            return strip_comment(buf)

        if s.startswith('#'):
            dm = DIVIDER_RE.match(s)
            if dm and dm.group(1) and stack:
                section = dm.group(1).strip(' -=─')
            i += 1
            continue
        cm = CLASS_RE.match(line) or None
        tm = TRAIT_RE.match(line)
        if cm or tm:
            if cm:
                name, generic, parent = cm.group(2), cm.group(3), cm.group(4)
                c = get_class(name, 'class')
                if parent and not c['parent']:
                    c['parent'] = parent
                if generic:
                    c['generic'] = generic
            else:
                name = tm.group(2)
                c = get_class(name, 'trait')
                c['kind'] = 'trait'
            if stack and not c['outer']:
                c['outer'] = stack[-1][1]['name']
            d = doc_above(i, ind)
            if len(d) > len(c['doc']):
                c['doc'] = d
            c['files'].append([rel, i + 1])
            stack.append((ind, c))
            section = ''
            i += 1
            continue
        mm = METH_RE.match(line)
        if mm and (not stack or ind == stack[-1][0] + 2):
            name, params, note, is_class = split_sig(mm.group(3))
            # body extent
            j = i + 1
            last = i
            while j < n:
                t = lines[j]
                if t.strip():
                    if indent_of(t) <= ind:
                        break
                    last = j
                j += 1
            body_lines = [x for x in lines[i + 1:last + 1] if x.strip() and not x.strip().startswith('#')]
            doc = doc_above(i, ind)
            if note:
                doc = (note + ('\n\n' + doc if doc else ''))
            rec = dict(n=name, p=params, d=doc, f=rel, l=i + 1, e=last + 1)
            if is_class:
                rec['c'] = 1
            if not body_lines:
                if name == 'new' and '@' in params:
                    rec['b'] = 1  # bodiless constructor that binds @-params straight to fields
                else:
                    rec['a'] = 1
            if mm.group(2) == 'fn':
                rec['fn'] = 1
            if section:
                rec['s'] = section
            gm = re.search(r'^\s*@(gpu|fastmath|strictmath|inline|pure)\b', lines[i - 1]) if i else None
            if gm:
                rec['t'] = gm.group(1)
            if stack:
                stack[-1][1]['methods'].append(rec)
                mk = re.match(r'^(.*\))\s+(ro|rw)$', params)
                if mk and name == 'new':
                    rec['p'] = mk.group(1)
                    for fld in re.findall(r'@([a-z_]\w*)', mk.group(1)):
                        stack[-1][1]['methods'].append(dict(n=fld, p='', f=rel, l=i + 1, e=i + 1, acc=mk.group(2),
                                                            d='Generated by the trailing `%s` on the constructor.' % mk.group(2)))
            else:
                functions.append(rec)
            i = last + 1 if body_lines else i + 1
            continue
        if stack and ind == stack[-1][0] + 2:
            c = stack[-1][1]
            m = re.match(r'^(is|with)\s+([A-Z]\w*)', s)
            if m and m.group(2) not in c['traits']:
                c['traits'].append(m.group(2))
            m = CONST_RE.match(line)
            if m and len(c['consts']) < 60:
                c['consts'].append([m.group(1), m.group(2)[:120], i + 1])
            m = re.match(r'^(ro|rw)\s+(:.*)$', s)
            if m:
                decl, _, trailing = m.group(2).partition('#')
                doc = trailing.strip() or doc_above(i, ind)
                for fld in re.findall(r':([A-Za-z_]\w*)', decl.split('{')[0]):
                    rec = dict(n=fld, p='', d=doc, f=rel, l=i + 1, e=i + 1, acc=m.group(1))
                    if section:
                        rec['s'] = section
                    c['methods'].append(rec)
            m = re.match(r'^(field|readonly)\s+(.+)$', s)
            if m:
                c['fields'].append([m.group(1), m.group(2)[:100]])
            m = ALIAS_RE.match(line)
            if m:
                c['aliases'].append([m.group(1), m.group(2)])
            m = re.match(r'^runtime\s+(:.+)$', s)
            if m:
                for nm in re.findall(r':([^\s,]+)', m.group(1)):
                    c['methods'].append(dict(n=nm, p='', d='Implemented natively by the runtime.', f=rel, l=i + 1, e=i + 1, a=1, rt=1))
            if s.startswith('- data'):
                j = i + 1
                buf = []
                while j < n and (not lines[j].strip() or indent_of(lines[j]) > ind):
                    if lines[j].strip():
                        buf.append(lines[j][ind + 2:] if len(lines[j]) > ind + 2 else lines[j].strip())
                    j += 1
                c['layout'] = s + '\n' + '\n'.join(buf[:40])
                i = j
                continue
        i += 1
    # attribute header doc to primary class of file if it has none
    header = strip_comment([l for l in lines[:h] if not re.match(r'^#\s*@author', l)])
    files[rel]['doc'] = header[:6000]

# ---- examples from specs and doc/examples ----
name_owner = defaultdict(set)
for c in classes.values():
    for m in c['methods']:
        name_owner[m['n']].add(c['name'])

ex_files = []
for base in ('spec', 'doc/examples'):
    for d, _, fs in os.walk(os.path.join(root, base)):
        for f in fs:
            if f.endswith('.w'):
                ex_files.append(os.path.join(d, f))
ex_files.sort()

examples = defaultdict(list)     # "Class#meth" -> [[file, line, text]]
class_specs = defaultdict(list)  # Class -> [spec rel]
file_to_classes = defaultdict(list)
for c in classes.values():
    for f, _ in c['files']:
        file_to_classes[f].append(c['name'])
CALL_RE = re.compile(r'(?:\b([A-Z]\w*))?\.([a-z_]\w*[?!]?)')
gallery = []
for path in ex_files:
    rel = os.path.relpath(path, root)
    try:
        lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        continue
    if rel.startswith('doc/examples'):
        title = ''
        for l in lines[:6]:
            if l.startswith('#') and l.strip('# ').strip() and not l.strip('# ').startswith(('expect', '@', 'Run', 'usage')):
                title = l.strip('# ').strip()
                break
        gallery.append([rel, title[:140], len(lines)])
    used = set()
    for l in lines[:40]:
        m = re.match(r'^use (core/[\w/]+)', l)
        if m:
            used.update(file_to_classes.get(m.group(1) + '.w', []))
    mentioned = set()
    for idx, l in enumerate(lines):
        t = l.strip()
        if not t or t.startswith('#') or len(t) > 160:
            continue
        for cm in CALL_RE.finditer(t):
            recv, meth = cm.group(1), cm.group(2)
            owners = name_owner.get(meth)
            if not owners:
                continue
            owner = None
            if recv and recv in owners:
                owner = recv
            elif len(owners) == 1 and len(meth) >= 5:
                owner = next(iter(owners))
            elif len(owners) > 1:
                cand = owners & used
                if len(cand) == 1:
                    owner = next(iter(cand))
            if owner:
                key = owner + '#' + meth
                lst = examples[key]
                if len(lst) < 3 and all(x[2] != t for x in lst):
                    lst.append([rel, idx + 1, t])
                mentioned.add(owner)
    if rel.startswith('spec/'):
        for cn in used | {c for c in mentioned if rel.split('/')[-1].startswith(re.sub(r'(?<!^)(?=[A-Z])', '_', c).lower())}:
            if len(class_specs[cn]) < 12:
                class_specs[cn].append(rel)

# ---- assemble ----
children = defaultdict(list)
for c in classes.values():
    if c['parent']:
        children[re.sub(r'<.*', '', c['parent'])].append(c['name'])
    # header doc fallback
    if not c['doc'] and c['files']:
        f = c['files'][0][0]
        prim = file_to_classes[f][0] if file_to_classes[f] else None
        if prim == c['name']:
            pass
for f, names in file_to_classes.items():
    c = classes[names[0]]
    if not c['doc']:
        c['doc'] = files[f].get('doc', '')

out_classes = []
for c in sorted(classes.values(), key=lambda c: c['name'].lower()):
    c['auto'] = autoload.get(c['name'])
    c['children'] = sorted(children.get(c['name'], []))
    c['specs'] = class_specs.get(c['name'], [])
    for m in c['methods']:
        ex = examples.get(c['name'] + '#' + m['n'])
        if ex:
            m['x'] = ex
    top = c['files'][0][0].split('/')
    c['area'] = top[1] if len(top) > 2 else 'core'
    out_classes.append({k: v for k, v in c.items() if v not in (None, [], '')})

meta = dict(sha=sha, note=(sys.argv[4] if len(sys.argv) > 4 else ''), files=len(paths), lines=total_lines, classes=len(out_classes),
            methods=sum(len(c.get('methods', [])) for c in out_classes) + len(functions),
            traits=sum(1 for c in out_classes if c['kind'] == 'trait'),
            accessors=sum(1 for c in out_classes for m in c.get('methods', []) if m.get('acc')),
            examples=sum(len(v) for v in examples.values()), autoloaded=len(autoload))
data = dict(meta=meta, classes=out_classes, functions=functions, gallery=gallery)
p = os.path.join(out, 'docs.json')
json.dump(data, open(p, 'w'), ensure_ascii=False, separators=(',', ':'))
print(json.dumps(meta), os.path.getsize(p))
