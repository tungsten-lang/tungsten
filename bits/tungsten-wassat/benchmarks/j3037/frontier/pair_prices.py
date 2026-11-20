"""Integer price bounds on the remaining 52 pairs, with mandatory occupants in each slot."""
from pathlib import Path
import numpy as np
import sys
project = Path(__file__).resolve().parents[1] / "verified58"
sys.path.insert(0, str(project))
from data import m as modes, succ
m = {(j,k): mode for j,ms in modes.items() for k,mode in enumerate(ms)}
anc = {j:set() for j in succ}
for j in sorted(succ):
 for child in succ[j]:anc[child].update(anc[j] | {j})
from functools import cache
import json
fixed_modes={2:0,3:1,4:2,7:2,8:0,12:2}
jobs=range(2,32)
def placements(a,b):
 fixed={2:0,3:0,4:0,7:a,8:b}
 dom={}
 for j in jobs:
  for k in range(3):
   length,r,s,*_=m[j,k]
   dom[j,k]={t for t in range(59-length)
    if (j not in fixed_modes or fixed_modes[j]==k) and (j not in fixed or t==fixed[j])}
 for t in range(58):
  here=[i for i in fixed if fixed[i]<=t<fixed[i]+m[i,fixed_modes[i]][0]]
  for (j,k),starts in dom.items():
   if j in fixed:continue
   length,r,s,*_=m[j,k]
   if r+sum(m[i,fixed_modes[i]][1] for i in here)>17 or s+sum(m[i,fixed_modes[i]][2] for i in here)>18:
    starts.difference_update(range(t-length+1,t+1))
 for i in jobs:
  end=min(t+m[i,k][0] for k in range(3) for t in dom[i,k])
  for j in succ[i]:
   if j in jobs:
    for k in range(3):dom[j,k].difference_update(range(end))
 for i in reversed(jobs):
  latest=min((max(t for k in range(3) for t in dom[j,k]) for j in succ[i] if j in jobs),default=58)
  for k in range(3):dom[i,k].difference_update(range(latest-m[i,k][0]+1,59))
 return dom,fixed
rows=[((),set(),0,0)]
for j in jobs:
 rows.extend([(row+(3*(j-2)+k,),js|{j},u+r,v+s) for row,js,u,v in rows if not js&anc[j]
              for k in range(3) for _,r,s,*_ in [m[j,k]] if u+r<=17 and v+s<=18 and (j not in fixed_modes or fixed_modes[j]==k)])
pm=np.zeros((len(rows),90),dtype=np.int16)
for idx,(row,*_) in enumerate(rows):pm[idx,list(row)]=1
base=project/'replay'
files=iter((base/'selprice58.txt').read_text().split());h,n=map(int,[next(files),next(files)])
prices=[]
for _ in range(n):
 name=next(files);cap,nlam=int(next(files)),int(next(files))
 for v in range(2*nlam):next(files)
 work={(i,k):np.array([int(next(files)) for _ in range(59-m[i,k][0])]) for i in jobs for k in range(3)}
 paths=list(base.rglob(name))
 w=np.array(json.loads(paths[0].read_text())['weights'])
 prices.append((name,work,pm@w.T))
inf=10**12
def check(a,b):
 dom,fixed=placements(a,b)
 slot=[]
 for t in range(58):
  can=np.array([any(t-m[j,k][0]<x<=t for x in dom[j,k]) for j in jobs for k in range(3)])
  must=[3*(j-2)+fixed_modes[j] for j,s in fixed.items() if s<=t<s+m[j,fixed_modes[j]][0]]
  valid=~np.any(pm[:,~can],axis=1) & np.all(pm[:,must],axis=1)
  slot.append(np.flatnonzero(valid))
 best=None
 for name,work,charges in prices:
  cap=sum(int(charges[ids,t].max()) for t,ids in enumerate(slot))
  dp=np.zeros((162,129),dtype=np.int64)
  for j in jobs:
   after=np.full_like(dp,inf)
   for k in range(3):
    if not dom[j,k]:continue
    *_,r,s=m[j,k]
    dst=after[r:,s:]
    np.minimum(dst,dp[:162-r,:129-s]+int(work[j,k][list(dom[j,k])].min()),out=dst)
   dp=after
  lower=int(dp[-1,-1]);cand=(lower-cap,name,lower,cap)
  if best is None or cand>best:best=cand
 return best
if __name__=='__main__':
 for a in range(10,18):
  for b in range(a+9,29):print(a,b,*check(a,b),flush=True)
