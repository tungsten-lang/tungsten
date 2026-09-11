#!/usr/bin/env python3
"""Full tensor, paged dedup/recovery and finite automatic wide-family gates."""
from hashlib import sha256
from collections import Counter
from functools import lru_cache
from itertools import permutations
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import random

from composition_queue_test import read_record
from wide_matrix_cleanup_parity_test import blob, read_blob
from packed_composition_parity_test import exact, naive
from verify_cofactor_mergers import refactor_shared, compress_shared
from verify_coordinate_projections import project_grid
from wide_feedback_test import audit as audit_feedback


def count(path):
    return int(path.read_text()) if path.exists() else 0


def project_coordinate(shape, terms, axis, removed):
    """Independent row-block contraction, unlike the native per-bit mapper."""
    assert axis in range(3) and shape[axis]>1 and 0<=removed<shape[axis]
    result=Counter(); maps=[{} for _ in range(3)]
    for term in terms:
        row=[]
        for k,(a,b) in enumerate(((0,1),(1,2),(0,2))):
            word=term[k]
            if word not in maps[k]:
                if axis==a:
                    below=removed*shape[b]
                    value=(word&((1<<below)-1))|((word>>((removed+1)*shape[b]))<<below)
                elif axis==b:
                    value=0; width=shape[b]; low=(1<<removed)-1
                    for r in range(shape[a]):
                        chunk=(word>>(r*width))&((1<<width)-1)
                        contracted=(chunk&low)|((chunk>>(removed+1))<<removed)
                        value|=contracted<<(r*(width-1))
                else:
                    value=word
                maps[k][word]=value
            row.append(maps[k][word])
        if all(row): result[tuple(row)]^=1
    return sorted(t for t,odd in result.items() if odd)


