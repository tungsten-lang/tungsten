#!/usr/bin/env python3
"""Durable native composition intake/replay; no formula-only admissions."""
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import tempfile
from packed_composition_parity_test import ROOT, exact, expected, naive, parse_terms, leaf_schemes

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


def read_record(q, kind, sequence):
    old=q/kind/str(sequence)
    if old.exists(): return old.read_bytes()
    page=q/(kind+'-pages')/str((sequence-1)//64)
    if not page.exists(): return None
    header,body=page.read_bytes().split(b'\n',1)
    tag,first,count,digest=header.decode().split()
    first,count=int(first),int(count)
    assert tag=='MFCP1' and sha256(body).hexdigest()==digest
    lines=body.splitlines(keepends=True)
    assert len(lines)==count and all(1<len(line)<=256 and line.endswith(b'\n') for line in lines)
    assert (first-1)//64==(first+count-2)//64==(sequence-1)//64
    return lines[sequence-first] if first<=sequence<first+count else None


def replace_record(q, kind, sequence, record):
    """Test-only mutation, including a correct page digest: not a certificate."""
    old=q/kind/str(sequence)
    if old.exists(): old.write_bytes(record); return
    page=q/(kind+'-pages')/str((sequence-1)//64)
    header,body=page.read_bytes().split(b'\n',1)
    _,first,count,_=header.decode().split(); lines=body.splitlines(keepends=True)
    lines[sequence-int(first)]=record; body=b''.join(lines)
    page.write_bytes(f'MFCP1 {first} {count} {sha256(body).hexdigest()}\n'.encode()+body)


def audit(root):
    q=root/'composition'
    outputs=set()
    for i in range(1,value(q/'consumed')+1):
        task=read_record(q,'tasks',i); fields=task.decode().split()
        assert len(fields)==9 and fields[0]=='MFC1'
        shape,terms=narrow(root,fields[1]); ls,leaf=narrow(root,fields[2])
        axis,k=map(int,fields[3:5]); assert ls==(2,k,k)
        target,want=expected(shape,terms,axis,k,leaf)
        result=read_record(q,'results',i).decode().split()
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
    with tempfile.TemporaryDirectory(prefix='metaflip-pages-') as d:
        q=Path(d)
        run('--pages-test',q)
        for kind in ('tasks','results'):
            for i in range(1,131):
                assert read_record(q,kind,i)==f'record-{i}\n'.encode()
            assert len(list((q/(kind+'-pages')).iterdir()))==3
        assert len(list((q/'tasks').iterdir()))==0
        assert len(list((q/'results').iterdir()))==37
        assert read_record(q,'tasks',131)==b'x'*255+b'\n'
        assert read_record(q,'tasks',132) is None
    with tempfile.TemporaryDirectory(prefix='metaflip-compose-queue-') as d:
        root=Path(d); (root/'objects').mkdir()
        key=store(root,(2,2,2),naive((2,2,2)))
        run('--prepare',root,RUNTIME,key)
        q=root/'composition'; assert value(q/'submitted')==9
        leaves={k:narrow(root,(q/'leaves'/str(k)).read_text().strip())[1] for k in (2,3,4)}
        assert {k:len(v) for k,v in leaves.items()}=={2:7,3:15,4:26}
        assert not list((q/'tasks').iterdir()) and not list((q/'by-id').iterdir())
        assert len(list((q/'tasks-pages').iterdir()))==1
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==9
        # Recover a crash after tasks were committed, before counter/parent.
        (q/'parents'/key).unlink(); (q/'submitted').unlink()
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==9
        (root/'stop').write_text('stop\n')
        run('--compose-batch',root,4)
        assert value(q/'consumed')==0 and not list((q/'results').iterdir())
        (root/'stop').unlink()
        # A forged formula is not admitted, and failure is visible/pending.
        original=read_record(q,'tasks',1); fields=original.decode().split()
        fields[-1]=str(int(fields[-1])+1); replace_record(q,'tasks',1,(' '.join(fields)+'\n').encode())
        run('--compose-batch',root,4,ok=False)
        assert value(q/'consumed')==0 and value(q/'failures')==1 and not list((q/'objects').iterdir())
        replace_record(q,'tasks',1,original)
        run('--compose-batch',root,4)
        assert value(q/'consumed')==4 and not (q/'error').exists()
        first=read_record(q,'results',1)
        # Lost completion cursor replays exactly, rather than trusting hashes.
        (q/'consumed').write_text('0\n')
        run('--compose-batch',root,4)
        assert read_record(q,'results',1)==first
        while value(q/'consumed')<value(q/'submitted'):
            run('--compose-batch',root,4)
        audit(root)
        assert not list((q/'results').iterdir()) and len(list((q/'results-pages').iterdir()))==1
        # Damaged page hashes fail closed, including when the price is sound.
        page=q/'tasks-pages'/'0'; original_page=page.read_bytes()
        page.write_bytes(original_page.replace(b'MFC1 ',b'MFC2 ',1))
        (q/'consumed').write_text('0\n')
        run('--compose-batch',root,4,ok=False)
        assert value(q/'consumed')==0
        page.write_bytes(original_page)
        run('--compose-batch',root,4)
    # Upgrade an actual v1 spool with the old rank-28 leaf and indexes. Keep
    # old recipes/results immutable; reprice only scale four on re-offering.
    with tempfile.TemporaryDirectory(prefix='metaflip-compose-legacy-') as d:
        root=Path(d); (root/'objects').mkdir()
        key=store(root,(2,2,2),naive((2,2,2)))
        run('--prepare',root,RUNTIME,key)
        q=root/'composition'
        old_leaf=store(root,(2,4,4),leaf_schemes()[4])
        originals=[]
        for i in range(1,10):
            fields=read_record(q,'tasks',i).decode().split()
            if fields[4]=='4':
                fields[2]=old_leaf
                fields[-1]='112'
            body=(' '.join(fields)+'\n').encode(); originals.append(body)
            (q/'tasks'/str(i)).write_bytes(body)
            (q/'by-id'/sha256(body).hexdigest()).write_text(f'{i}\n')
        for page in (q/'tasks-pages').iterdir(): page.unlink()
        (q/'leaves'/'4').write_text(old_leaf+'\n')
        (q/'parents'/key).write_text('pair-scales-2-4-v1\n')
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==12
        assert len(narrow(root,(q/'leaves'/'4').read_text().strip())[1])==26
        assert all(read_record(q,'tasks',i)==body for i,body in enumerate(originals,1))
        assert all(read_record(q,'tasks',i).decode().split()[4]=='4' for i in range(10,13))
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==12
        # Legacy results can share a 64-record block with new paged results.
        run('--compose-batch',root,4)
        legacy_results=[read_record(q,'results',i) for i in range(1,5)]
        for i,body in enumerate(legacy_results,1): (q/'results'/str(i)).write_bytes(body)
        for page in (q/'results-pages').iterdir(): page.unlink()
        while value(q/'consumed')<value(q/'submitted'): run('--compose-batch',root,4)
        audit(root)
        assert all(read_record(q,'results',i)==body for i,body in enumerate(legacy_results,1))
        # A changed valid same-rank leaf affects only its three scale recipes.
        from packed_composition_parity_test import orient
        leaf_key=(q/'leaves'/'4').read_text().strip()
        shape,terms=narrow(root,leaf_key)
        variant=store(root,shape,orient(shape,terms,(0,2,1)))
        assert variant!=leaf_key
        (q/'leaves'/'4').write_text(variant+'\n')
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==15
        assert all(read_record(q,'tasks',i).decode().split()[2]==variant for i in range(13,16))
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted')==15
        while value(q/'consumed')<value(q/'submitted'): run('--compose-batch',root,4)
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
            assert ((16,7,16),1132) in results
            assert len(list((q/'tasks-pages').iterdir()))==(total+63)//64
            assert len(list((q/'results-pages').iterdir()))==(total+63)//64
            print(f'PASS external rank-94 projection chain: {total} fully replayed composition recipes; rank-651/rank-1132 targets')
    print('PASS native composition queue: exact leaves, paged/legacy restart, selective repricing, dedup, stop, forged price rejection')


if __name__=='__main__':
    check(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else None)
