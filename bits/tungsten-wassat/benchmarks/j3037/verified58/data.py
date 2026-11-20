from pathlib import Path
import re,itertools
d=Path(__file__).resolve().parent
p=d/'input.cnf'
cnf=[tuple(map(int,l.split()[:-1])) for l in p.read_text().splitlines()[1:]]
s=(d/'job.mm').read_text()
succ={};m={}
for l in s.split('PRECEDENCE RELATIONS:')[1].split('REQUESTS/DURATIONS:')[0].splitlines():
 if re.match(r'^\s*\d',l):
  i,_,_,*a=map(int,l.split());succ[i]=a
for l in s.split('REQUESTS/DURATIONS:')[1].split('RESOURCEAVAILABILITIES:')[0].splitlines():
 if re.match(r'^\s*\d',l):
  a=list(map(int,l.split()))
  if len(a)==7:i=a.pop(0);m[i]=[]
  m[i].append(a[1:])
es={i:0 for i in m};tail={}
for i in m:
 for j in succ[i]:es[j]=max(es[j],es[i]+min(x[0] for x in m[i]))
for i in reversed(m):tail[i]=min(x[0] for x in m[i])+max((tail[j] for j in succ[i]),default=0)
