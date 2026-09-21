#!/usr/bin/env python3
"""Replace Ruby-style trivial accessors with class-level `ro` / `rw` declarations.

    -> certificate          =>   ro :certificate
      @certificate

    -> note       + -> note=(v)      =>   rw :note
      @note           @note = v

usage: ro_codemod.py [--write] [--manifest out.json] <file-or-dir>...

Rules (all conservative; anything unusual is reported and left alone):
  * only inside a `+ Class` body, only `-> name` with no params whose whole body is `@name`
    (or `return @name`), name without ?/!
  * adjacent undocumented getters merge into one `ro :a, :b` line (order preserved, <= 100 cols)
  * a getter with a doc comment above, or a trailing comment, keeps it on its own `ro :name` line
  * a trivial setter for the same field in the same class upgrades it to `rw` and is removed
"""
import json, os, re, sys

GETTER = re.compile(r'^(\s*)-> ([a-z_][A-Za-z0-9_]*)\s*(#.*)?$')
SETTER = re.compile(r'^(\s*)-> ([a-z_][A-Za-z0-9_]*)=\(([a-z_]\w*)\)\s*(#.*)?$')
CLASS = re.compile(r'^(\s*)\+ [A-Z]')
DIVIDER = re.compile(r'^#\s*[-=─]{2,}')
DECL = re.compile(r'^\s*(ro|rw)\s+(.*)$')
CTOR_MARK = re.compile(r'^\s*-> new\b.*\)\s*(ro|rw)\s*(#.*)?$')
WIDTH = 100


def indent(s):
    return len(s) - len(s.lstrip(' '))


def is_code(s):
    t = s.strip()
    return bool(t) and not t.startswith('#')


def split_comment(s):
    m = re.match(r'^(.*?)(\s+#.*)?$', s)
    return m.group(1).rstrip(), (m.group(2) or '').strip()


def block_end(L, i, ind):
    """index of last line belonging to the block opened at line i (deeper-indented or blank-inside)."""
    last = i
    j = i + 1
    while j < len(L):
        if L[j].strip():
            if indent(L[j]) <= ind:
                break
            last = j
        j += 1
    return last


def class_of(L, i, ind):
    """header line index of the enclosing `+ Class`, or None when the getter is not directly in one."""
    j = i - 1
    while j >= 0:
        if is_code(L[j]) and indent(L[j]) < ind:
            m = CLASS.match(L[j])
            return j if m and indent(L[j]) == ind - 2 else None
        j -= 1
    return None


