"""Check both project budgets against Horn clauses from the input by decision diagrams."""
from bridge import *
from functools import lru_cache
def check(axis,root,limit):
 # Canonical ternary decision diagrams, one choice of mode per real job.
 nodes=[(32,0,0,0),(32,1,1,1)];unique={}
 def mk(i,kids):
  a,b,c=kids
  if a==b==c:return a
  key=(i,a,b,c)
  if key not in unique:unique[key]=len(nodes);nodes.append(key)
  return unique[key]
 @lru_cache(None)
 def op(is_or,a,b):
  if a>b:return op(is_or,b,a)
  if a==0:return b if is_or else 0
  if a==1:return 1 if is_or else b
  if a==b:return a
  x,y=nodes[a],nodes[b];level=min(x[0],y[0])
  return mk(level,[op(is_or,x[k] if x[0]==level else a,y[k] if y[0]==level else b) for k in (1,2,3)])
 @lru_cache(None)
 def forced(v):
  if v==1:return 1
  if 4167<=v<=4256:
   i,k=divmod(v-4167,3);return mk(i+2,[int(k==j) for j in range(3)])
  assert v in g,(root,v)
  acc=0
  for row in g[v]:
   both=1
   for l in row:both=op(False,both,forced(l))
   acc=op(True,acc,both)
  return acc
 @lru_cache(None)
 def exceed(i,left):
  if left<0:return 1
  if i==32:return 0
  return mk(i,[exceed(i+1,left-row[axis]) for row in m[i]])
 rootfn=forced(root);bad=exceed(2,limit)
 assert op(False,bad,rootfn)==bad,(axis,root,'overload can evade this cone')
 print('budget',limit,'unit',-root,'verified',len(nodes),'nodes')
for axis,root,cap in zip((3,4),roots[-2:],(161,128)):check(axis,root,cap)