def projection_oracle_tests():
    rng=random.Random(20260910); checked=0
    shapes=[(2,3,4),(1,1,65),(2,1,512),(32,32,1),(7,7,7)]
    shapes += [tuple(rng.randrange(1,33) for _ in range(3)) for _ in range(50)]
    for shape in shapes:
        widths=(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2])
        terms=[tuple(rng.getrandbits(w) or 1 for w in widths) for _ in range(12)]
        # Include duplicates, sparse edge bits and zero-producing restrictions.
        terms+=terms[:3]+[(1,1,1),tuple(1<<(w-1) for w in widths)]
        for axis,size in enumerate(shape):
            if size<2: continue
            for removed in sorted({0,size//2,size-1}):
                coords=[list(range(n)) for n in shape]; coords[axis].remove(removed)
                assert project_coordinate(shape,terms,axis,removed)==sorted(project_grid(shape,terms,coords))
                checked+=1
    return checked


def audit(root, progress=None):
    q=root/'composition/transforms'; objects=root/'composition/objects'
    done=count(q/'consumed'); submitted=count(q/'submitted')
    verified=set(); seen=set(); counts=dict(contexts=done,basis=0,project=0,neutral=0,limited=0)
    @lru_cache(maxsize=64)
    def load(h):
        raw=(objects/f'{h}.tensor').read_bytes(); assert sha256(raw).hexdigest()==h
        shape,terms=read_blob(raw)
        if h not in verified:
            exact(shape,terms); verified.add(h)
        return shape,terms
    for ticket in range(1,submitted+1):
        raw=read_record(q,'tasks',ticket); tag,h,mode=raw.decode().split(); mode=int(mode)
        assert tag=='MFT_TASK1' and raw==f'MFT_TASK1 {h} {mode}\n'.encode()
        assert (h,mode) not in seen; seen.add((h,mode))
        kind='basis' if mode<18 else 'project'; ordinal=mode+1 if mode<18 else mode-17
        assert read_record(q/'index'/h,kind,ordinal)==f'{ticket}\n'.encode()
        if ticket>done: continue
        shape,terms=load(h); width=max(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2])
        record=read_record(q,'results',ticket); fields=record.decode().split()
        assert len(fields)==11 and fields[0]=='MFT_RESULT1' and fields[1]==sha256(raw).hexdigest()
        n,m,p,before,proposed,admitted,status,work=map(int,fields[3:])
        assert before==len(terms) and 1<=proposed<=before and status in (1,2,3) and 0<=work<=140000000
        assert record==(' '.join(fields)+'\n').encode()
        expected=terms; dims=shape
        if mode<18:
            order=[mode//2] if mode<6 else list(permutations(range(3)))[(mode-6)//2]
            for _ in range(1 if mode<6 else 2):
                for axis in order:
                    expected,_=refactor_shared(expected,axis,max_bits=width,reverse_columns=bool(mode%2))
                if sorted(expected)==terms: break
        else:
            index=mode-18; coordinate=None
            for axis,size in enumerate(shape):
                if size<2: continue
                if index<size:
                    coordinate=axis,index; break
                index-=size
            assert coordinate is not None
            axis,index=coordinate; coords=[list(range(d)) for d in shape]; coords[axis].remove(index)
            expected=project_coordinate(shape,terms,axis,index); dims=tuple(map(len,coords))
        assert (n,m,p)==dims
        expected,_=compress_shared(expected,max_bits=width)
        if status==3:
            assert fields[2]=='-' and admitted==0
        else:
            assert admitted==proposed
            result_shape,result=load(fields[2]); assert result_shape==dims and len(result)==admitted
            if status==1: assert result==sorted(expected)
            assert (root/f'composition/by-shape/{n}x{m}x{p}'/fields[2]).is_file()
            counts['neutral']+=mode<18 and h!=fields[2] and admitted==before
        counts[kind]+=1; counts['limited']+=status!=1
        if progress is not None and ticket%100==0:
            progress(dict(counts,ticket=ticket,full_tensors=len(verified)))
    counts['full_tensors']=len(verified)
    return counts


def check(binary, retained=None, public=None):
    binary=str(Path(binary).resolve())
    print('PASS row-block projection oracle:',projection_oracle_tests(),'dense/sparse grid comparisons')
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-queue-') as temp:
        root=Path(temp) if retained is None else Path(retained)
        if retained is not None: assert not root.exists(); root.mkdir()
        source=root/'input.tensor'; shape=(1,1,65)
        # Identity matrix with a noncanonical, equal-rank 2x2 factorization.
        terms=[(1,3,1),(1,2,3)]+[(1,1<<i,1<<i) for i in range(2,65)]
        raw=blob(shape,terms); source.write_bytes(raw); h=sha256(raw).hexdigest()
        def run(args,ok=True,**env):
            p=subprocess.run([binary,*map(str,args)],capture_output=True,text=True,timeout=30,
                             env=dict(os.environ,**env))
            assert (p.returncode==0)==ok,(args,p.returncode,p.stdout,p.stderr)
            return p
        run(['--turn-self-test'])
        (root/'stop').write_text('stop\n')
        run(['--offer-file',root,source],False); assert not (root/'composition').exists()
        (root/'stop').unlink(); run(['--offer-file',root,source])
        q=root/'composition/transforms'
        assert count(q/'submitted')==2
        snapshot={p:p.read_bytes() for p in q.rglob('*') if p.is_file()}
        run(['--offer-file',root,source]); assert snapshot=={p:p.read_bytes() for p in q.rglob('*') if p.is_file()}
        # Reject a context gap before appending a global task.
        run(['--offer-task',root,h,4],False); assert count(q/'submitted')==2
        assert read_record(q,'tasks',3) is None
        # Crash after global append, before index/counter commit.
        (q/'submitted').write_text('1\n'); (q/'index'/h/'project-pages/0').unlink()
        run(['--offer-file',root,source]); assert snapshot=={p:p.read_bytes() for p in q.rglob('*') if p.is_file()}
        run(['--drain',root,4],METAFLIP_WIDE_TRANSFORMS='0'); assert count(q/'consumed')==0
        (root/'stop').write_text('stop\n'); run(['--drain',root,4]); assert count(q/'consumed')==0
        (root/'stop').unlink()
        # Source digest/full tensor gate precedes any task acknowledgement.
        obj=root/'composition/objects'/f'{h}.tensor'; obj.write_bytes(raw+b' ')
        run(['--drain',root,1],False); assert count(q/'consumed')==0 and (q/'error').exists()
        obj.write_bytes(raw); run(['--drain',root,1]); assert count(q/'consumed')==1 and not (q/'error').exists()
        assert audit(root)['neutral']==1
        # Replay after children/results committed but the consume cursor lost.
        second=root/'second.tensor'; second.write_bytes(blob((1,1,3),naive((1,1,3))))
        run(['--offer-file',root,second]); submitted=count(q/'submitted')
        snapshot={p:p.read_bytes() for p in q.rglob('*') if p.is_file()}
        (q/'consumed').write_text('0\n'); run(['--drain',root,1])
        assert count(q/'submitted')==submitted and count(q/'consumed')==1
        assert snapshot=={p:p.read_bytes() for p in q.rglob('*') if p.is_file()}
        for _ in range(100):
            if count(q/'consumed')==count(q/'submitted'): break
            run(['--drain',root,4])
        assert count(q/'consumed')==count(q/'submitted')==169
        checked=audit(root)
        feedback=audit_feedback(root)
        assert feedback['submitted']>0 and feedback['consumed']==0
        assert checked['basis']==36 and checked['project']==133 and checked['neutral']>0 and checked['limited']==0
        # Full-term identity retains the useful rank tie, not just one rank.
        assert len(list((root/'composition/by-shape/1x1x65').iterdir()))==2
        # Compact pages, not one global/index file per context.
        assert len(list(q.rglob('*-pages/*')))<35
        assert not (q/'tasks').exists() and not (q/'results').exists()
        # A checksummed forged result still cannot pass native replay. The
        # result journal is not authority for a tensor or the selected recipe.
        page=q/'results-pages/0'; good_page=page.read_bytes()
        header,payload=good_page.split(b'\n',1); lines=payload.splitlines(keepends=True)
        fields=lines[0].decode().split(); good_result=fields[2]
        dims,valid=read_blob((root/'composition/objects'/f'{good_result}.tensor').read_bytes())
        bad=valid.copy(); u,v,w=bad[0]; bad[0]=(u,v,w^2)
        false_blob=blob(dims,bad); false_id=sha256(false_blob).hexdigest()
        false_path=root/'composition/objects'/f'{false_id}.tensor'; false_path.write_bytes(false_blob)
        fields[2]=false_id; lines[0]=(' '.join(fields)+'\n').encode(); payload=b''.join(lines)
        parts=header.decode().split(); parts[-1]=sha256(payload).hexdigest()
        page.write_bytes((' '.join(parts)+'\n').encode()+payload)
        run(['--task',root,1],False)
        assert not (root/'composition/by-shape/1x1x65'/false_id).exists()
        page.write_bytes(good_page); false_path.unlink()
        snapshot={p:p.read_bytes() for p in root.rglob('*') if p.is_file()}
        run(['--offer-file',root,source]); run(['--drain',root,4])
        assert snapshot=={p:p.read_bytes() for p in root.rglob('*') if p.is_file()}
        print('PASS automatic wide queue:',checked,'feedback:',feedback)
        if public is not None:
            cold=root/'public-batch'; cold.mkdir()
            run(['--offer-file',cold,second])
            p=subprocess.run([str(Path(public).resolve()),'--compose-batch',str(cold),'4'],
                             capture_output=True,text=True,timeout=30)
            assert p.returncode==0,(p.stdout,p.stderr)
            assert count(cold/'composition/transforms/consumed')==4,(p.stdout,p.stderr)
            feedback=audit_feedback(cold)
            assert feedback['submitted']>0
            print('PASS public four-context batch:',audit(cold),'feedback:',feedback)


if __name__=='__main__':
    check(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else None,
          sys.argv[3] if len(sys.argv)>3 else None)
