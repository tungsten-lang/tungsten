"""Hold learned candidate backbone fixed, remove only its residual readout."""
import argparse,json,multiprocessing as mp
from gpt_competitor import ROOT,OUT,PARAMS,CONFIG,VALID,run,read_params

def main():
    ap=argparse.ArgumentParser();ap.add_argument('problem',choices=CONFIG);args=ap.parse_args()
    p=read_params(PARAMS/(args.problem+'_tcn.txt'))
    p.update({f'gpt_w{i}':0. for i in range(20)})
    jobs=[(args.problem,'tcn',p,seed,CONFIG[args.problem][2],{'trace':args.problem+'_tcn_zero_head_validation.npz'} if seed==VALID[0] else {}) for seed in VALID]
    with mp.get_context('spawn').Pool(3) as pool:rows=pool.map(run,jobs,chunksize=1)
    (OUT/(args.problem+'_tcn_zero_head.json')).write_text(json.dumps([{'seed':seed,'score':r[0],'metrics':r[1],'wall':r[2]} for seed,r in zip(VALID,rows)],indent=2)+'\n')
    print(args.problem,'zero-head ablation completed',len(rows),'fresh starts')
if __name__=='__main__':main()
