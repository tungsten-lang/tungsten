#!/usr/bin/env python3
"""Full tensor, paged dedup/recovery and finite automatic wide-family gates."""
from hashlib import sha256
from collections import Counter
from functools import lru_cache
from itertools import combinations, permutations
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import random

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))

from composition_queue_test import read_record
from wide_matrix_cleanup_parity_test import blob, read_blob
from packed_composition_parity_test import exact, naive
from verify_cofactor_mergers import refactor_shared, compress_shared
from verify_coordinate_projections import project_grid
from wide_feedback_test import audit as audit_feedback
import screen_middle_shear_children as middle
import replay_axis_mask_cascade as axis_mask


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


def axis_mask_best_rank(shape, terms, axis):
    size=shape[axis]; best=len(terms)+1; selected=None
    for removed in range(size):
        for bit in range(size):
            if bit==removed: continue
            rank=len(axis_mask.child(shape,terms,axis,removed,1<<bit)[2])
            if rank<best: best,selected=rank,removed
    for weight in (0,2,3):
        for bits in combinations((b for b in range(size) if b!=selected),weight):
            rank=len(axis_mask.child(shape,terms,axis,selected,
                                     sum(1<<b for b in bits))[2])
            if rank<best: best=rank
    return best


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


def productive_postbasis(binary):
    package=Path(__file__).resolve().parents[1]
    replay=package/'tools/replay_structured_parent_portfolio.rb'
    with tempfile.TemporaryDirectory(prefix='metaflip-postbasis-productivity-') as directory:
        root=Path(directory)
        subprocess.run(['ruby',str(replay),'--output',str(root/'parent'),
                        '--only','20x20x25'],check=True,capture_output=True,text=True,timeout=30)
        shape,terms=read_blob((root/'parent/20x20x25/20x20x25.mfw').read_bytes())
        assert shape==(20,20,25)
        projected=project_coordinate(shape,terms,1,18)
        reduced,_=compress_shared(projected,max_bits=max(shape[0]*shape[1],
                                                        shape[1]*shape[2],shape[0]*shape[2]))
        assert len(reduced)==5439
        source=root/'projected.mfw'; source.write_bytes(blob((20,19,25),reduced))
        first=root/'postbasis-first.mfw'
        result=subprocess.run([binary,'--postbasis-scan',str(source),str(first)],check=True,
                              capture_output=True,text=True,timeout=30)
        fields=dict(item.split('=',1) for item in result.stdout.split()[1:])
        assert result.stdout.startswith('POSTBASIS ') and int(fields['before'])==5439
        assert int(fields['best'])<=5422
        basis_shape,basis_terms=read_blob(first.read_bytes())
        assert basis_shape==(20,19,25)
        old_child,_=compress_shared(project_coordinate(basis_shape,reduced,0,2),
                                    max_bits=max(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2]))
        new_child,_=compress_shared(project_coordinate(basis_shape,basis_terms,0,2),
                                    max_bits=max(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2]))
        assert len(new_child)<len(old_child)
        result2=subprocess.run([binary,'--postbasis-scan',str(first)],check=True,
                               capture_output=True,text=True,timeout=30)
        fields2=dict(item.split('=',1) for item in result2.stdout.split()[1:])
        assert result2.stdout.startswith('POSTBASIS ')
        assert int(fields2['before'])==int(fields['best']) and int(fields2['best'])<=5418
        # A better tensor found in this source's first sweep has not itself
        # completed that sweep. Its first family must be offered before mode
        # 3108; offering the second family directly used to stop the queue.
        handoff=root/'handoff'; handoff.mkdir()
        subprocess.run([binary,'--offer-postbasis-file',str(handoff),str(source)],check=True,
                       capture_output=True,text=True,timeout=30)
        queue=handoff/'composition/transforms'
        source_id=sha256(source.read_bytes()).hexdigest()
        for _ in range(80):
            p=subprocess.run([binary,'--drain',str(handoff),'4'],capture_output=True,
                             text=True,timeout=30)
            assert p.returncode==0,(p.stdout,p.stderr)
            terminal=read_record(queue/'index'/source_id,'postbasis',18)
            if terminal is not None and count(queue/'consumed')>=int(terminal): break
        assert terminal is not None and count(queue/'consumed')>=int(terminal)
        assert read_record(queue,'tasks',int(terminal)).decode().split()[2]=='3107'
        best=(handoff/'composition/best/20x19x25').read_text().split()
        assert int(best[0])<=5422 and best[1]!=source_id
        assert read_record(queue/'index'/best[1],'postbasis',1) is not None
        assert read_record(queue/'index'/best[1],'project',1) is not None
        assert not (queue/'error').exists()
        print('PASS native projected-basis productivity: 5439 ->',fields['best'],'->',fields2['best'])


