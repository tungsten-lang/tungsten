#!/usr/bin/env python3
"""Durable native composition intake/replay; no formula-only admissions."""
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import tempfile
from packed_composition_parity_test import ROOT, exact, expected, naive, parse_terms

RUNTIME = ROOT/'bits/tungsten-metaflip/lib/metaflip'


def narrow(root, key):
    raw=(root/'objects'/f'{key}.tensor').read_bytes()
    assert sha256(raw).hexdigest() == key
    lines=raw.decode().splitlines(); header=lines.pop(0).split()
    shape=tuple(map(int,header[1:4])); terms=[tuple(map(int,line.split())) for line in lines]
    assert header[0]=='MFR1' and len(terms)==int(header[4]) and terms==sorted(terms)
    exact(shape,terms)
    return shape,terms


def store(root,shape,terms):
    data=(f'MFR1 {" ".join(map(str,shape))} {len(terms)}\n'+''.join(' '.join(map(str,t))+'\n' for t in sorted(terms))).encode()
    key=sha256(data).hexdigest(); (root/'objects'/f'{key}.tensor').write_bytes(data)
    return key


def value(path):
    return int(path.read_text()) if path.exists() else 0


def audit(root):
    q=root/'composition'
    outputs=set()
    for i in range(1,value(q/'consumed')+1):
        task=(q/'tasks'/str(i)).read_bytes(); fields=task.decode().split()
        assert len(fields)==9 and fields[0]=='MFC1'
        shape,terms=narrow(root,fields[1]); ls,leaf=narrow(root,fields[2])
        axis,k=map(int,fields[3:5]); assert ls==(2,k,k)
        target,want=expected(shape,terms,axis,k,leaf)
        result=(q/'results'/str(i)).read_text().split()
        assert result[0]=='MFC_RESULT1' and result[1]==sha256(task).hexdigest()
        raw=(q/'objects'/f'{result[2]}.tensor').read_bytes()
        assert result[2]==sha256(raw).hexdigest()
        lines=raw.decode().splitlines(); header=lines.pop(0).split()
        got=[tuple(int(v,16) for v in line.split()) for line in lines]
        assert header==['MFW1',*map(str,target),str(len(want))]
        assert got==want
        exact(target,got)
        assert result[3]=='x'.join(map(str,target)) and result[4]==str(len(got))
        outputs.add((target,len(got)))
    return outputs


def check(binary, external=None):
    def run(*args, ok=True):
        p=subprocess.run([binary,*map(str,args)],timeout=60,capture_output=True,text=True)
        assert (p.returncode==0)==ok, (args,p.returncode,p.stdout,p.stderr)
        return p
    with tempfile.TemporaryDirectory(prefix='metaflip-compose-queue-') as d:
        root=Path(d); (root/'objects').mkdir()
        key=store(root,(2,2,2),naive((2,2,2)))
        run('--prepare',root,RUNTIME,key)
        q=root/'composition'; assert value(q/'submitted')==9
        leaves={k:narrow(root,(q/'leaves'/str(k)).read_text().strip())[1] for k in (2,3,4)}
        assert {k:len(v) for k,v in leaves.items()}=={2:7,3:15,4:28}
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==9
        # Recover a crash after a task was committed, before counter/index.
        (q/'parents'/key).unlink(); (q/'submitted').unlink()
        last=sha256((q/'tasks'/'9').read_bytes()).hexdigest(); (q/'by-id'/last).unlink()
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==9 and (q/'by-id'/last).read_text()=='9\n'
        (root/'stop').write_text('stop\n')
        run('--compose-batch',root,4)
        assert value(q/'consumed')==0 and not list((q/'results').iterdir())
        (root/'stop').unlink()
        # A forged formula is not admitted, and failure is visible/pending.
        task=q/'tasks'/'1'; original=task.read_bytes(); fields=original.decode().split()
        fields[-1]=str(int(fields[-1])+1); task.write_text(' '.join(fields)+'\n')
        run('--compose-batch',root,4,ok=False)
        assert value(q/'consumed')==0 and value(q/'failures')==1 and not list((q/'objects').iterdir())
        task.write_bytes(original)
        run('--compose-batch',root,4)
        assert value(q/'consumed')==4 and not (q/'error').exists()
        first=(q/'results'/'1').read_bytes()
        # Lost completion cursor replays exactly, rather than trusting hashes.
        (q/'consumed').write_text('0\n')
        run('--compose-batch',root,4)
        assert (q/'results'/'1').read_bytes()==first
        while value(q/'consumed')<value(q/'submitted'):
            run('--compose-batch',root,4)
        audit(root)
    if external:
        # Complete projection -> queue -> wide composition chain. The imported
        # parent stays external and is never copied into the distributable bit.
        with tempfile.TemporaryDirectory(prefix='metaflip-compose-regression-') as d:
            root=Path(d)
            for name in ('objects','tasks','results'): (root/name).mkdir()
            key=store(root,(4,8,4),parse_terms(Path(external).read_bytes(),94))
            (root/'tasks'/'1').write_text(key+'\n')
            run('--refine-batch',root,1,1,RUNTIME)
            q=root/'composition'
            total=value(q/'submitted'); assert total>9
            while value(q/'consumed')<total:
                run('--compose-batch',root,4)
            results=audit(root)
            assert ((12,7,12),651) in results
            print(f'PASS external rank-94 projection chain: {total} fully replayed composition recipes; rank-651 target')
    print('PASS native composition queue: exact leaves, dedup, crash recovery, bounded drain, stop, forged price rejection')


if __name__=='__main__':
    check(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else None)
