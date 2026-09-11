#!/usr/bin/env python3
"""Full-tensor wide/narrow feedback and transactional queue gates."""
from hashlib import sha256
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile

from wide_matrix_cleanup_parity_test import blob, read_blob
from packed_composition_parity_test import naive, exact
from refinement_worker_parity_test import blob as narrow_blob
from composition_queue_test import read_record as record, replace_record, value, narrow
from verify_representation_portfolio import parse_terms


def audit(root):
    """Check every handoff, including exact immutable cross-format identity."""
    root=Path(root); queue=root/'composition/feedback'
    submitted=value(queue/'submitted'); consumed=value(queue/'consumed')
    assert 0<=consumed<=submitted
    seen=set()
    for ticket in range(1,submitted+1):
        raw=record(queue,'tasks',ticket); f=raw.decode().split()
        assert len(f)==7 and f[0]=='MFW_FEED1' and raw==(' '.join(f)+'\n').encode()
        _,wide,key,*numbers=f; shape=tuple(map(int,numbers[:3])); rank=int(numbers[3])
        assert wide not in seen; seen.add(wide)
        assert (queue/'by-id'/wide).read_text()==f'{ticket}\n'
        packed=(root/'composition/objects'/f'{wide}.tensor').read_bytes()
        assert sha256(packed).hexdigest()==wide
        dims,terms=read_blob(packed)
        assert dims==shape and len(terms)==rank and 1<=rank<=4096
        assert max(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2])<=63
        exact(shape,terms)
        assert narrow(root,key)==(shape,terms)
        if ticket<=consumed:
            intake=value(root/'by-id'/key)
            assert 1<=intake<=value(root/'submitted')
            assert (root/'tasks'/str(intake)).read_text()==key+'\n'
    return dict(submitted=submitted,consumed=consumed,pending=submitted-consumed)


