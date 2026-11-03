"""Correct the round-3 original diagnostic by pinning round-1 champion identity."""
import hashlib,json,multiprocessing as mp
from pathlib import Path
import gpt_competitor as base
from gpt_jump_stabilize import VALID,legal
ROOT=base.ROOT;ORIGINAL=ROOT/'out/competitor_20260927';OUT=ROOT/'out/competitor_jump_round3'
def run(seed):
    base.OUT=ORIGINAL
    return base.run(('jump','pure',base.initial('jump','pure'),seed,8.,{'baseline':True,**({'trace':str(OUT/'original_pinned_validation.npz')} if seed==VALID[0] else {})}))
def main():
    champion=json.loads((ORIGINAL/'champions_before.json').read_text())['search_jump_legal']
    round2=json.loads((ROOT/'out/competitor_jump_round2/champions_before.json').read_text())['search_jump_legal']
    assert all(champion[k]==round2[k] for k in ['frozen_controller','frozen_params','scores'])
    with mp.get_context('spawn').Pool(3) as pool:results=pool.map(run,VALID,chunksize=1)
    rows=[{'seed':s,'metrics':r[1],'wall':r[2]} for s,r in zip(VALID,results)];assert not any('error' in r['metrics'] for r in rows)
    assert all(all(x==0. for x in r['metrics']['residual_peak_rad']) for r in rows)
    (OUT/'original_pinned_validate.json').write_text(json.dumps(rows,indent=2)+'\n')
    provenance={k:champion[k] for k in ['frozen_controller','frozen_params']}
    provenance['sha256']={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in provenance.values()}
    provenance['source_snapshot']=str(ORIGINAL/'champions_before.json');provenance['round2_original_identity_also_verified']=True
    provenance['supersedes_invalid_files']=['original_validate.json','original_validation.npz']
    provenance['reason']='The round-3 followup used its local champions_before snapshot, which held the round-2 temporal distance winner, and forced pure mode. It was mislabeled original. Training, candidate validation, endurance and arena results do not use that diagnostic.'
    (OUT/'original_pinned_provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print('original pinned legal3',sum(legal(r['metrics']['three_second']) for r in rows),'legal8',sum(legal(r['metrics']) for r in rows),'n',len(rows),flush=True)
if __name__=='__main__':main()
