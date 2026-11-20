"""Bit-parallel check of renewable overloads against original Horn clauses."""
from bridge import *
from functools import lru_cache
anc={i:set() for i in m}
for i in m:
 for j in succ[i]:anc[j].update(anc[i]|{i})
# Any overloaded simultaneous antichain contains a first overloaded prefix.
violations=[]
def prefix(start,jobs,terms,r,s):
 for i in range(start,32):
  if jobs&anc[i]:continue
  for k,(_,a,b,_,_) in enumerate(m[i]):
   z=terms+((i-2)*3+k,);nr=r+a;ns=s+b
   if nr>17 or ns>18:
    # Test minimal overloads only. Strict subsets that overload have their own test.
    if all(nr-m[2+v//3][v%3][1]<=17 and ns-m[2+v//3][v%3][2]<=18 for v in z):violations.append(z)
   else:prefix(i+1,jobs|{i},z,nr,ns)
prefix(2,set(),(),0,0)
print('minimal overloaded patterns',len(violations),flush=True)
exceptions=set();tests=0
for ix in range(0,len(violations),2048):
 chunk=violations[ix:ix+2048];word=(1<<len(chunk))-1
 flags=[0]*90
 for j,row in enumerate(chunk):
  for z in row:flags[z]|=1<<j
 for t in range(58):
  bits={1:word};valid=word
  for z,mask in enumerate(flags):
   v=activity.get((2+z//3,z%3,t))
   if v is None:valid&=~mask
   else:bits[v]=mask
  @lru_cache(None)
  def forced(v):
   if v in bits:return bits[v]
   if v not in g:return 0
   total=0
   for row in g[v]:
    term=word
    for dep in row:term&=forced(dep)
    total|=term
   return total
  forced_roots=forced(roots[2*t])|forced(roots[2*t+1])
  missing=valid&~forced_roots
  while missing:
   bit=missing&-missing;missing-=bit
   exceptions.add(tuple(-activity[2+z//3,z%3,t] for z in chunk[bit.bit_length()-1]))
  tests+=valid.bit_count()
print('verified',tests,'overload and slot combinations')

with (d/'resource-overloads.drat').open('w') as f:
 for row in sorted(exceptions,key=lambda r:(len(r),r)):print(*row,0,file=f)
print('exceptional clauses for independent checking',len(exceptions))
