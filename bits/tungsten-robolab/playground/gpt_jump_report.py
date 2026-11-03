"""Evidence tables for the jump recovery continuation."""
import hashlib,json,statistics
import numpy as np
from gpt_jump_recover import ROOT,OUT,PARAMS,legal

def summary(rows):
    early=[m['three_second'] for m in rows];ok3=[m for m in early if legal(m)];ok8=[m for m in rows if legal(m)]
    return {'n':len(rows),'legal3':len(ok3),'mark3':statistics.mean(m['mark'] for m in ok3) if ok3 else None,'legal8':len(ok8),'mark8':statistics.mean(m['mark'] for m in ok8) if ok8 else None,'peak_bw':statistics.mean(m['peak_grf_bw'] for m in rows),'loading':statistics.mean(m['peak_loading_bw_s'] for m in rows)}
def main():
    arena=json.loads((OUT/'arena_summary.json').read_text());pro=json.loads((OUT/'promotions.json').read_text());validation={}
    original=[r['metrics'] for r in json.loads((OUT/'original_validate.json').read_text())];validation['original']=summary(original)
    for v in ['pure','tcn']:
        rows=json.loads((OUT/f'{v}_validate.json').read_text())
        for kind in sorted({r['kind'] for r in rows}):validation[v+'_'+kind]=summary([r['metrics'] for r in rows if r['kind']==kind])
    long=json.loads((OUT/'endurance20.json').read_text());endurance={v:sum(legal(r['metrics']) for r in long if r['variant']==v) for v in ['pure','tcn']}
    ms=[r['metrics'] for r in json.loads((OUT/'tcn_validate.json').read_text()) if r['kind']=='candidate']
    peak=np.degrees(np.max([m['residual_peak_rad'] for m in ms],axis=0));rms=np.degrees(np.sqrt(np.mean(np.array([m['residual_rms_rad'] for m in ms])**2,axis=0)))
    evidence={'arena':arena,'validation':validation,'endurance20_passes_out_of_8':endurance,'residual_peak_degrees':peak.tolist(),'residual_rms_degrees':rms.tolist()}
    (OUT/'summary.json').write_text(json.dumps(evidence,indent=2)+'\n')
    lines=['## Round 2: recovery and the original jump trials','', 'The first continuation focused on the unbeatен original standing-jump trials. On new training start 273101, the original flight phase continued until 2.424 s. Raising the touchdown COM threshold from 0.478 to 0.85 m moved landing to 1.672 s. That alone still failed every eight-second probe. Positive capture-point feedback plus the existing rise-to-crouch keyframe moved the next transition to 1.972 s and kept 7/8 probe starts legal for eight seconds.','', '**Recovery pure search.** The explicit original take-off contraction keyframes are followed by the earlier sensed landing and a balanced-crouch target. Phase-indexed bounded hip, knee, spine, and shoulder offsets are searched along with twelve launch, landing, and standing parameters. This is the same private controller implementation in a new frozen binary copy, with the opt-in recovery phase enabled. No shared SDK, task, body, or existing trial changes are involved.','', '**Recovery temporal residual.** The same backbone uses the existing causal convolution features of contractions, velocities, acceleration, jerk, and sensors. Its twenty output weights start at zero; ES trains those weights and the identical twelve backbone parameters. The four offsets remain bounded at 0.6/0.6/0.4/0.6 rad and pass through geometry conversion and correction springs. Convolution filters remain fixed.','', 'Both searches use 2,048 rollouts, eight training starts 273101–273108, optimizer seed 270929, initial normalized sigma 0.015, and the same risk-0.5 aggregation. The objective rewards legal distance at both three and eight seconds and includes the same impact/loading penalty. The preceding 64 diagnostic rollouts are additional shared setup work. Validation uses 32 fresh starts 274101–274132; longer checks use the first eight of those starts for twenty seconds.','', '### Arena verdicts','', 'Each candidate was entered before any second-round promotion, against the round-start champions. Failed guards score -1e9; large differences below are guard-coded scores, not metres. The unchanged arena samples 4,000 sign flips, so a sampled p of zero is not an exact mathematical zero.','', '| Trial | Candidate | Valid starts | Mean valid mark, m | Paired difference | p | Verdict |','|---|---|---:|---:|---:|---:|---|']
    for r in arena['entries']:
        mean='—' if r['mean_valid'] is None else f"{r['mean_valid']:.4f}"
        lines.append(f"| {r['trial']} | {r['variant']} | {r['passes']}/{r['n']} | {mean} | {r['mean_diff']:+.6g} | {r['p']:.5f} | {'WIN' if r['wins'] else 'LOSE'} |")
    lines+=['','### Fresh validation and attribution','','| Controller | Legal at 3 s | Mean legal mark at 3 s | Legal at 8 s | Mean legal mark at 8 s | Mean peak GRF, BW | Mean peak loading, BW/s |','|---|---:|---:|---:|---:|---:|---:|']
    for key in ['original','pure_start','pure_candidate','tcn_candidate','tcn_bias_only','tcn_zero_head']:
        r=validation[key];m3='—' if r['mark3'] is None else f"{r['mark3']:.3f}";m8='—' if r['mark8'] is None else f"{r['mark8']:.3f}"
        lines.append(f"| {key} | {r['legal3']}/{r['n']} | {m3} | {r['legal8']}/{r['n']} | {m8} | {r['peak_bw']:.2f} | {r['loading']:.0f} |")
    lines+=['',f"Twenty-second legality: pure **{endurance['pure']}/8**, temporal **{endurance['tcn']}/8**. These are finite checks, not a guarantee of indefinite balance.",'',f"Temporal output magnitude, hip / knee / spine / shoulder: sampled peak **{' / '.join(f'{v:.2f}' for v in peak)} degrees**; full-rollout RMS **{' / '.join(f'{v:.2f}' for v in rms)} degrees**. These are requested joint-equivalent offsets sampled at 10 Hz before geometry and spring filtering. Zero-head and bias-only rows retain the tuned backbone, isolating the residual and its time dependence.",'','### Direct temporal-versus-pure arena comparison','','| Trial | TCN minus pure | p | TCN wins |','|---|---:|---:|---|']
    for r in arena['tcn_vs_pure']:lines.append(f"| {r['trial']} | {r['mean_diff']:+.6g} | {r['p']:.5f} | {r['wins']} |")
    lines+=['','### New champion videos','', 'Each video shows twenty seconds on the declared arena seed, including the motion after the scoring horizon.','']
    for r in pro:lines.append(f"- **{r['trial']}**, {r['variant']}, seed {r['seed']}: [full video]({r['video']}); [contact sheet]({r['sheet']}).")
    lines+=['','The original six-challenger evidence remains in `out/competitor_20260927`. This continuation has its own protocols, frozen hashes, diagnostic probes, complete search archives, fresh validation, ablations, arena rows, and long-horizon traces in `out/competitor_jump_round2`.','']
    report=ROOT/'GPT_CHALLENGERS_20260927.md';s=report.read_text();marker='## Round 2: recovery and the original jump trials'
    if marker in s:s=s[:s.index(marker)]
    s=s.replace('## Conclusion\n','## Round 1 conclusion\n');report.write_text(s.rstrip()+'\n\n'+'\n'.join(lines).replace('unbeatен','unbeaten'))
    print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