def productive_middle_mask(binary):
    package=Path(__file__).resolve().parents[1]
    replay=package/'tools/replay_structured_parent_portfolio.rb'
    with tempfile.TemporaryDirectory(prefix='metaflip-middle-mask-queue-') as directory:
        root=Path(directory)
        subprocess.run(['ruby',str(replay),'--output',str(root/'parent'),
                        '--only','8x18x30'],check=True,capture_output=True,text=True,timeout=30)
        source=root/'parent/8x18x30/8x30x18.mfw'
        for index,(shape,rank,digest) in enumerate((
                ((8,29,18),2493,'6265b61d6591f662e1765ddafcbf3d269e622d14089d440aaa191bb6cf98889d'),
                ((8,28,18),2436,'e122208719fddbd814d079d2b52169f662018786f9b180b024387de0ab248688'))):
            workspace=root/f'pass{index}'; workspace.mkdir()
            offered=subprocess.run([binary,'--offer-file',str(workspace),str(source)],
                                   check=True,capture_output=True,text=True,timeout=30)
            identity=offered.stdout.split()[1]
            subprocess.run([binary,'--offer-task',str(workspace),identity,'3126'],
                           check=True,capture_output=True,text=True,timeout=30)
            drained=subprocess.run([binary,'--drain',str(workspace),'3'],
                                   check=True,capture_output=True,text=True,timeout=60)
            assert 'done=3' in drained.stdout
            assert read_record(workspace/'composition/transforms/index'/identity,'mask',1)==b'3\n'
            assert read_record(workspace/'composition/transforms/index'/digest,'postbasis',1) is not None
            result=(workspace/'composition/best'/'x'.join(map(str,shape))).read_text().split()
            assert result==[str(rank),digest]
            source=workspace/'composition/objects'/f'{digest}.tensor'
            child_shape,child_terms=read_blob(source.read_bytes())
            assert child_shape==shape and len(child_terms)==rank
            exact(shape,child_terms)

        # A completed second postbasis sweep schedules the same search arm
        # without a user flag or an explicit mask task offer.
        tiny=root/'tiny'; tiny.mkdir()
        source=tiny/'source.mfw'; source.write_bytes(blob((2,3,2),naive((2,3,2))))
        subprocess.run([binary,'--offer-postbasis-file',str(tiny),str(source)],
                       check=True,capture_output=True,text=True,timeout=30)
        queue=tiny/'composition/transforms'
        mask_ticket=None
        for _ in range(80):
            subprocess.run([binary,'--drain',str(tiny),'4'],check=True,
                           capture_output=True,text=True,timeout=30)
            for ticket in range(1,count(queue/'submitted')+1):
                if read_record(queue,'tasks',ticket).decode().split()[2]=='3126':
                    mask_ticket=ticket; break
            if mask_ticket is not None and count(queue/'consumed')>=mask_ticket:
                break
        assert mask_ticket is not None and count(queue/'consumed')>=mask_ticket
        offered_modes={int(read_record(queue,'tasks',ticket).decode().split()[2])
                       for ticket in range(1,count(queue/'submitted')+1)}
        assert {3126,3127,3128}<=offered_modes
        checked=audit(tiny)
        assert checked['mask']>=1 and checked['limited']==0

        roots=tiny/'root'; roots.mkdir()
        subprocess.run([binary,'--offer-file',str(roots),str(source)],
                       check=True,capture_output=True,text=True,timeout=30)
        queue=roots/'composition/transforms'
        parent_mask=None
        for _ in range(150):
            subprocess.run([binary,'--drain',str(roots),'4'],check=True,
                           capture_output=True,text=True,timeout=30)
            for ticket in range(1,count(queue/'submitted')+1):
                raw=read_record(queue,'tasks',ticket).decode().split()
                if raw[2]!='3126': continue
                shape,_=read_blob((roots/'composition/objects'/f'{raw[1]}.tensor').read_bytes())
                if shape==(2,3,2): parent_mask=ticket; break
            if parent_mask is not None and count(queue/'consumed')>=parent_mask:
                break
        assert parent_mask is not None and count(queue/'consumed')>=parent_mask
        checked=audit(roots)
        assert checked['mask']>=1 and checked['limited']==0
        print('PASS automatic middle-mask cascade: 2526 -> 2493 -> 2436; '
              'postbasis mask task',mask_ticket,'root mask task',parent_mask)