def check(binary, retained=None):
    binary=Path(binary).resolve()
    context=tempfile.TemporaryDirectory(prefix='metaflip-wide-feedback-') if retained is None else None
    root=Path(context.name) if context else Path(retained)
    if context is None:
        assert not root.exists();root.mkdir(parents=True)
    runs=0
    def run(*args,ok=True,env=None):
        nonlocal runs
        p=subprocess.run([str(binary),*map(str,args)],capture_output=True,text=True,timeout=30,
                         env=dict(os.environ,**(env or {})))
        runs+=1
        assert (p.returncode==0)==ok,(args,p.stdout,p.stderr)
        return p.stdout
    assert 'PASS wide feedback' in run()
    fixtures=[]
    seeds=Path(__file__).resolve().parents[1]/'lib/metaflip/seeds/gf2'
    for name in ('matmul_2x2_rank7_strassen_gf2.txt','matmul_2x2_rank7_d36_gl120_gf2.txt'):
        fixtures.append(((2,2,2),parse_terms((seeds/name).read_bytes(),7)))
    fixtures+=[((1,1,n),naive((1,1,n))) for n in range(1,65)]
    fixtures.append(((2,5,6),naive((2,5,6))))
    paths=[]
    for i,(shape,terms) in enumerate(fixtures):
        exact(shape,terms);p=root/f'input-{i}.tensor';p.write_bytes(blob(shape,terms));paths.append(p)
    def publish(q,index=0,**kw):return run('--publish',q,paths[index],**kw)
    def take(q,shape=(2,2,2),cap=64,calls=1,mode='--take',state=None,**kw):
        out=run(mode,q,*shape,cap,calls,*([state] if state else []),**kw)
        fields=dict(t.split('=',1) for t in out.split() if '=' in t)
        return out,fields
    q=root/'basic'
    assert 'PUBLISH 1' in publish(q)
    wide=sha256(paths[0].read_bytes()).hexdigest();narrow=sha256(narrow_blob(*fixtures[0])).hexdigest()
    assert record(q/'composition/feedback','tasks',1)==f'MFW_FEED1 {wide} {narrow} 2 2 2 7\n'.encode()
    assert (q/'objects'/f'{narrow}.tensor').read_bytes()==narrow_blob(*fixtures[0])
    publish(q);assert value(q/'composition/feedback/submitted')==1
    out,f=take(q);assert 'TAKE 7 wide-feedback '+narrow in out
    assert f['refine_submitted']==f['wide_feedback_completed']=='1'
    assert f['wide_feedback_failures']==f['refine_failures']=='0'
    assert (q/'tasks/1').read_text()==narrow+'\n'
    # Replayed handoff after an intake-before-ack crash is idempotent.
    (q/'composition/feedback/consumed').unlink()
    out,f=take(q);assert 'TAKE 7 wide-feedback' in out
    assert f['refine_submitted']=='1' and f['refine_duplicates']=='1' and f['wide_feedback_completed']=='1'
    publish(q,1);out,f=take(q)
    assert 'TAKE 7 wide-feedback' in out and f['refine_submitted']=='2'
    assert audit(q)==dict(submitted=2,consumed=2,pending=0)
    # Published prefix and dedup index are recoverable from either crash point.
    for index in (False,True):
        x=root/f'recovery-{index}';publish(x)
        (x/'composition/feedback/submitted').unlink()
        if index:(x/'composition/feedback/by-id'/wide).unlink()
        run('--recover',x);publish(x)
        assert value(x/'composition/feedback/submitted')==1
        assert (x/'composition/feedback/by-id'/wide).read_text()=='1\n'
    # Cross-shape and oversized valid results are archived/enqueued, not errors.
    x=root/'cross';publish(x,64)
    out,f=take(x);assert f['refine_submitted']=='1' and f['refine_cross_shape']=='1'
    assert f['wide_feedback_completed']=='1' and f['refine_failures']=='0'
    x=root/'oversize';publish(x);out,f=take(x,cap=4)
    assert f['wide_feedback_oversized']=='1' and f['refine_submitted']=='1' and f['refine_failures']=='0'
    # 64-bit factors are archive-only; bit 62 crosses native conversion/load,
    # but the live rectangular campaign intentionally has a smaller allowlist.
    x=root/'wide';publish(x,65);assert not (x/'composition/feedback').exists()
    x=root/'boundary';publish(x,64);out,f=take(x,shape=(1,1,63),cap=128)
    assert f['wide_feedback_completed']=='1' and f['wide_feedback_unsupported']=='1'
    assert f['refine_submitted']=='1' and f['refine_failures']=='0'
    x=root/'rectangular';publish(x,66);out,f=take(x,shape=(2,5,6),cap=128)
    assert 'TAKE 60 wide-feedback' in out and f['refine_failures']=='0'
    # Cross-shape checked descendants of live-seedable shapes are spooled for
    # that shape's next campaign start under the shared state root. Unsupported
    # shapes and same-shape records never reach the spool; ranks above 4096
    # are already refused upstream by ffwf_valid_record (fixture 65 above).
    def spooled(state,shape):
        d=state/'banks/gf2'/('%dx%dx%d'%shape)/'feedback'
        return sorted(p.read_text() for p in d.glob('feedback_*.txt')) if d.exists() else []
    def scheme(shape,terms):
        return f'{len(terms)}\n'+''.join(f'{u} {v} {w}\n' for u,v,w in sorted(terms))
    x=root/'spool';state=root/'spool-state'
    publish(x);out,f=take(x,shape=(2,5,6),cap=128,state=state)
    assert f['refine_cross_shape']=='1' and f['wide_feedback_offered']=='1' and f['refine_failures']=='0'
    assert spooled(state,(2,2,2))==[scheme(*fixtures[0])]
    exact((2,2,2),parse_terms(spooled(state,(2,2,2))[0].encode(),7))
    # Intake-before-ack replay is idempotent: the same single slot, no re-offer.
    (x/'composition/feedback/consumed').unlink()
    out,f=take(x,shape=(2,5,6),cap=128,state=state)
    assert f['wide_feedback_offered']=='0' and f['wide_feedback_completed']=='1'
    assert spooled(state,(2,2,2))==[scheme(*fixtures[0])]
    # The consuming campaign's own capacity does not gate another shape's spool.
    publish(x,1);out,f=take(x,shape=(2,5,6),cap=4,state=state)
    assert f['wide_feedback_offered']=='1' and f['wide_feedback_oversized']=='0'
    assert spooled(state,(2,2,2))==sorted(scheme(*fixtures[i]) for i in (0,1))
    publish(x,64);out,f=take(x,shape=(2,5,6),cap=128,state=state)
    assert f['refine_cross_shape']=='1' and f['wide_feedback_offered']=='0'
    assert not (state/'banks/gf2/1x1x63').exists()
    publish(x,66);out,f=take(x,shape=(2,5,6),cap=128,state=state)
    assert 'TAKE 60 wide-feedback' in out and f['wide_feedback_offered']=='0'
    assert spooled(state,(2,5,6))==[] and f['refine_failures']=='0'
    y=root/'spool-off';publish(y);out,f=take(y,shape=(2,5,6),cap=128)
    assert f['refine_cross_shape']=='1' and f['wide_feedback_offered']=='0'
    assert not (root/'banks').exists()
    # Bounded spool: eight slots keep the lowest ranks, ties by lower body
    # SHA-256; a losing offer is dropped and any surviving body is a no-op.
    def split(terms,i,axis):
        term=list(terms[i]);low=term[axis]&-term[axis];rest=list(term);rest[axis]^=low;term[axis]=low
        return terms[:i]+[tuple(term),tuple(rest)]+terms[i+1:]
    variants=[];bodies=set()
    for terms in (fixtures[0][1],fixtures[1][1]):
        for i in range(len(terms)):
            for axis in range(3):
                if terms[i][axis]&(terms[i][axis]-1):
                    body=scheme((2,2,2),split(terms,i,axis))
                    if body not in bodies:bodies.add(body);variants.append(split(terms,i,axis))
    variants=[fixtures[0][1],fixtures[1][1]]+variants[:10]
    assert len(variants)==12
    def key(body):return (int(body.split('\n',1)[0]),sha256(body.encode()).hexdigest())
    state=root/'bounded-state';slots=[]
    for i,terms in enumerate(variants):
        exact((2,2,2),terms);path=root/f'bounded-{i}.tensor';path.write_bytes(blob((2,2,2),terms))
        body=scheme((2,2,2),terms)
        if body in slots:expected=0
        elif len(slots)<8:slots.append(body);expected=1
        else:
            worst=max(slots,key=key)
            expected=int(key(body)<key(worst))
            if expected:slots[slots.index(worst)]=body
        assert f'SPOOL {expected}' in run('--spool',state,path),i
        assert spooled(state,(2,2,2))==sorted(slots)
    assert len(slots)==8 and sum(key(b)[0]==7 for b in slots)==2
    assert sorted(slots,key=key)==sorted((scheme((2,2,2),t) for t in variants),key=key)[:8]
    for i in range(len(variants)):
        assert f'SPOOL 0' in run('--spool',state,root/f'bounded-{i}.tensor')
    assert spooled(state,(2,2,2))==sorted(slots)
    for body in spooled(state,(2,2,2)):exact((2,2,2),parse_terms(body.encode(),key(body)[0]))
    x=root/'disabled';publish(x,env={'METAFLIP_WIDE_FEEDBACK':'0'})
    assert not (x/'composition/feedback').exists()
    x=root/'disable-consumer';publish(x);out,f=take(x,env={'METAFLIP_WIDE_FEEDBACK':'0'})
    assert f['wide_feedback_completed']=='0' and f['refine_submitted']=='0'
    x=root/'stopped';publish(x);out,f=take(x,mode='--take-stopped')
    assert f['wide_feedback_completed']=='0' and f['refine_submitted']=='0'
    assert 'PUBLISH -1' in publish(x,ok=False)
    # All publication-side full identity gates remain mandatory on cache hits.
    x=root/'invalid';bad=root/'invalid.tensor';bad.write_bytes(blob((2,2,2),[(1,1,1)]))
    assert 'PUBLISH 0' in run('--publish',x,bad,ok=False)
    assert not (x/'composition/feedback/submitted').exists()
    for which in ('packed','narrow','binding'):
        x=root/f'corrupt-{which}';publish(x)
        if which=='packed':(x/'composition/objects'/f'{wide}.tensor').write_bytes(b'corrupt\n')
        elif which=='narrow':(x/'objects'/f'{narrow}.tensor').write_bytes(b'corrupt\n')
        else:(x/'composition/feedback/by-id'/wide).write_text('2\n')
        out,f=take(x,ok=False)
        assert f['wide_feedback_failures']=='1' and f['wide_feedback_completed']=='0'
        assert not (x/'tasks/1').exists()
    # A valid but different same-rank tensor is not an exact format conversion.
    x=root/'valid-but-wrong-map';publish(x);publish(x,1)
    fields=record(x/'composition/feedback','tasks',1).decode().split()
    fields[2]=record(x/'composition/feedback','tasks',2).decode().split()[2]
    replace_record(x/'composition/feedback','tasks',1,(' '.join(fields)+'\n').encode())
    out,f=take(x,ok=False)
    assert f['wide_feedback_failures']=='1' and f['wide_feedback_completed']=='0'
    assert not (x/'tasks/1').exists()
    x=root/'corrupt-publication-cache';publish(x)
    (x/'objects'/f'{narrow}.tensor').write_bytes(b'corrupt\n')
    assert 'PUBLISH 0' in publish(x,ok=False)
    assert value(x/'composition/feedback/submitted')==1
    # A failed intake-index commit cannot acknowledge the outbox. The durable
    # ticket remains recoverable; restart after repair does not duplicate it.
    x=root/'intake-write-failure';publish(x)
    obstruction=x/'by-id'/narrow;obstruction.mkdir(parents=True)
    out,f=take(x,ok=False)
    assert f['refine_failures']==f['wide_feedback_failures']=='1'
    assert f['wide_feedback_completed']=='0' and f['refine_submitted']=='1'
    obstruction.rmdir()
    out,f=take(x)
    assert f['wide_feedback_completed']=='1' and f['refine_submitted']=='1'
    assert f['refine_duplicates']=='1' and f['refine_failures']=='0'
    x=root/'backpressure'
    for i in range(2,11):publish(x,i)
    out,f=take(x,calls=9)
    assert f['refine_submitted']==f['wide_feedback_completed']=='8'
    assert f['wide_feedback_pending']=='1' and f['refine_failures']=='0'
    assert audit(x)==dict(submitted=9,consumed=8,pending=1)
    x=root/'pages'
    for i in range(65):publish(x,i)
    assert value(x/'composition/feedback/submitted')==65
    assert len(list((x/'composition/feedback/tasks-pages').iterdir()))==2
    assert audit(x)==dict(submitted=65,consumed=0,pending=65)
    for ticket in (1,64,65):assert record(x/'composition/feedback','tasks',ticket).startswith(b'MFW_FEED1 ')
    raw=(x/'composition/feedback/tasks-pages/1').read_bytes()
    (x/'composition/feedback/tasks-pages/1').write_bytes(raw+b'bad\n')
    run('--recover',x,ok=False)
    result=dict(complete=True,record_claim=False,native_runs=runs,binary_sha256=sha256(binary.read_bytes()).hexdigest())
    (root/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    if context:context.cleanup()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('binary');p.add_argument('--retain',type=Path)
    a=p.parse_args();check(a.binary,a.retain)
