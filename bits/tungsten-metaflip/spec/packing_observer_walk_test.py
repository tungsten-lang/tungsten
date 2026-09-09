#!/usr/bin/env python3
"""Read-only multi-context group/grid retention with independent minima."""
from pathlib import Path
import subprocess
import sys
import tempfile

from mixed_observer_walk_test import fields, greedy_price, read_scheme
from mixed_group_composition_parity_test import optimal as group_optimal
from mixed_grid_composition_parity_test import optimal as grid_optimal
from packed_composition_parity_test import naive


def check(binary):
    with tempfile.TemporaryDirectory(prefix='metaflip-packing-observers-') as directory:
        root=Path(directory);shape=(2,2,2);terms=naive(shape)
        source=root/'source.txt'
        source.write_text(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms))
        tables=[[11,20,20,21,30,30,-1,40,40,-1,38,40,40]]
        for i,c in enumerate((7,15,20,23,29,38,47)):
            costs=[c]+[2*c-(i+a)%3 for a in range(3)]
            costs += [k*c-1-(i+a)%4 for k in (3,4) for a in range(3)]
            costs += [4*c-5-(i+a)%3 for a in range(3)]
            tables.append([v if v<=128 else -1 for v in costs])

        def run(name,kind=None,rows=None,steps=32,every=1,chunks=1,trials=1,
                budget=50000,shape=shape,source=source,limit=10,mode='walk',
                raw=None,extra=(),success=True):
            out=root/name;out.mkdir()
            lines=[str(limit)]+[' '.join(str(23*k) for k in range(limit+1))]*3
            if kind:
                width={'pairs':4,'groups':10,'grids':13}[kind]
                rows=tables if rows is None else rows
                lines += [f'mixed-observers {kind} {len(rows)} {budget}']
                lines += [' '.join(map(str,row[:width])) for row in rows]
            table=out/'prices.txt';table.write_text(raw if raw is not None else '\n'.join(lines)+'\n')
            command=[binary,str(source),'x'.join(map(str,shape)),str(table),str(trials),str(chunks),str(steps),
                     mode,'972019',str(out),'2','4',str(every),*extra]
            result=subprocess.run(command,capture_output=True,text=True,timeout=60)
            assert (result.returncode==0)==success,(command,result.stdout,result.stderr)
            if not success:
                assert not list(out.glob('*trial-*.txt'))
                return out,result.stdout
            if kind:
                stats=fields(result.stdout,'BUD_MIXED')[0]
                expected=len(rows)*trials*(1+chunks*((steps+every-1)//every))
                assert int(stats['evaluations'])==expected
                for key in ('states','probes_or_states','pair_states','group_probes'):
                    if key in stats:assert 0<=int(stats[key])<=expected*budget
                for a,b in (('fallback_components','components'),('group_fallback_components','group_components')):
                    if a in stats:assert 0<=int(stats[a])<=int(stats[b])
            return out,result.stdout

        control,ct=run('control')
        samples=[terms]
        for length in range(1,33):
            out,_=run('prefix-'+str(length),steps=length)
            samples.append(read_scheme(out/'end-0.txt',shape))
        for kind,oracle,width in (('groups',group_optimal,10),('grids',grid_optimal,13)):
            out,text=run(kind,kind)
            assert fields(text,'BUD_TRIAL')==fields(ct,'BUD_TRIAL')
            for key in ('attempted','accepted_flips','accepted_chunks','observations'):
                assert fields(text,'BUD_RESULT')[0][key]==fields(ct,'BUD_RESULT')[0][key]
            for role in ('trial','end'):
                assert (out/f'{role}-0.txt').read_bytes()==(control/f'{role}-0.txt').read_bytes()
            for index,costs in enumerate(tables):
                objectives=[(oracle(sorted(t),costs[:width]),len(t),sum(v.bit_count() for row in t for v in row)) for t in samples]
                at=min(range(len(samples)),key=lambda i:objectives[i])
                row=fields(text,'BUD_MIXED_OBSERVER')[index]
                assert tuple(int(row[k]) for k in ('score','rank','bits'))==objectives[at]
                assert int(row['best_at'])==at
                assert sorted(read_scheme(out/f'mixed-observer-{index}-trial-0.txt',shape))==sorted(samples[at])
                single,st=run(kind+'-single-'+str(index),kind,rows=[costs])
                assert fields(st,'BUD_MIXED_OBSERVER')[0]|{'observer':str(index)}==row
                assert (single/'mixed-observer-0-trial-0.txt').read_bytes()==(out/f'mixed-observer-{index}-trial-0.txt').read_bytes()
            coarse,_=run(kind+'-coarse',kind,every=32)
            assert (coarse/'end-0.txt').read_bytes()==(control/'end-0.txt').read_bytes()
        print('PASS packing observers: eight group/grid objectives, every-observation minima, batch/separate equality and unchanged walk',flush=True)

        multi,mt=run('multi-control',steps=128,every=16,chunks=24,trials=2)
        for kind in ('pairs','groups','grids'):
            snapshots=[]
            for repeat in range(2):
                out,text=run(f'multi-{kind}-{repeat}',kind,steps=128,every=16,chunks=24,trials=2)
                assert fields(text,'BUD_TRIAL')==fields(mt,'BUD_TRIAL')
                for trial in range(2):
                    assert (out/f'end-{trial}.txt').read_bytes()==(multi/f'end-{trial}.txt').read_bytes()
                snapshots.append((fields(text,'BUD_MIXED_OBSERVER'),[p.read_bytes() for p in sorted(out.glob('*trial-*.txt'))]))
            assert snapshots[0]==snapshots[1]
        for shape in ((2,2,2),(3,3,3),(5,5,5)):
            terms=naive(shape);source=root/('source-'+'x'.join(map(str,shape))+'.txt')
            source.write_text(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms))
            for kind in ('groups','grids'):
                out,text=run(f'fallback-{shape}-{kind}',kind,rows=[tables[0]],shape=shape,source=source,
                             steps=8,budget=1,limit=len(terms)+2)
                got=read_scheme(out/'mixed-observer-0-trial-0.txt',shape)
                assert int(fields(text,'BUD_MIXED_OBSERVER')[0]['score'])==greedy_price(got,tables[0][:4])
                assert int(fields(text,'BUD_MIXED')[0]['fallback_components'])>0
        print('PASS packing observers: repeated multi-chunk/multi-trial retention and explicit fallback above rank 64',flush=True)

        prefix=(control/'prices.txt').read_text().splitlines()[:4]
        costs=' '.join(map(str,tables[0]))
        bad=[prefix+[f'mixed-observers grids {n} {b}',costs] for n,b in ((0,50000),(9,50000),(2,50000),(1,0),(1,1000001),('01',50000),(1,'050000'))]
        bad += [prefix+[header,costs] for header in ('mixed-observers unknown 1 50000','mixed-observers grids 1','mixed-observers grids 1 50000 extra')]
        bad += [prefix+['mixed-observers grids 1 50000',row] for row in
                (' '.join(map(str,tables[0][:-1])),costs+' 1',costs.replace('38','0'),costs.replace('38','-2'),costs.replace('38','129'),costs.replace('38','038'),costs.replace('11','-1',1))]
        bad += [prefix+['mixed-observers groups 1 50000',costs]]
        for i,lines in enumerate(bad):run('bad-'+str(i),raw='\n'.join(lines)+'\n',success=False)
        for mode in ('greedy','anneal'):run('bad-'+mode,'grids',mode=mode,success=False)
        run('bad-holdout','grids',extra=('missing-holdout',),success=False)
        run('bad-limit','grids',limit=513,success=False)
        print(f'PASS packing observers: {len(bad)+4} malformed/incompatible tables rejected before export',flush=True)


if __name__=='__main__':
    check(sys.argv[1])
