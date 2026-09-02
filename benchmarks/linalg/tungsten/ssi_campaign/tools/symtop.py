#!/usr/bin/env python3
# symtop.py <sidemap> <N> <sample.txt>... : merge "Sort by top of stack" self-samples, symbolize __wy_ frames
import sys, re, json, collections
sidemap = json.load(open(sys.argv[1]))
names = {}
for k, v in sidemap.get("hashes", sidemap).items():
    if isinstance(v, dict) and 'symbol' in v:
        orig = v.get('originals', [{}])[0]
        cls, meth = orig.get('class', ''), orig.get('method', orig.get('symbol', ''))
        names[v['symbol']] = f"{cls}#{meth}" if cls else meth
N = int(sys.argv[2]); tot = collections.Counter(); grand = 0
for f in sys.argv[3:]:
    txt = open(f).read()
    sec = txt.split("Sort by top of stack")[1] if "Sort by top of stack" in txt else ""
    for line in sec.splitlines():
        m = re.match(r'\s+(\S+)\s+\(in [^)]*\)\s+(\d+)$', line)
        if m: tot[m.group(1)] += int(m.group(2)); grand += int(m.group(2))
print(f"self-samples total {grand}")
for sym, c in tot.most_common(N):
    print(f"{100*c/grand:6.1f}%  {names.get(sym, sym)}")
