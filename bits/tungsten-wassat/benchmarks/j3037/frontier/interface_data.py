import sys
from pair_prices import *
a,b=map(int,sys.argv[1:]);ds,_=placements(a,b)
with open(f'interface-{a}-{b}.dat','w') as f:
 for j in jobs:
  print(len(succ[j]),*succ[j],file=f)
  for k in range(3):
   print(*m[j,k],len(ds[j,k]),*sorted(ds[j,k]),file=f)
