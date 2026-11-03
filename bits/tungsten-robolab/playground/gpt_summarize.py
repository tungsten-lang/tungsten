"""Summarize saved evidence using the arena's unchanged comparison function."""
import json,math
from pathlib import Path
import numpy as np
import arena
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'out/competitor_20260927'

def legal(m):return bool(m.get('takeoff')) and not any(m.get(k) for k in ('fallen','foul','inverted'))
def average(rows,key):
    values=[r[key] for r in rows if isinstance(r.get(key),(int,float,bool))]
    return float(np.mean(values)) if values else None

def physical(problem,rows):
    if problem=='jump':
        ok=[m for m in rows if legal(m)]
        return {'passes':len(ok),'n':len(rows),'mean_legal_mark':average(ok,'mark')}
    return {k:average(rows,k) for k in (['power','quality','hits','fair','hitch_full'] if problem=='bat' else ['x_ok','dribbles','controlled_s','moves_failed','x_attempts','x_rate','body_hits','trunk_share_if_dribbling','shoulder_work_share'])}

def main():
    champions=json.loads((OUT/'champions_before.json').read_text());report={'arena':[],'validation':{},'residual':{},'budgets':{},'head_to_head':[]}
    original={'jump':'search_jump_legal','bat':'bat_power','dribble':'dribble_crossover_25'}
    for problem in ['jump','bat','dribble']:
        report['validation'][problem]={};report['budgets'][problem]={}
        for variant in ['pure','tcn']:
            tag=problem+'_'+variant
            train=json.loads((OUT/(tag+'.json')).read_text())
            report['budgets'][problem][variant]={k:train[k] for k in ['used','wall','rollout_s','opt_s','best']}
            rows=json.loads((OUT/(tag+'_validate.json')).read_text())
            for kind in sorted({r['kind'] for r in rows}):
                key=variant+'_'+kind
                ms=[r['metrics'] for r in rows if r['kind']==kind]
                report['validation'][problem][key]={**physical(problem,ms),'mean_peak_grf_bw':average(ms,'peak_grf_bw'),'max_peak_grf_bw':max(m['peak_grf_bw'] for m in ms),'mean_peak_loading_bw_s':average(ms,'peak_loading_bw_s')}
            if variant=='tcn':
                ms=[r['metrics'] for r in rows if r['kind']=='candidate']
                report['residual'][problem]={'sampled_peak_rad':np.max([m['residual_peak_rad'] for m in ms],axis=0).tolist(),'rms_rad':np.sqrt(np.mean(np.array([m['residual_rms_rad'] for m in ms])**2,axis=0)).tolist(),'readout':{k:v for k,v in train['params'].items() if k.startswith('gpt_w')}}
                z=json.loads((OUT/(problem+'_tcn_zero_head.json')).read_text());report['validation'][problem]['tcn_zero_head']=physical(problem,[r['metrics'] for r in z])
        trials=['search_jump_legal','search_jump_robust_legal','gpt_jump_stable6'] if problem=='jump' else [original[problem]]
        for trial in trials:
            saved={}
            for variant in ['pure','tcn']:
                artifact=OUT/f'arena_{problem}_{variant}_{trial}.json';d=json.loads(artifact.read_text());saved[variant]=d
                baseline=json.loads((OUT/'arena_jump_stable6_baseline.json').read_text())['scores'] if trial=='gpt_jump_stable6' else champions[trial]['scores']
                comparison=arena.compare(d['trial'],baseline,d['scores'])
                passed=[x for x in d['scores'] if abs(x)<1e8]
                report['arena'].append({'problem':problem,'variant':variant,'trial':trial,**comparison,'passes':len(passed),'n':len(d['scores']),'mean_passed':float(np.mean(passed)) if passed else None,'mean_guard_coded':float(np.mean(d['scores'])),'artifact':str(artifact)})
            report['head_to_head'].append({'problem':problem,'trial':trial,**arena.compare(saved['tcn']['trial'],saved['pure']['scores'],saved['tcn']['scores'])})
    report['jump_12sec']=json.loads((OUT/'jump_12sec.json').read_text())
    (OUT/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['## Results','', 'Arena comparisons below use the original champion for both entrants. A failed guard is scored as -1e9, so large paired differences are **guard-coded scores, not metres**. The tables retain the arena\'s exact decision rule. Its p values use 4,000 sampled sign flips; a reported zero means no sampled permutation was as favorable, not a mathematical zero. These are unadjusted per-trial decisions for fixed candidates, from one optimizer seed per challenger.','', '| Trial | Challenger | Valid / total | Mean on valid starts | Paired difference | p | Verdict |','|---|---|---:|---:|---:|---:|---|']
    for r in report['arena']:
        p=f"{r['p']:.5f}" if r['p'] else '0 (0/4000 sampled flips)'
        mean='—' if r['mean_passed'] is None else f"{r['mean_passed']:.4f}"
        lines.append(f"| {r['trial']} | {r['variant']} | {r['passes']}/{r['n']} | {mean} | {r['mean_diff']:+.6g} | {p} | {'WIN' if r['wins'] else 'LOSE'} |")
    lines+=['','### Fresh validation and attribution','', 'The zero-readout ablation retains all tuned backbone parameters. The bias-only ablation additionally retains constant learned offsets but removes temporal dependence. These checks use 24 validation starts and do not enter the arena.','']
    for problem in ['jump','bat','dribble']:
        lines += [f'**{problem.capitalize()}**','', '| Controller | Fresh result |','|---|---|']
        entries=report['validation'][problem]
        for key in ['pure_baseline','pure_candidate','tcn_candidate','tcn_bias_only','tcn_zero_head']:
            r=entries[key]
            if problem=='jump':
                mean='—' if r['mean_legal_mark'] is None else f"{r['mean_legal_mark']:.3f} m"
                val=f"{r['passes']}/{r['n']} legal six-second landings; mean legal mark {mean}"
            elif problem=='bat':val=f"power {r['power']:.3f} m/s; ball quality {r['quality']:.3f}"
            else:val=f"{r['x_ok']:.3f} successful crossovers per 15 s"
            lines.append(f'| {key} | {val} |')
        head=report['residual'][problem]
        peak=np.degrees(head['sampled_peak_rad']);rms=np.degrees(head['rms_rad'])
        axes={'jump':'hip / knee / spine / shoulder flexion','bat':'spine rotation / spine flexion / elbow / wrist flexion','dribble':'shoulder flexion / shoulder abduction / elbow / wrist flexion'}[problem]
        lines+=['',f"Learned outputs ({axes}): sampled peak degrees **{' / '.join(f'{v:.2f}' for v in peak)}**; RMS degrees **{' / '.join(f'{v:.2f}' for v in rms)}**. These are requested joint-equivalent offsets logged at 10 Hz, before geometry conversion, chunk masks, and spring filtering; they are not raw activations or an exact maximum of the continuous motion.",'']
        base=entries['pure_baseline'];learned=entries['tcn_candidate']
        lines += [f"Full-rollout force telemetry, original → learned: mean peak **{base['mean_peak_grf_bw']:.2f} → {learned['mean_peak_grf_bw']:.2f} body weights**; mean peak loading rate **{base['mean_peak_loading_bw_s']:.0f} → {learned['mean_peak_loading_bw_s']:.0f} BW/s**. The learned controller's largest peak on validation was {learned['max_peak_grf_bw']:.2f} BW.",'']
    lines+=['### Twelve-second jump observation','']
    for kind in ['baseline','pure','tcn']:
        rows=[r['metrics'] for r in report['jump_12sec'] if r['kind']==kind];r=physical('jump',rows)
        lines.append(f"- {kind}: {r['passes']}/{r['n']} legal at twelve seconds.")
    lines += ['','### Budget accounting','', '| Problem | Pure rollout budget / wall seconds | TCN rollout budget / wall seconds |','|---|---:|---:|']
    for problem,r in report['budgets'].items():lines.append(f"| {problem} | {r['pure']['used']} / {r['pure']['wall']:.1f} | {r['tcn']['used']} / {r['tcn']['wall']:.1f} |")
    lines+=['','Training wall times include shared-machine contention. The pure crossover run also contains a 5,436-second gap between two generations (see `wall_clock_anomaly.json`); its cause is not established. Wall time is not a compute-speed comparison. Validation, ablations, rechecks, rendering and arena entries are additional evaluations, excluded from both matched training budgets.','', '### Learned versus pure: direct arena comparisons','', '| Trial | TCN minus pure, guard-coded where applicable | p | TCN wins the same arena test |','|---|---:|---:|---|']
    for r in report['head_to_head']:lines.append(f"| {r['trial']} | {r['mean_diff']:+.6g} | {r['p']:.5f} | {r['wins']} |")
    lines+=['','The fixed convolution filters and small learned readout limit this experiment: it does not test end-to-end convolution training, larger neural policies, or performance outside the evaluated tasks and seed distributions.','']
    document=ROOT/'GPT_CHALLENGERS_20260927.md';text=document.read_text();a=text.index('## Results');b=text.index('## Reproduction and evidence');document.write_text(text[:a]+'\n'.join(lines)+'\n'+text[b:])
    print(json.dumps({'arena':report['arena'],'head_to_head':report['head_to_head']},indent=2))
if __name__=='__main__':main()
