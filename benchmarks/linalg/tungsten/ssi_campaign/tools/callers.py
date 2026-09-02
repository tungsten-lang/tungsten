#!/usr/bin/env python3
# callers.py <sidemap> <leaf-regex> <sample.txt>...: attribute leaf samples to nearest tungsten (__wy_) ancestor
import sys, re, json, collections
d = json.load(open(sys.argv[1])); names = {}
for k, v in d.get('hashes', d).items():
    o = v.get('originals', [{}])[0]; names[v['symbol']] = f"{o.get('class','')}#{o.get('method', o.get('symbol',''))}"
leaf = re.compile(sys.argv[2]); tot = collections.Counter(); grand = 0
for f in sys.argv[3:]:
    txt = open(f).read().split("Call graph:")[1].split("Total number in stack")[0]
    stack = []  # (depth, symbol)
    for line in txt.splitlines():
        m = re.match(r'^(\s*)[+!:|\s]*?(\d+)\s+(\S+)\s+\(in ', line)
        if not m: continue
        depth = len(line) - len(line.lstrip(' +!:|')); cnt = int(m.group(2)); sym = m.group(3)
        while stack and stack[-1][0] >= depth: stack.pop()
        stack.append((depth, sym))
        if leaf.search(sym):
            anc = next((s for dd, s in reversed(stack[:-1]) if s.startswith('__wy_')), '?')
            tot[anc] += cnt; grand += cnt
print(f"leaf '{sys.argv[2]}' samples {grand}")
for s, c in tot.most_common(10): print(f"{100*c/grand:6.1f}%  {names.get(s, s)}")
