#!/usr/bin/env python3
"""Focused compiled-CLI conversion, assignment, alias and proof-boundary gates."""
import argparse
import itertools
import json
from pathlib import Path
import subprocess
import tempfile


def run(solver, checker, out):
    out.mkdir(parents=True,exist_ok=False)
    observations=[]
    def call(args, code=0):
        p=subprocess.run(list(map(str,args)),text=True,capture_output=True,timeout=10)
        observations.append(dict(argv=list(map(str,args)),code=p.returncode,stdout=p.stdout,stderr=p.stderr))
        assert p.returncode==code,observations[-1]
        return p.stdout
    def parse(text):
        lines=[s for s in text.splitlines() if s and not s.startswith('c')]
        _,_,n,k=lines.pop(0).split()
        clauses=[[int(x) for x in s.split()[:-1]] for s in lines]
        assert len(clauses)==int(k)
        return int(n),clauses
    truth_checks=0
    samples=[[],[1],[-1],[1,1],[1,-1],[1,2],[1,-2],[1,2,3],[-1,-2,3],
             [1,2,1,-3],[1,2,3,4],[1,-2,-3,4],[-1,-1,2,2,3,-3]]
    for i,lits in enumerate(samples):
        source=out/f'{i}.xcnf';target=out/f'{i}.cnf'
        source.write_text('p cnf 4 1\nx '+' '.join(map(str,lits))+' 0\n')
        call([solver,'convert',source,'--out',target])
        n,clauses=parse(target.read_text())
        for mask in range(16):
            expected=sum(bool(mask & (1<<(abs(x)-1))) != (x<0) for x in lits)%2==1
            actual=False
            for extension in range(1<<(n-4)):
                m=mask|(extension<<4)
                actual |= all(any(bool(m & (1<<(abs(x)-1))) != (x<0) for x in clause) for clause in clauses)
            assert actual==expected,(lits,mask)
            truth_checks+=1
    source=out/'alias.xcnf';source.write_text('p cnf 2 1\nx1 2 0\n')
    saved=source.read_bytes()
    for kind in ('same','symbolic','hard'):
        dest=source if kind=='same' else out/(kind+'.cnf')
        if kind=='symbolic':dest.symlink_to(source)
        if kind=='hard':dest.hardlink_to(source)
        call([solver,'convert',source,'--out',dest],1)
        assert source.read_bytes()==saved
    invalid=out/'bad.xcnf';invalid.write_text('p cnf 2 1\nx1 -0\n')
    stale=out/'stale.cnf';stale.write_text('keep me\n')
    call([solver,'convert',invalid,'--out',stale],1)
    assert stale.read_text()=='keep me\n'
    # No implicit conversion in the old strict-CNF API.
    call([solver,source,'--fast'],1)
    direct=call([solver,'convert',source,'--out','-']);parse(direct)
    source=out/'contradiction.xcnf';source.write_text('p cnf 2 3\nx1 2 0\n1 0\n2 0\n')
    cnf=out/'contradiction.cnf';proof=out/'contradiction.wrat'
    call([solver,'convert',source,'--out',cnf])
    call([solver,cnf,'--proof',proof],20)
    assert 's VERIFIED' in call([checker,cnf,proof])
    call([checker,source,proof],1)
    (out/'audit.json').write_text(json.dumps(dict(complete=True,truth_checks=truth_checks,calls=observations,
                                                independent_wrat=True),indent=2)+'\n')
    print(f'PASS {truth_checks} assignment checks, aliases, stale output, stdout, strict CNF, WRAT proof boundary')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('solver',type=Path);p.add_argument('checker',type=Path);p.add_argument('out',type=Path)
    args=p.parse_args();run(args.solver,args.checker,args.out)
