"""Reconstruct every bound used by the schedule enumerators from the PSPLIB input."""
from pathlib import Path
import sys,json
d=Path(__file__).resolve().parent
sys.path.insert(0,str(d.parent))
from data import m,succ
h=int(sys.argv[1]);f=iter((d/sys.argv[2]).read_text().split());slots=iter((d/sys.argv[3]).read_text().split())
activities=iter(map(int,(d.parent/'activities.txt').read_text().split()))
for i in range(1,33):
 assert [next(activities) for _ in range(next(activities))]==succ[i]
 assert [[next(activities) for _ in range(5)] for _ in range(next(activities))]==m[i]
assert next(activities,None) is None
parents={i:set() for i in m}
for i in m:
 for j in succ[i]:parents[j]|=parents[i]|{i}
patterns=[((),set(),0,0)]
for i in range(2,32):
 extra=[]
 for row,jobs,a,b in patterns:
  if jobs&parents[i]:continue
  for k,(_,ra,rb,_,_) in enumerate(m[i]):
   if a+ra<=17 and b+rb<=18:extra.append((row+(3*(i-2)+k,),jobs|{i},a+ra,b+rb))
 patterns.extend(extra)
patterns=[r for r,_,_,_ in patterns]
assert int(next(f))==h
n=int(next(f)); assert n>0
for _ in range(n):
 name=next(f);assert next(slots)==name
 wfile=d/name
 if not wfile.exists():wfile=d/'stretch'/name
 c=json.loads(wfile.read_text());w=c['weights'];assert len(w)==h
 cap=int(next(f));nlam=int(next(f));assert all(int(next(f))>=0 for _ in range(2*nlam))
 assert all(j in succ[i] and 0<=t<h and type(v)==int and v>=0 for i,j,t,v in c['precedence'])
 for i in range(2,32):
  for k,mode in enumerate(m[i]):
   dur=mode[0];z=3*(i-2)+k
   for st in range(h-dur+1):
    score=sum(w[t][z] for t in range(st,st+dur))
    score+=sum(v*(int(j==i and st<=t)-int(p==i and st+dur<=t)) for p,j,t,v in c['precedence'])
    assert int(next(f))==score
 total=0
 for wr in w:
  assert len(wr)==90 and all(type(v)==int and v>=0 for v in wr)
  cmax=max(sum(wr[z] for z in row) for row in patterns);assert int(next(slots))==cmax
  assert [int(next(slots)) for _ in wr]==wr;total+=cmax
 assert cap==total
assert next(slots,None) is None and next(f,None) is None
print('validated',n,'price profiles;',len(patterns),'patterns including empty at horizon',h)
