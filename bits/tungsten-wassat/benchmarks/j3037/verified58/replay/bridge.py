from pathlib import Path
import sys,re,collections,json
d=Path(__file__).resolve().parent;sys.path.insert(0,str(d.parent))
from data import cnf,m,succ
import itertools
cs=set(map(frozenset,cnf))
roots=[-r[0] for r in cnf if len(r)==1 and r[0]<0]; assert len(roots)==118
mode=lambda i,k:4167+3*(i-2)+k
for i in range(2,32):
 vs=[mode(i,k) for k in range(3)];assert frozenset(vs) in cs and all(frozenset([-a,-b]) in cs for a,b in itertools.combinations(vs,2))
blocks=[];start=2
for v in range(2,964):
 if frozenset([-v,v+1]) not in cs:blocks.append((start,v));start=v+1
assert len(blocks)==31
g=collections.defaultdict(list)
for row in cnf:
 pos=[l for l in row if l>0]
 if len(pos)==1 and pos[0]>4256:g[pos[0]].append(tuple(-l for l in row if l<0))
def cone(root):
 q=[root];seen=set();leaves=set()
 while q:
  v=q.pop()
  if v in seen:continue
  seen.add(v)
  if v in g:
   for row in g[v]:q.extend(row)
  else:leaves.add(v)
 return seen,leaves
locations=collections.defaultdict(set)
for n,root in enumerate(roots[:116]):
 for v in cone(root)[1]:locations[v].add(n//2)
gates=collections.defaultdict(list)
for row in cnf:
 if len(row)>=2 and 1032<=row[0]<=4166 and -4256<=row[1]<=-4167:gates[-row[1]].append((row[0],row[2:]))
offset={};activity={}
for i in range(2,32):
 for k,(dur,*_) in enumerate(m[i]):
  rows=sorted(gates[mode(i,k)]);off={t-j for j,(v,_) in enumerate(rows) for t in locations[v]}
  assert len(off)==1,(i,k,off)
  phi=off.pop();assert offset.get(i,phi)==phi;offset[i]=phi
  a,b=blocks[i-2]
  for j,(v,others) in enumerate(rows):
   t=phi+j;activity[i,k,t]=v
   required=[]
   if a<=a+j<=b:required.append(-(a+j))
   if a<=a+j-dur<=b:required.append(a+j-dur)
   assert frozenset([v,-mode(i,k)]+required) in cs,(i,k,t)

# Boundary cases that would overrun activity lanes or violate precedence need CNF checks as well.
def le(i,t):
 a,b=blocks[i-2];v=a+t-offset[i]
 return (False if v<a else True if v>b else v)
def guards(i,s):
 a=le(i,s-1); b=le(i,s)
 return ([] if a is False else [-a])+([] if b is True else [b])
assert (1,) in cnf

claims=set()
for i in range(2,32):
 a,b=blocks[i-2]
 for s in range(offset[i],offset[i]+b-a+2):
  for k,(dur,*_) in enumerate(m[i]):
   case=[mode(i,k),*guards(i,s)]
   if s+dur>58 or any((i,k,t) not in activity for t in range(s,s+dur)):
    claims.add(tuple(-v for v in case))
   for j in succ[i]:
    if j==32:continue
    too_early=le(j,s+dur-1)
    if too_early is False:continue
    cond=case if too_early is True else case+[too_early]
    claims.add(tuple(-v for v in cond))
with (d/'precedence.drat').open('w') as f:
 for row in sorted(claims,key=lambda r:(len(r),r)):print(*row,0,file=f)
print('clausal implications',len(claims))
