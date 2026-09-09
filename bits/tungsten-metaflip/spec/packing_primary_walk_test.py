#!/usr/bin/env python3
"""Independent observation minima and acceptance for packing-driven walks."""
from pathlib import Path
import subprocess
import sys
import tempfile

from mixed_observer_walk_test import fields, greedy_price, read_scheme
from mixed_composition_parity_test import optimal as pair_optimal
from mixed_group_composition_parity_test import optimal as group_optimal
from packed_composition_parity_test import naive


def check(binary):
    with tempfile.TemporaryDirectory(prefix='metaflip-packing-primary-') as directory:
        root = Path(directory)
        shape = (2,2,3)
        terms = naive(shape)
        source = root/'source.txt'
        source.write_text(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms))
        costs = [11,20,20,21,30,30,-1,40,40,-1]

        def run(name, kind=None, mode='walk', steps=32, every=1, chunks=1,
                budget=50000, costs=costs, shape=shape, source=source,
                limit=14, raw=None, extra=(), success=True):
            out = root/name
            out.mkdir()
            primary = [str(limit)]+[' '.join(map(str,range(limit+1)))]*3
            if kind:
                primary += [f'mixed-primary {kind} {budget}',
                            ' '.join(map(str,costs[:4] if kind == 'pairs' else costs))]
            table = out/'prices.txt'
            table.write_text(raw if raw is not None else '\n'.join(primary)+'\n')
            command = [binary,str(source),'x'.join(map(str,shape)),str(table),'1',str(chunks),str(steps),
                       mode,'950113',str(out),'2','8',str(every),*extra]
            p = subprocess.run(command,capture_output=True,text=True,timeout=60)
            assert (p.returncode == 0) == success,(command,p.stdout,p.stderr)
            if not success:
                assert not list(out.glob('*trial-*.txt'))
                return out,p.stdout
            assert not fields(p.stdout,'BUD_MIXED_OBSERVER') and not fields(p.stdout,'BUD_OBSERVER')
            t=fields(p.stdout,'BUD_RESULT')[0]
            assert int(t['attempted']) == chunks*steps
            if kind:
                stats=fields(p.stdout,'BUD_PACK')[0]
                assert stats['kind']==kind and int(stats['budget'])==budget
                evaluations=1+chunks*((steps+every-1)//every)
                assert int(stats['evaluations'])==evaluations
                assert int(stats['probes_or_states'])<=evaluations*budget
                assert int(stats['pair_states'])<=evaluations*budget
            return out,p.stdout

        control,ct=run('control')
        samples=[terms]
        for length in range(1,33):
            out,_=run('prefix-'+str(length),steps=length)
            samples.append(read_scheme(out/'end-0.txt',shape))
        for kind,oracle in (('pairs',lambda t:pair_optimal(t,costs[:4])),('groups',lambda t:group_optimal(t,costs))):
            objectives=[(oracle(sorted(t)),len(t),sum(v.bit_count() for row in t for v in row)) for t in samples]
            best=min(range(len(samples)),key=lambda i:objectives[i])
            out,text=run(kind,kind)
            row=fields(text,'BUD_TRIAL')[0]
            assert tuple(int(row[k]) for k in ('score','rank','bits'))==objectives[best]
            assert int(row['best_at'])==best
            assert sorted(read_scheme(out/'trial-0.txt',shape))==sorted(samples[best])
            assert (out/'end-0.txt').read_bytes()==(control/'end-0.txt').read_bytes()
            for key in ('attempted','accepted_flips','accepted_chunks','observations'):
                assert fields(text,'BUD_RESULT')[0][key]==fields(ct,'BUD_RESULT')[0][key]
            assert int(fields(text,'BUD_PACK')[0]['fallback_components'])==0
            # One chunk's proposal is cadence-neutral. The acceptance rule
            # is independently determined from all observed objective values.
            for mode in ('greedy','anneal'):
                out,text=run(kind+'-'+mode,kind,mode=mode)
                accept=(objectives[-1][0]<=objectives[0][0] if mode=='greedy'
                        else objectives[-1][0]<=objectives[best][0])
                assert int(fields(text,'BUD_TRIAL')[0]['chunks_accepted'])==int(accept)
                assert sorted(read_scheme(out/'end-0.txt',shape))==sorted(samples[-1] if accept else terms)
                assert tuple(int(fields(text,'BUD_TRIAL')[0][k]) for k in ('score','rank','bits'))==objectives[best]
            coarse,coarse_text=run(kind+'-coarse',kind,every=32)
            assert (coarse/'end-0.txt').read_bytes()==(control/'end-0.txt').read_bytes()
            assert fields(coarse_text,'BUD_RESULT')[0]['accepted_flips']==fields(ct,'BUD_RESULT')[0]['accepted_flips']
        print('PASS packing primary: 33 observation minima, independent greedy/anneal acceptance, cadence-neutral walk and counters',flush=True)

        # Multi-chunk steering, reproducibility and canonical post-hoc scoring.
        for mode in ('walk','greedy','anneal'):
            snapshots=[]
            for rep in range(2):
                out,text=run(f'multi-{mode}-{rep}','groups',mode=mode,chunks=24,steps=128,every=16)
                candidate=read_scheme(out/'trial-0.txt',shape)
                row=fields(text,'BUD_TRIAL')[0]
                assert int(row['score'])==group_optimal(sorted(candidate),costs)
                assert int(row['score'])<=group_optimal(terms,costs)
                snapshots.append((row,(out/'trial-0.txt').read_bytes(),(out/'end-0.txt').read_bytes()))
            assert snapshots[0]==snapshots[1]
        for shape in ((2,2,3),(3,3,3),(5,5,5)):
            t=naive(shape);source=root/('source-'+'x'.join(map(str,shape))+'.txt')
            source.write_text(str(len(t))+'\n'+''.join(' '.join(map(str,row))+'\n' for row in t))
            for kind in ('pairs','groups'):
                out,text=run(f'fallback-{shape}-{kind}',kind,budget=1,shape=shape,source=source,limit=len(t)+2,steps=8)
                got=read_scheme(out/'trial-0.txt',shape)
                assert int(fields(text,'BUD_TRIAL')[0]['score'])==greedy_price(got,costs[:4])
                assert int(fields(text,'BUD_PACK')[0]['fallback_components'])>0
        print('PASS packing primary: repeatable multi-chunk steering, explicit canonical fallback and rank above 64',flush=True)

        primary=[str(14)]+[' '.join(map(str,range(15)))]*3
        bad=[primary+['mixed-primary unknown 50000','7 11 11 11'],
             primary+['mixed-primary pairs 0','7 11 11 11'],
             primary+['mixed-primary groups 1000001',' '.join(map(str,costs))],
             primary+['mixed-primary pairs 050000','7 11 11 11'],
             primary+['mixed-primary pairs 50000','7 11 11 11','7 11 11 11'],
             *[primary+['mixed-primary pairs 50000',row] for row in ('7 11 11','7 11 11 11 11','-1 11 11 11','7 129 11 11','7 01 11 11')],
             *[primary+['mixed-primary groups 50000',row] for row in
               (' '.join(map(str,costs[:9])), ' '.join(map(str,costs+[11])),
                '11 20 20 21 30 30 0 40 40 -1','11 20 20 21 30 30 -2 40 40 -1')]]
        for i,lines in enumerate(bad):
            run('bad-'+str(i),raw='\n'.join(lines)+'\n',success=False)
        run('bad-limit','groups',limit=513,success=False)
        run('bad-holdout','pairs',extra=('missing-holdout',),success=False)
        print(f'PASS packing primary: {len(bad)+2} malformed or incompatible tables rejected before export',flush=True)


if __name__=='__main__':
    check(sys.argv[1])