def productive_axis_masks(binary):
    package=Path(__file__).resolve().parents[1]
    replay=package/'tools/replay_structured_parent_portfolio.rb'
    cases=(('8x18x30','8x30x18',3128,'mask-last',(8,30,17),2472,
            'a9c1ec3aa769d51ed46418ed112924f0e9abf9d352ad0c14351cf4fe0829146e'),
           ('10x12x20','12x10x20',3127,'mask-first',(11,10,20),1397,
            '35aead2549cb29e21236dff425e10e657f5248acc9b8987473c07fdb29228d49'))
    with tempfile.TemporaryDirectory(prefix='metaflip-axis-mask-queue-') as directory:
        root=Path(directory)
        for index,(portfolio,oriented,mode,kind,shape,rank,digest) in enumerate(cases):
            parent=root/f'parent{index}'
            subprocess.run(['ruby',str(replay),'--output',str(parent),'--only',portfolio],
                           check=True,capture_output=True,text=True,timeout=30)
            source=parent/portfolio/f'{oriented}.mfw'
            workspace=root/f'pass{index}'; workspace.mkdir()
            offered=subprocess.run([binary,'--offer-file',str(workspace),str(source)],
                                   check=True,capture_output=True,text=True,timeout=30)
            identity=offered.stdout.split()[1]
            subprocess.run([binary,'--offer-task',str(workspace),identity,str(mode)],
                           check=True,capture_output=True,text=True,timeout=30)
            drained=subprocess.run([binary,'--drain',str(workspace),'3'],
                                   check=True,capture_output=True,text=True,timeout=60)
            assert 'done=3' in drained.stdout
            queue=workspace/'composition/transforms'
            assert read_record(queue/'index'/identity,kind,1)==b'3\n'
            assert read_record(queue/'index'/digest,'postbasis',1) is not None
            assert (workspace/'composition/best'/'x'.join(map(str,shape))).read_text().split()==[
                str(rank),digest]
            actual_shape,terms=read_blob((workspace/'composition/objects'/f'{digest}.tensor').read_bytes())
            assert actual_shape==shape and len(terms)==rank
            exact(shape,terms)
    print('PASS native first/last axis masks: 8x17x30 r2472; 10x11x20 r1397')


def productive_postmask_basis(binary):
    package=Path(__file__).resolve().parents[1]
    replay=package/'tools/replay_structured_parent_portfolio.rb'
    with tempfile.TemporaryDirectory(prefix='metaflip-postmask-basis-') as directory:
        root=Path(directory)
        subprocess.run(['ruby',str(replay),'--output',str(root/'parent'),
                        '--only','8x15x20'],check=True,capture_output=True,text=True,timeout=30)
        source=root/'parent/8x15x20/8x20x15.mfw'
        workspace=root/'queue'; workspace.mkdir()
        offered=subprocess.run([binary,'--offer-file',str(workspace),str(source)],
                               check=True,capture_output=True,text=True,timeout=30)
        identity=offered.stdout.split()[1]
        subprocess.run([binary,'--offer-task',str(workspace),identity,'3128'],
                       check=True,capture_output=True,text=True,timeout=30)
        queue=workspace/'composition/transforms'
        subprocess.run([binary,'--drain',str(workspace),'3'],check=True,
                       capture_output=True,text=True,timeout=30)
        best=workspace/'composition/best/8x20x14'
        assert int(best.read_text().split()[0])==1409
        child=best.read_text().split()[1]
        assert read_record(queue/'index'/child,'postbasis',1) is not None
        for _ in range(20):
            subprocess.run([binary,'--drain',str(workspace),'4'],check=True,
                           capture_output=True,text=True,timeout=30)
            if best.read_text().split()[0]=='1406': break
        rank,digest=best.read_text().split()
        assert (rank,digest)==('1406','b324ebd3fdb3ca4eb894b418509cacc4dadbe7e8cfb59c52d033d1ce75d98513')
        shape,terms=read_blob((workspace/'composition/objects'/f'{digest}.tensor').read_bytes())
        assert shape==(8,20,14) and len(terms)==1406
        exact(shape,terms)
    print('PASS automatic postmask basis: 8x14x20 r1409 -> r1406')


