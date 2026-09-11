#!/usr/bin/env python3
"""Native wide projection -> outbox -> public live rectangular seed gate."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

from wide_matrix_cleanup_parity_test import blob
from composition_queue_test import read_record, value
from wide_feedback_test import audit
from refinement_fleet_test import run as run_fleet
from verify_representation_portfolio import parse_terms


def check(public, transform, retained=None):
    public=Path(public).resolve(); transform=Path(transform).resolve()
    temporary=tempfile.TemporaryDirectory(prefix='metaflip-feedback-fleet-') if retained is None else None
    root=Path(temporary.name) if temporary else Path(retained)
    if temporary is None:
        assert not root.exists();root.mkdir(parents=True)
    case=root/'live';spool=case/'status.txt.refinement'
    # Lift a retained rank tie into a larger parent; the last-column deletion
    # must return a seed that meets the live near-best admission policy.
    seed=Path(__file__).resolve().parents[1]/'lib/metaflip/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt'
    terms=parse_terms(seed.read_bytes(),47)
    def embed(word,rows):
        return sum(((word>>(row*6))&63)<<(row*7) for row in range(rows))
    lifted=[(u,embed(v,5),embed(w,2)) for u,v,w in terms]
    lifted += [(1<<(i*5+k),1<<(k*7+6),1<<(i*7+6)) for i in range(2) for k in range(5)]
    source=root/'source.tensor';source.write_bytes(blob((2,5,7),lifted))
    def invoke(binary,*args):
        result=subprocess.run(['nice','-n','10',str(binary),*map(str,args)],
            capture_output=True,text=True,timeout=30,
            env=dict(os.environ,METAFLIP_WIDE_FEEDBACK='1',METAFLIP_WIDE_TRANSFORMS='1'))
        assert result.returncode==0,(args,result.stdout,result.stderr)
    invoke(transform,'--offer-file',spool,source)
    # The actual public composition worker projects this wide-formatted parent.
    while value(spool/'composition/transforms/consumed')<value(spool/'composition/transforms/submitted'):
        invoke(public,'--compose-batch',spool,4)
    before=audit(spool)
    matches=[]
    for ticket in range(1,before['submitted']+1):
        fields=read_record(spool/'composition/feedback','tasks',ticket).decode().split()
        if fields[3:6]==['2','5','6']:
            matches.append((ticket,fields[2],int(fields[6])))
    assert matches and before['consumed']==0
    status=run_fleet(public,case,'2x5x6',1,seconds=6,require_outputs=False)
    after=audit(spool)
    assert all(ticket<=after['consumed'] for ticket,_,_ in matches)
    assert int(status['wide_feedback_seed_uses'])>0
    assert all((spool/'by-id'/identity).exists() for _,identity,_ in matches)
    result=dict(complete=True,record_claim=False,before=before,after=after,
                matching_projected_outputs=matches,seed_uses=int(status['wide_feedback_seed_uses']))
    (root/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    if temporary:temporary.cleanup()


if __name__=='__main__':
    check(*sys.argv[1:])