def transform(text, report, path):
    L = text.split('\n')
    getters, setters = [], []
    for i, line in enumerate(L):
        g = GETTER.match(line)
        if g:
            ind, name = len(g.group(1)), g.group(2)
            end = block_end(L, i, ind)
            body = [x for x in L[i + 1:end + 1] if x.strip()]
            if len(body) != 1:
                continue
            code, bcomment = split_comment(body[0].strip())
            if code not in ('@' + name, 'return @' + name):
                continue
            hdr = class_of(L, i, ind)
            if hdr is None:
                report.append((path, i + 1, name, 'not directly inside a + Class body'))
                continue
            comment = (g.group(3) or bcomment or '').strip()
            getters.append(dict(i=i, end=end, ind=ind, name=name, hdr=hdr, comment=comment))
            continue
        s = SETTER.match(line)
        if s:
            ind, name, arg = len(s.group(1)), s.group(2), s.group(3)
            end = block_end(L, i, ind)
            body = [x.strip() for x in L[i + 1:end + 1] if x.strip()]
            if body == ['@%s = %s' % (name, arg)] and not s.group(4):
                hdr = class_of(L, i, ind)
                if hdr is not None:
                    setters.append(dict(i=i, end=end, ind=ind, name=name, hdr=hdr))
    if not getters:
        return text, []

    # per-class facts: existing declarations, duplicate definitions, ctor markers
    ok = []
    for g in getters:
        hdr, ind = g['hdr'], g['ind']
        cend = block_end(L, hdr, indent(L[hdr]))
        body = L[hdr + 1:cend + 1]
        declared, dup, marker = set(), 0, False
        for x in body:
            if indent(x) == ind:
                d = DECL.match(x)
                if d:
                    declared.update(re.findall(r':?([a-z_]\w*)', split_comment(d.group(2))[0]))
                if CTOR_MARK.match(x):
                    marker = True
                m = GETTER.match(x) or re.match(r'^(\s*)-> (%s)[(/]' % re.escape(g['name']), x)
                if m and m.group(2) == g['name']:
                    dup += 1
        if g['name'] in declared:
            report.append((path, g['i'] + 1, g['name'], 'already declared by ro/rw'))
        elif dup > 1:
            report.append((path, g['i'] + 1, g['name'], 'defined more than once in the class'))
        elif marker:
            report.append((path, g['i'] + 1, g['name'], 'constructor carries a trailing ro/rw marker'))
        else:
            ok.append(g)
    getters = ok
    by_key = {(g['hdr'], g['name']): g for g in getters}
    drop = []
    for s in setters:
        g = by_key.get((s['hdr'], s['name']))
        if g:
            g['rw'] = True
            drop.append(s)

    # runs of getters separated only by blank lines
    getters.sort(key=lambda g: g['i'])
    runs, cur = [], []
    for g in getters:
        if cur and g['hdr'] == cur[-1]['hdr'] and all(not L[k].strip() for k in range(cur[-1]['end'] + 1, g['i'])):
            cur.append(g)
        else:
            if cur:
                runs.append(cur)
            cur = [g]
    if cur:
        runs.append(cur)

    edits = []  # (start, end_inclusive, replacement lines)
    for run in runs:
        pad = ' ' * run[0]['ind']
        out, pending = [], []

        def flush():
            line = ''
            for n in pending:
                piece = ':' + n
                if not line:
                    line = pad + 'ro ' + piece
                elif len(line) + 2 + len(piece) > WIDTH:
                    out.append(line)
                    line = pad + 'ro ' + piece
                else:
                    line += ', ' + piece
            if line:
                out.append(line)
            pending.clear()

        above = L[run[0]['i'] - 1].strip() if run[0]['i'] > 0 else ''
        documented = above.startswith('#') and not DIVIDER.match(above) and indent(L[run[0]['i'] - 1]) == run[0]['ind']
        for k, g in enumerate(run):
            alone = g.get('rw') or g['comment'] or (k == 0 and documented)
            if alone:
                flush()
                out.append(pad + ('rw' if g.get('rw') else 'ro') + ' :' + g['name'] + ('  ' + g['comment'] if g['comment'] else ''))
                if k == 0 and documented and len(run) > 1:
                    out.append('')
            else:
                pending.append(g['name'])
        flush()
        edits.append((run[0]['i'], run[-1]['end'], out))
    for s in drop:
        a, b = s['i'], s['end']
        if a > 0 and not L[a - 1].strip() and (b + 1 >= len(L) or not L[b + 1].strip()):
            a -= 1  # swallow one of the two blank lines left behind
        edits.append((a, b, []))

    for a, b, rep in sorted(edits, key=lambda e: -e[0]):
        L[a:b + 1] = rep
    changes = [dict(name=g['name'], rw=bool(g.get('rw')), line=g['i'] + 1) for g in getters]
    return '\n'.join(L), changes


def main():
    args = sys.argv[1:]
    write = '--write' in args
    manifest = None
    if '--manifest' in args:
        manifest = args[args.index('--manifest') + 1]
    paths = [a for a in args if not a.startswith('--') and a != manifest]
    exts = ('.w', '.md')
    files = []
    for p in paths:
        if os.path.isfile(p):
            files.append(p)
        for d, ds, fs in os.walk(p):
            ds[:] = [x for x in ds if x not in ('.git', '.claude', 'node_modules', 'build', 'tmp', 'tmp_ll', 'vendor')]
            files += [os.path.join(d, f) for f in fs if f.endswith(exts)]
    report, result, total = [], {}, 0
    for f in sorted(set(files)):
        try:
            text = open(f, encoding='utf-8').read()
        except (UnicodeDecodeError, OSError):
            continue
        new, changes = transform(text, report, f)
        if changes and new != text:
            result[f] = changes
            total += len(changes)
            if write:
                open(f, 'w', encoding='utf-8').write(new)
    for r in report:
        print('SKIP %s:%d %s — %s' % r)
    print('%s %d accessors in %d files (%d rw)' % ('rewrote' if write else 'would rewrite', total, len(result), sum(c['rw'] for v in result.values() for c in v)))
    if manifest:
        json.dump(result, open(manifest, 'w'), indent=1)


main()
