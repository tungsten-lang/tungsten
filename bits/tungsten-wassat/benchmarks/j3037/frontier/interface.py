"""Enumerate possible before/during/after states at job 8's execution slot."""
from pair_prices import placements, rows, m, succ, jobs
from collections import Counter
from itertools import product
from functools import cache
import sys
a,b=map(int,sys.argv[1:3]);dom,_=placements(a,b)
parents={i:[j for j in jobs if i in succ[j]] for i in jobs}
def phase(j,k,t): return 0 if t+m[j,k][0]<=b else 2 if t>b else 1
opts={(j,k):{phase(j,k,t) for t in ts} for (j,k),ts in dom.items()}
phases={j:set.union(*(opts[j,k] for k in range(3))) for j in jobs}
# Enumerate the potential occupants with concrete modes before extending the prefix ideal.
patterns=[{q//3+2:q%3 for q in row} for row,*_ in rows if 18 in row and all(1 in opts[q//3+2,q%3] for q in row)]
def states(active):
 before=after=0
 for j in reversed(jobs):
  bit=1<<j
  if j in active or before&bit or 2 not in phases[j]:
   if j not in active and 0 not in phases[j]:return
   if j in active and before&bit:return
   if j not in active:before|=bit
   for i in parents[j]:before|=1<<i
 for j in jobs:
  bit=1<<j
  if j in active or after&bit or 0 not in phases[j]:
   if j not in active and 2 not in phases[j]:return
   if j in active and after&bit:return
   if j not in active:after|=bit
   for i in succ[j]:after|=1<<i
 if before&after:return
 free=[j for j in jobs if j not in active and not ((before|after)>>j&1)]
 def extend(p,finished):
  if p==len(free):
   yield finished
   return
  j=free[p]
  yield from extend(p+1,finished)
  if all(finished>>i&1 for i in parents[j]):yield from extend(p+1,finished|1<<j)
 yield from extend(0,before)
out=open(f'interface-{a}-{b}.states','w');count=Counter()
for act in patterns:
 for mask in states(act):
  count[len(act)]+=1
  print(mask,*[3*(j-2)+k for j,k in act.items()],file=out)
out.close()
print(a,b,'mode patterns',len(patterns),'states',sum(count.values()),'by active jobs',dict(count))