def audit(root, progress=None):
    q=root/'composition/transforms'; objects=root/'composition/objects'
    done=count(q/'consumed'); submitted=count(q/'submitted')
    verified=set(); seen=set(); counts=dict(contexts=done,basis=0,project=0,postbasis=0,
                                            mask=0,mask_first=0,mask_last=0,neutral=0,limited=0)
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
        if mode<18: kind,ordinal='basis',mode+1
        elif mode==3126: kind,ordinal='mask',1
        elif mode==3127: kind,ordinal='mask-first',1
        elif mode==3128: kind,ordinal='mask-last',1
        elif mode>=3090: kind,ordinal='postbasis',mode-3089
        else: kind,ordinal='project',mode-17
        assert read_record(q/'index'/h,kind,ordinal)==f'{ticket}\n'.encode()
        if ticket>done: continue
        shape,terms=load(h); width=max(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2])
        record=read_record(q,'results',ticket); fields=record.decode().split()
        assert len(fields)==11 and fields[0]=='MFT_RESULT1' and fields[1]==sha256(raw).hexdigest()
        n,m,p,before,proposed,admitted,status,work=map(int,fields[3:])
        work_bound=150000000000 if mode>=3126 else 140000000
        assert before==len(terms) and 1<=proposed<=before and status in (1,2,3) and 0<=work<=work_bound
        assert record==(' '.join(fields)+'\n').encode()
        expected=terms; dims=shape
        basis_mode=mode if mode<18 else (mode-3090)%18 if 3090<=mode<=3125 else None
        if basis_mode is not None:
            order=[basis_mode//2] if basis_mode<6 else list(permutations(range(3)))[(basis_mode-6)//2]
            for _ in range(1 if basis_mode<6 else 2):
                for axis in order:
                    expected,_=refactor_shared(expected,axis,max_bits=width,reverse_columns=bool(basis_mode%2))
                if sorted(expected)==terms: break
        elif mode>=3126:
            axis={3126:1,3127:0,3128:2}[mode]
            assert 2<=shape[axis]<=32
            dims=tuple(size-(i==axis) for i,size in enumerate(shape))
            expected=None
            if status==1:
                assert proposed==(middle.screen(shape,terms,h)['row']['rank'] if axis==1
                                  else axis_mask_best_rank(shape,terms,axis))
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
        if expected is not None:
            expected,_=compress_shared(expected,max_bits=width)
        if status==3:
            assert fields[2]=='-' and admitted==0
        else:
            assert admitted==proposed
            result_shape,result=load(fields[2]); assert result_shape==dims and len(result)==admitted
            if status==1 and expected is not None: assert result==sorted(expected)
            assert (root/f'composition/by-shape/{n}x{m}x{p}'/fields[2]).is_file()
            counts['neutral']+=mode<18 and h!=fields[2] and admitted==before
        counts[kind.replace('-','_')]+=1; counts['limited']+=status!=1
        if progress is not None and ticket%100==0:
            progress(dict(counts,ticket=ticket,full_tensors=len(verified)))
    counts['full_tensors']=len(verified)
    return counts


def check(binary, retained=None, public=None):
    binary=str(Path(binary).resolve())
    print('PASS row-block projection oracle:',projection_oracle_tests(),'dense/sparse grid comparisons')
    productive_postbasis(binary)
    productive_middle_mask(binary)
    productive_axis_masks(binary)
    productive_postmask_basis(binary)
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
        assert count(q/'consumed')==count(q/'submitted')==281
        checked=audit(root)
        feedback=audit_feedback(root)
        assert feedback['submitted']>0 and feedback['consumed']==0
        assert (checked['basis'],checked['project'],checked['postbasis'],
                checked['mask_last'])==(36,135,108,2)
        assert checked['neutral']>0 and checked['limited']==0
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
