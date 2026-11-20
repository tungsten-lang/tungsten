"""Replay the projection from DIMACS and the exhaustive 58-slot scheduling certificate."""
from pathlib import Path
from hashlib import sha256
import itertools,json,os,subprocess,sys,tempfile
root=Path(__file__).resolve().parent
src=root/'replay'
if not __debug__:raise RuntimeError('run Python with assertions enabled')
expected='6d6a406144bf3d3e20efa43e79395612596ac413efba1fac5b59f190c43cff79'
assert sha256((root/'input.cnf').read_bytes()).hexdigest()==expected
from data import cnf,m,succ,s
assert len(cnf)==83276 and max(abs(v) for c in cnf for v in c)==18420
assert [line.split() for line in s.split('RESOURCEAVAILABILITIES:')[-1].splitlines() if line.strip()[:1].isdigit()]==[['17','18','161','128']]
assert set(m)==set(range(1,33)) and all(j>i for i in succ for j in succ[i])
assert m[1]==m[32]==[[0,0,0,0,0]]
assert all(len(m[i])==3 and all(row[0]>0 and all(a>=0 for a in row) for row in m[i]) for i in range(2,32))
witness=[list(map(int,l.split())) for l in (root/'schedule-best.txt').read_text().splitlines()]
assert sorted(i for i,t,k in witness)==list(range(1,33))
assert all(t>=0 and k in range(len(m[i])) for i,t,k in witness)
start={i:t for i,t,k in witness};end={i:t+m[i][k][0] for i,t,k in witness}
assert max(end.values())==59 and all(end[i]<=start[j] for i in m for j in succ[i])
for a,lim in ((1,17),(2,18)):
 assert all(sum(m[i][k][a] for i,t,k in witness if t<=s0<end[i])<=lim for s0 in range(59))
for a,lim in ((3,161),(4,128)):assert sum(m[i][k][a] for i,t,k in witness)<=lim
print('Verified the 59-slot upper bound.',flush=True)

def run(*args):subprocess.run(list(args),check=True)
run(sys.executable,src/'nonrenew.py')
run(sys.executable,src/'renew.py')
run(sys.executable,src/'audit-prices.py','58','selprice58.txt','selcap58.txt')
with tempfile.TemporaryDirectory() as tmp:
 tmp=Path(tmp);cc=os.environ.get('CXX','c++')
 for name in ('check-claims','verify-tree'):
  run(cc,'-std=c++17','-O3',src/(name+'.cpp'),'-o',tmp/name)
 run(tmp/'check-claims',root/'input.cnf',src/'precedence.drat',src/'resource-overloads.drat')
 cases=json.loads((root/'cases.json').read_text());domains=[]
 for case in cases:
  fixes={int(i):k for i,k in case['modes'].items()}
  assert all(i in range(2,32) and type(k)==int and k in range(3) for i,k in fixes.items())
  domains.append(fixes)
 for a,b in itertools.combinations(domains,2):
  assert any(a[i]!=b[i] for i in a.keys()&b.keys()),'overlapping branches'
 assert sum(3**(30-len(x)) for x in domains)==3**30,'incomplete partition'
 for case,fix in zip(cases,domains):
  print('Checking',case['trace'],flush=True)
  run(tmp/'verify-tree',root/'activities.txt',src/'selprice58.txt',src/'selcap58.txt',root/'traces'/case['trace'],
      *(str(v) for pair in sorted(fix.items()) for v in pair))
print('VERIFIED UNSAT at horizon 58 by scheduling projection and exhaustive event certificates.',flush=True)
