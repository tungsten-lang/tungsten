"""Audit round-six frozen artifacts and write a standalone evidence appendix."""
import json,math,statistics,subprocess
from pathlib import Path
import imageio.v2 as imageio
import numpy as np
import arena
from gpt_jump_support_refine import ROOT,OUT,TRAIN,VALID,BUDGET,NAMES,read,write,sha,initial,check_manifest
from gpt_jump_support_refine_judge import check_frozen
from gpt_jump_support_validate import compact
from gpt_jump_recover import legal
from search import read_params

def pv(p):return '0 / 4,000 sampled flips' if p==0 else f'{p:.5f}'
def main():
    registry=check_frozen();checks={};details={};baseline=read(ROOT/'out/competitor_20260927/baseline_files.json')
    allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    changes=[p for p,h in baseline.items() if p not in allowed and sha(ROOT/p)!=h];checks['inherited_files_unchanged']=not changes;details['unexpected_changes']=changes
    checks['trial_definitions_unchanged']=(ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    manifests=['competitor_20260927/frozen_manifest.json','competitor_20260927/final_manifest.json','competitor_jump_round2/manifest.json','competitor_jump_round3/manifest.json','competitor_jump_round4/manifest.json','competitor_jump_round4/judge_manifest.json','competitor_jump_round5/manifest.json','competitor_jump_round5/support/manifest.json','competitor_jump_round5/support/judge_manifest.json','competitor_jump_round6/manifest.json','competitor_jump_round6/judge_manifest.json']
    drift=[p for f in manifests for p,h in read(ROOT/'out'/f).items() if sha(ROOT/p)!=h];checks['all_frozen_manifests_match']=not drift;details['hash_drift']=drift
    training={v:read(OUT/f'{v}.json') for v in ['pure','tcn']}
    checks['matched_search_budgets']=all(r['used']==r['budget']==BUDGET and r['method']=='oneplusone' and r['seed']==280930 and len(r['metrics'])==len(TRAIN) for r in training.values())
    checks['twelve_dimensions_each']=all(set(read(OUT/f'{v}_representation.json')['names'])==set(NAMES) for v in training)
    checks['complete_search_archives_finite']=all(np.load(OUT/f'{v}.npz')['X'].shape==(BUDGET//len(TRAIN),len(NAMES)) and np.load(OUT/f'{v}.npz')['F'].shape==(BUDGET//len(TRAIN),) and np.isfinite(np.load(OUT/f'{v}.npz')['F']).all() and bool((np.load(OUT/f'{v}.npz')['F']>-1e6).all()) for v in training)
    checks['only_declared_parameters_changed']=all(all(r['params'].get(k)==value for k,value in initial(r['variant']).items() if k not in NAMES) for r in registry)
    checks['frozen_candidates_equal_selected_training']=all(r['params']==training[r['variant']]['params']==read_params(r['params_file']) for r in registry)
    checks['frozen_copy_equals_support_build']=all(sha(r['controller'])==sha(ROOT/f"bin/challengers/gpt-jump-support-{r['variant']}") for r in registry)
    validation=read(OUT/'validation.json');long=read(OUT/'endurance20.json');a=read(OUT/'arena_summary.json');promotions=read(OUT/'promotions.json')
    labels={'pure','pure_previous','pure_static','tcn','tcn_previous','tcn_static','tcn_bias','tcn_zero','p6_reference'}
    checks['fresh_validation_complete']=len(validation)==64*len(labels) and {r['label'] for r in validation}==labels and all({r['seed'] for r in validation if r['label']==label}==set(VALID) for label in labels)
    checks['long_validation_complete']=len(long)==16 and all({r['seed'] for r in long if r['label']==label}==set(VALID[:8]) for label in ['pure','tcn'])
    old=set()
    for f in ['competitor_20260927/protocol.json','competitor_jump_round2/protocol.json','competitor_jump_round3/protocol.json','competitor_jump_round4/protocol.json','competitor_jump_round5/protocol.json','competitor_jump_round5/support/protocol.json','competitor_jump_round5/support/validation_protocol.json']:
        for k,v in read(ROOT/'out'/f).items():
            if k in ['training_seeds','validation_seeds','training','validation','pilot_seeds','parity_seeds','endurance_seeds'] and isinstance(v,list):old.update(v)
    old.update(range(279001,279003));old.update(range(279101,279109));old.update(range(281101,281165))
    old.update(s for t in read(ROOT/'playground/arena/trials.json').values() for s in t['seeds'])
    checks['fresh_seeds_disjoint']=not set(TRAIN)&set(VALID) and not (set(TRAIN)|set(VALID))&old
    metrics=[m for r in training.values() for m in r['metrics']]+[r['metrics'] for r in validation+long]
    checks['no_simulation_errors']=not any('error' in m for m in metrics)
    checks['full_motion_metrics_finite']=all(all(isinstance(m.get(k),(int,float)) and math.isfinite(m[k]) for k in ['time','mark','peak_grf_bw','peak_loading_bw_s','takeoff_vx','takeoff_vz']) for m in metrics)
    checks['bounded_residuals']=all(len(m['residual_peak_rad'])==4 and all(math.isfinite(x) and 0<=x<=b+1e-9 for x,b in zip(m['residual_peak_rad'],[.6,.6,.4,.6])) for m in metrics)
    params={r['label']:r['params'] for r in registry}
    checks['support_event_limits']=all(all(len(e)==5 and all(math.isfinite(x) for x in e) and e[1]>=params[r['label']]['gpt_support_time']-1e-8 and e[2]<params[r['label']]['gpt_support_height'] and abs(e[4]-params[r['label']]['gpt_support_gain'])<1e-8 and .4<=e[4]<=1.4 for e in r['metrics']['capture_events']) for r in validation+long if r['label'] in params)
    full=np.load(OUT/'validation_tcn.npz');zero=np.load(OUT/'validation_tcn_zero.npz');effects={k:float(np.max(np.abs(full[k]-zero[k]))) for k in ['command','measured','activation','q']}
    details['head_effects']=effects;checks['temporal_head_changes_measured_motion']=all(v>1e-8 for v in effects.values())
    before=read(OUT/'champions_before.json');main=read(OUT/'main_champions_before.json');decisions=[]
    for r in a['entries']:
        entry=read(OUT/f"arena_{r['trial']}_{r['label']}.json")
        decisions.append(arena.compare(entry['trial'],before[r['trial']]['scores'],entry['scores'])==r['local'])
        if r['trial'] in main:decisions.append(arena.compare(entry['trial'],main[r['trial']]['scores'],entry['scores'])==r['main_frontier'])
    checks['six_arena_entries_recompute']=len(a['entries'])==6 and all(decisions)
    checks['p6_exact_replay']=read(OUT/'p6_arena_replay.json')['scores']==main['search_jump_robust_legal']['scores']
    checks['promotions_beat_both_incumbents']=all(r['local']['wins'] and (r['main_frontier'] is None or r['main_frontier']['wins']) for r in promotions)
    reg={r['label']:r for r in registry}
    checks['promoted_copies_match']=all(sha(ROOT/r['champion']['frozen_controller'])==reg[r['label']]['controller_sha256'] and sha(ROOT/r['champion']['frozen_params'])==reg[r['label']]['params_sha256'] for r in promotions)
    checks['gpt_names_and_notes']=all(Path(r['champion']['controller']).name.startswith('gpt-jump-support-refine-') and r['champion']['note'].startswith('gpt:') for r in promotions)
    if promotions:
        log=(OUT/'recheck_promoted.log').read_text();checks['promoted_replays_exact']=all(any(line.startswith(r['trial']+':') and line.endswith('  OK') for line in log.splitlines()) for r in promotions) and 'DRIFT' not in log
    videos=[]
    for r in promotions:
        p=Path(r['video']);reader=imageio.get_reader(p);meta=reader.get_meta_data();frames=0
        for frame in reader:assert frame.shape==(448,800,3);frames+=1
        reader.close();m=read(p.with_suffix('.json'))['metrics'];assert frames/meta['fps']>=m['time']-.04
        videos.append({'file':str(p),'frames':frames,'fps':meta['fps'],'seconds':frames/meta['fps'],'simulation_seconds':m['time'],'seed':r['seed'],'legal_at_end':legal(m)})
    write('video_audit.json',videos);checks['all_promoted_videos_decoded']=len(videos)==len(promotions)
    checks['no_commits']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()=='85e95c33680a0e04bb4245de3fe86e2ae3c3200a'
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    audit={'passed':all(checks.values()),'checks':checks,'details':details};write('audit.json',audit);assert audit['passed'],checks
    val={k:compact([r for r in validation if r['label']==k]) for k in dict.fromkeys(r['label'] for r in validation)}
    endurance={v:compact([r for r in long if r['label']==v],20) for v in ['pure','tcn']}
    ms=[r['metrics'] for r in validation if r['label']=='tcn'];residual={'sampled_peak_degrees':np.degrees(np.max([m['residual_peak_rad'] for m in ms],axis=0)).tolist(),'rms_degrees':np.degrees(np.sqrt(np.mean(np.array([m['residual_rms_rad'] for m in ms])**2,axis=0))).tolist()}
    failures={label:{h:{k:[r['seed'] for r in validation if r['label']==label and (r['metrics']['three_second'] if h=='three_second' else r['metrics']).get(k)] for k in ['fallen','foul','inverted']} for h in ['three_second','eight_second']} for label in ['pure','tcn']}
    retention={}
    for horizon,rows in [(8,validation),(20,long)]:
        for label in ['pure','tcn']:
            both=[r for r in rows if r['label']==label and legal(r['metrics']) and legal(r['metrics']['three_second'])]
            drops=[r['metrics']['three_second']['mark']-r['metrics']['mark'] for r in both]
            retention[f'{label}_{horizon}s']={'n_legal_at_both':len(both),'mean_mark3_same_starts':statistics.mean(r['metrics']['three_second']['mark'] for r in both) if both else None,'mean_final_same_starts':statistics.mean(r['metrics']['mark'] for r in both) if both else None,'mean_mark_drop':statistics.mean(drops) if drops else None,'max_mark_drop':max(drops) if drops else None,'drops_over_1cm':[{'seed':r['seed'],'mark3':r['metrics']['three_second']['mark'],'mark_final':r['metrics']['mark']} for r in both if r['metrics']['three_second']['mark']-r['metrics']['mark']>.01]}
    write('distance_retention.json',retention)
    evidence={'arena':a,'validation':val,'endurance20':endurance,'residual':residual,'promotions':promotions,'failures':failures,'distance_retention':retention,'training':{v:compact([{'metrics':m} for m in training[v]['metrics']]) for v in training},'audit_passed':True};write('summary.json',evidence)
    lines=['## Round 6: launch and conditional-support refinement','','Round 5 restored 32/32 short-horizon legality but did not decisively beat P6. This round starts from its pure and temporal recovery candidates and tunes twelve explicit launch, recovery-pose, and conditional-support parameters. Contraction keyframe vectors and inherited learned heads remain frozen.','','**Pure search.** Retain the phase-indexed correction model and measured landing-depth gate. Tune crouch and extension duration, takeoff height, hip/arm drive, recovery duration and hip/knee/ankle posture, plus gate delay, height, and gain.','','**Temporal residual.** Tune the identical twelve explicit parameters around the earlier causal-convolution policy. Its twenty learned readout weights remain frozen. This is equal-budget refinement of two previously trained policies, not a common-initialization neural architecture experiment.','','Each family receives **4,096 rollouts on 32 new starts (282101–282132)**, (1+1)-ES seed 280930, normalized sigma .008, risk .5. The score prioritizes three-second legality and distance, rewards eight-second legality and mark, and penalizes full-rollout peak force and loading. Exactly one best training candidate per family is frozen before **64 untouched starts (283101–283164)**. P6 is a separately trained incumbent.','','### Arena outcomes','','All six entries precede promotion. A candidate must beat both the worktree and recorded main incumbent where both exist. Large guard-scored differences are not metres. The arena uses unadjusted sign-flip comparisons.','','| Trial | Family | Valid | Mean valid mark, m | Local diff | Local p | Local verdict | Main diff | Main p | Main verdict |','|---|---|---:|---:|---:|---:|---|---:|---:|---|']
    for r in a['entries']:
        l=r['local'];m=r['main_frontier'];front='— | — | —' if m is None else f"{m['mean_diff']:+.9g} | {pv(m['p'])} | {'WIN' if m['wins'] else 'LOSE'}"
        lines.append(f"| {r['trial']} | {r['variant']} | {r['passes']}/{r['n']} | {r['mean_valid'] if r['mean_valid'] is not None else '—'} | {l['mean_diff']:+.9g} | {pv(l['p'])} | {'WIN' if l['wins'] else 'LOSE'} | {front} |")
    lines+=['','### Fresh validation and ablations','','| Controller | Legal 3 s | Mean legal 3 s mark, m | Legal 8 s | Mean legal 8 s mark, m | Gate triggered | Peak force, BW | Loading, BW/s |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for k,v in val.items():lines.append(f"| {k} | {v['legal3']}/{v['n']} | {v['mean3']} | {v['legal_final']}/{v['n']} | {v['mean_final'] if v['mean_final'] is not None else '—'} | {v['capture_count']}/{v['n']} | {v['peak_bw']:.2f} | {v['loading']:.1f} |")
    lines+=['','Static recovery applies the selected time and gain on every landing. Bias-only and zero-head ablations retain the tuned backbone and gate. Conditional means exclude invalid starts; arena decisions include all failures.','', '### Longer recovery and correction magnitudes','']
    for k,v in endurance.items():lines.append(f"- {k}: **{v['legal_final']}/{v['n']}** legal at twenty seconds.")
    for k,v in retention.items():
        lines.append(f"- {k}, same starts legal at both horizons (n={v['n_legal_at_both']}): mean mark drop after three seconds **{v['mean_mark_drop']} m**, maximum **{v['max_mark_drop']} m**. [Per-seed distance retention]({OUT/'distance_retention.json'}).")
    lines.append(f"- Temporal hip/knee/spine/shoulder: sampled peak **{' / '.join(f'{x:.2f}' for x in residual['sampled_peak_degrees'])}°**, RMS **{' / '.join(f'{x:.2f}' for x in residual['rms_degrees'])}°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.")
    lines+=['','### Direct temporal minus pure comparisons','','| Trial | Oriented paired diff | p | Temporal wins |','|---|---:|---:|---|']
    for r in a['comparisons']:lines.append(f"| {r['trial']} | {r['mean_diff']:+.9g} | {pv(r['p'])} | {r['wins']} |")
    lines+=['','### New champion videos, failure evidence, and audit','']
    for r,v in zip(promotions,videos):lines.append(f"- {r['trial']}, **{r['label']}**, seed {r['seed']}: [twenty-second video]({r['video']}) and [contact sheet]({r['sheet']}); legal at the end: **{v['legal_at_end']}**.")
    if not promotions:lines.append('No candidate qualifies for promotion; earlier champions remain in place.')
    for label,by_horizon in failures.items():
        for horizon,flags in by_horizon.items():lines.append(f"- {label}, {horizon}: "+'; '.join(f"{k}: {seeds}" for k,seeds in flags.items()))
    lines+=['',f"All **{len(checks)} audit checks** pass: [audit]({OUT/'audit.json'}), [complete summary]({OUT/'summary.json'}), [frozen selections]({OUT/'candidates.json'}). Shared SDK, simulator, and existing trials are unchanged; no commits or main-checkout edits. Finite recovery tests do not establish universal stability.",'']
    (OUT/'REPORT.md').write_text('\n'.join(lines));print(json.dumps({'checks':len(checks),'passed':True,'promotions':[r['trial']+':'+r['label'] for r in promotions],'validation':{v:val[v] for v in ['pure','tcn']},'endurance20':endurance},indent=2))
if __name__=='__main__':main()
