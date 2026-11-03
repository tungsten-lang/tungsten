"""Audit and report the fixed round-nine crossover experiment."""
import collections,json,math,statistics,subprocess
from pathlib import Path
import imageio.v2 as imageio
import numpy as np
import arena
from search import read_params
from gpt_dribble_catch import ROOT,OUT,TRAIN,VALID,PREFLIGHT,BUDGET,NAMES,initial,score,compact,read,write,sha
from gpt_dribble_catch_judge import check_frozen,TRIALS

def main():
    reg=check_frozen();training={v:read(OUT/f'{v}.json') for v in ['pure','tcn']};validation=read(OUT/'validation.json');a=read(OUT/'arena_summary.json');promotions=read(OUT/'promotions.json');checks={};detail={}
    baseline=read(ROOT/'out/competitor_20260927/baseline_files.json');allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    drift=[p for p,h in baseline.items() if p not in allowed and sha(ROOT/p)!=h];checks['inherited_files_unchanged']=not drift;detail['unexpected_changes']=drift
    checks['existing_trials_unchanged']=(ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    manifests=['competitor_20260927/frozen_manifest.json','competitor_20260927/final_manifest.json']
    for round in range(2,9):
        d=ROOT/f'out/competitor_jump_round{round}'
        for f in ['manifest.json','judge_manifest.json','support/manifest.json','support/judge_manifest.json']:
            if (d/f).exists():manifests.append(str((d/f).relative_to(ROOT/'out')))
    manifests+=['competitor_dribble_round9/manifest.json','competitor_dribble_round9/judge_manifest.json']
    drift=[p for f in manifests for p,h in read(ROOT/'out'/f).items() if sha(ROOT/p)!=h];checks['frozen_manifest_chain_matches']=not drift;detail['hash_drift']=drift
    preflight=read(OUT/'preflight.json');checks['all_sixteen_preflight_checks_pass']=preflight['passed'] and len(preflight['checks'])==16 and all(preflight['checks'].values())
    detail['preflight']=preflight
    checks['matched_1024_rollout_budgets']=all(t['used']==t['budget']==BUDGET and t['seed']==280933 and t['method']=='oneplusone' and len(t['metrics'])==len(TRAIN) for t in training.values())
    checks['same_twenty_eight_dimensions_and_ranges']=all(set(read(OUT/f'{v}_representation.json')['names'])==set(NAMES) for v in training)
    reps={v:read(OUT/f'{v}_representation.json') for v in training};checks['same_twenty_eight_dimensions_and_ranges']&=all(reps['pure'][k]==reps['tcn'][k] for k in ['names','lo','hi'])
    z={v:initial(v) for v in training};checks['common_zero_head_initialization']=all(z['pure'][k]==z['tcn'][k] for k in z['pure'] if k!='gpt_temporal') and all(z[v][f'gpt_w{i}']==0 for v in z for i in range(20)) and all(all(reps[v]['initial'][k]==value for k,value in z[v].items()) for v in z) and all(reps['pure']['initial'][k]==reps['tcn']['initial'][k] for k in reps['pure']['initial'] if k!='gpt_temporal')
    checks['training_objective_recomputes']=all(math.isclose(t['best'],.5*(statistics.mean(score(m) for m in t['metrics'])+min(score(m) for m in t['metrics'])),abs_tol=1e-9,rel_tol=0) for t in training.values())
    checks['archives_complete_and_finite']=all(np.load(OUT/f'{v}.npz')['X'].shape==(BUDGET//len(TRAIN),len(NAMES)) and np.load(OUT/f'{v}.npz')['F'].shape==(BUDGET//len(TRAIN),) and np.isfinite(np.load(OUT/f'{v}.npz')['F']).all() for v in training)
    checks['only_declared_parameters_changed']=all(all(r['params'].get(k)==value for k,value in initial(r['variant']).items() if k not in NAMES) for r in reg)
    checks['selected_candidates_frozen_exactly']=all(r['params']==training[r['variant']]['params']==read_params(r['params_file']) for r in reg)
    checks['both_frozen_binary_copies_match_new_build']=len({sha(r['controller']) for r in reg}|{sha(ROOT/'bin/robolab_gpt_dribble_catch')})==1
    labels=set(read(OUT/'protocol.json')['validation_groups']);checks['eight_fresh_groups_complete']=len(validation)==len(VALID)*len(labels) and {r['label'] for r in validation}==labels and all({r['seed'] for r in validation if r['label']==k}==set(VALID) for k in labels)
    old=set()
    for f in (ROOT/'out').glob('competitor*/**/*protocol.json'):
        if f==OUT/'protocol.json':continue
        for k,v in read(f).items():
            if k in ['training_seeds','validation_seeds','training','validation','pilot_seeds','parity_seeds','endurance_seeds'] and isinstance(v,list):old.update(x for x in v if isinstance(x,int))
    old.update(s for t in read(ROOT/'playground/arena/trials.json').values() for s in t['seeds'])
    checks['training_validation_preflight_disjoint_and_fresh']=not set(TRAIN)&set(VALID) and not set(PREFLIGHT)&(set(TRAIN)|set(VALID)) and not (set(TRAIN)|set(VALID)|set(PREFLIGHT))&old
    ms=[m for t in training.values() for m in t['metrics']]+[r['metrics'] for r in validation]
    checks['all_runs_complete_without_error']=all('error' not in m and 15<=m['time']<15.02 for m in ms)
    checks['full_motion_metrics_finite']=all(all(isinstance(m.get(k),(int,float)) and math.isfinite(m[k]) for k in ['controlled_s','x_ok','dribbles','peak_grf_bw','peak_loading_bw_s','trunk_share_upper','trunk_share_if_dribbling']) for m in ms)
    checks['bounded_residuals']=all(len(m['residual_peak_rad'])==4 and all(math.isfinite(x) and 0<=x<=b+1e-9 for x,b in zip(m['residual_peak_rad'],[.18,.18,.25,.18])) for m in ms)
    checks['conditional_arms_metric_recomputes']=all(m['trunk_share_if_dribbling']==(m['trunk_share_upper'] if m['dribbles']>=10 else 1.) for m in ms)
    effects={}
    for left,right in [('pure','pure_right_phase'),('pure','pure_bias'),('tcn','tcn_bias'),('tcn','tcn_zero')]:
        x=np.load(OUT/f'validation_{left}.npz');y=np.load(OUT/f'validation_{right}.npz')
        effects[left+'_vs_'+right]={k:float(np.max(np.abs(x[k]-y[k]))) for k in ['command','measured','activation','q']}
    detail['actual_motion_ablation_effects']=effects
    checks['temporal_readout_changes_actual_motion']=all(v>1e-8 for v in effects['tcn_vs_tcn_zero'].values())
    before=read(OUT/'champions_before.json');main=read(OUT/'main_champions_before.json');decisions=[]
    for r in a['entries']:
        e=read(OUT/f"arena_{r['trial']}_{r['label']}.json")
        decisions.extend([arena.compare(e['trial'],before[r['trial']]['scores'],e['scores'])==r['local'],arena.compare(e['trial'],main[r['trial']]['scores'],e['scores'])==r['main_frontier']])
    checks['all_six_arena_verdicts_recompute']=len(a['entries'])==6 and all(decisions)
    checks['main_incumbents_replay_exactly']=all(read(OUT/'main_replay.json')[t]['scores']==main[t]['scores'] for t in TRIALS)
    checks['promotions_beat_both_incumbents']=all(p['local']['wins'] and p['main_frontier']['wins'] for p in promotions)
    bylabel={r['label']:r for r in reg};checks['promoted_frozen_copies_match']=all(sha(ROOT/p['champion']['frozen_controller'])==bylabel[p['label']]['controller_sha256'] and sha(ROOT/p['champion']['frozen_params'])==bylabel[p['label']]['params_sha256'] for p in promotions)
    checks['gpt_names_and_notes']=all(Path(r['controller']).name.startswith('gpt-dribble-catch-') for r in reg) and all(p['champion']['note'].startswith('gpt:') for p in promotions)
    if promotions:
        log=(OUT/'recheck_promoted.log').read_text();checks['promoted_replays_exact']=all(any(line.startswith(p['trial']+':') and line.endswith('  OK') for line in log.splitlines()) for p in promotions) and 'DRIFT' not in log
    videos=[]
    for p in promotions:
        path=Path(p['video']);reader=imageio.get_reader(path);meta=reader.get_meta_data();frames=0
        for frame in reader:assert frame.shape==(448,800,3);frames+=1
        reader.close();m=read(path.with_suffix('.json'))['metrics']
        entry=read(OUT/f"promoted_{p['trial']}_{p['label']}.json");metric=entry['trial']['metric'];idx=entry['trial']['seeds'].index(p['seed'])
        assert m[metric]==entry['rows'][idx][metric]
        assert frames/meta['fps']>=m['time']-.04
        videos.append({'file':str(path),'frames':frames,'fps':meta['fps'],'seconds':frames/meta['fps'],'seed':p['seed'],'x_ok':m['x_ok'],'controlled_s':m['controlled_s'],'lost':m.get('lost'),'fell':m.get('fell')})
    write('video_audit.json',videos);checks['new_champion_videos_fully_decoded_and_replay_metric']=len(videos)==len(promotions)
    geometry=read(OUT/'saved_geometry_diagnosis.json');checks['saved_geometry_sources_pinned']=len(geometry['rows'])==4 and all(sha(r['source'])==r['source_sha256'] for r in geometry['rows'])
    figure=read(OUT/'geometry_figure_verification.json');checks['diagnostic_figure_visually_checked']=figure['passed'] and sha(figure['file'])==figure['sha256']
    checks['no_commits']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()=='85e95c33680a0e04bb4245de3fe86e2ae3c3200a'
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    audit={'passed':all(checks.values()),'checks':checks,'details':detail};write('audit.json',audit);assert audit['passed'],{k:v for k,v in checks.items() if not v}
    val={k:compact([r for r in validation if r['label']==k]) for k in dict.fromkeys(r['label'] for r in validation)}
    residual={}
    for v in training:
        m=[r['metrics'] for r in validation if r['label']==v]
        residual[v]={'sampled_peak_degrees':np.degrees(np.max([x['residual_peak_rad'] for x in m],axis=0)).tolist(),'rms_degrees':np.degrees(np.sqrt(np.mean(np.array([x['residual_rms_rad'] for x in m])**2,axis=0))).tolist(),'mean_arm_excursion_share':{k:statistics.mean(x['split']['arm_excursion_share'].get(k,0) for x in m) for k in ['shoulder','elbow','wrist','fingers']}}
    failures={k:{'lost_reasons':dict(collections.Counter(r['metrics'].get('lost') or 'not lost' for r in validation if r['label']==k)),'fell_seeds':[r['seed'] for r in validation if r['label']==k and r['metrics'].get('fell')],'fewer_than_ten_dribbles':[r['seed'] for r in validation if r['label']==k and r['metrics']['dribbles']<10]} for k in val}
    diagnostics=[]
    for left,right in [('tcn','pure'),('tcn','previous'),('pure','previous'),('pure','pure_right_phase'),('tcn','tcn_bias')]:
        for metric in ['x_ok','controlled_s']:
            scores=lambda label:[next(r['metrics'][metric] for r in validation if r['label']==label and r['seed']==s) for s in VALID]
            diagnostics.append({'comparison':left+' minus '+right,'metric':metric,**arena.compare({'higher':True},scores(right),scores(left))})
    summary={'arena':a,'validation':val,'training':{v:compact([{'metrics':m} for m in t['metrics']]) for v,t in training.items()},'residual':residual,'promotions':promotions,'failures':failures,'validation_comparisons':diagnostics,'audit_passed':True};write('summary.json',summary)
    lines=['## Round 9: sustained crossover catching','','Both contenders start from the same previously selected crossover backbone with twenty zero residual weights. The pure contender now conditions its bounded shoulder, elbow and wrist offsets on the active hand\'s motion phase. The temporal contender uses fixed causal convolution features of measured muscle contraction, derivatives and ball state with a learned bounded readout. The explicit contraction/keyframe choreography and reflex layer remain the backbone; neither controller emits raw activations. The inherited trunk pump and paddle-hand mechanics remain.','','Each receives **1,024 rollouts on eight new starts**, (1+1)-ES seed 280933, sigma .025, with the same mean/worst-start aggregate. They tune the same eight catch-feedback parameters and twenty residual weights. Training rewards successful crossovers and duration of control while penalizing failed moves, missed-catch distance, body contacts, drift, apex variability and whole-rollout force/loading. One best training policy per family is frozen before **32 untouched validation starts**. This is a matched-compute comparison from a common starting motion; the predecessor has a separate training history.','','### Arena verdicts','','| Trial | Family | Mean score | Local paired gain | Local p | Local win | Main paired gain | Main p | Main win |','|---|---|---:|---:|---:|---|---:|---:|---|']
    for e in a['entries']:
        l=e['local'];m=e['main_frontier'];lines.append(f"| {e['trial']} | {e['label']} | {e['mean_valid']} | {l['mean_diff']:+.6f} | {l['p']} | {l['wins']} | {m['mean_diff']:+.6f} | {m['p']} | {m['wins']} |")
    lines+=['','The arms-only trial is a **conditional penalty score, lower is better**: runs below ten dribbles receive 1.0. It is not raw trunk activation share. Paired gains are oriented so positive favors the challenger. All six entries precede promotion; promotion requires beating both recorded incumbents. p=0 means zero of 4,000 sampled sign flips, not an exact zero probability. Tests are unadjusted exploratory comparisons.','','### Fresh validation and ablations','','| Controller | Crossovers | Control, s | Dribbles | Runs ≥10 | Raw trunk share | Conditional score | Lost |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for k,v in val.items():lines.append(f"| {k} | {v['x_ok']:.4f} | {v['controlled_s']:.4f} | {v['dribbles']:.4f} | {v['at_least_ten_dribbles']}/{v['n']} | {v['trunk_share_upper']:.5f} | {v['trunk_share_if_dribbling']:.5f} | {v['lost']}/{v['n']} |")
    lines+=['','The common-zero policy restores the shared starting movement. Bias-only and zero-head ablations retain tuned catch feedback. The pure right-phase ablation alone restores the old phase selection. The previous champion is evaluated unchanged on the same fresh starts.','','### Direct architecture comparison','','| Trial | Temporal minus pure, oriented gain | p | Temporal wins |','|---|---:|---:|---|']
    for d in a['comparisons']:lines.append(f"| {d['trial']} | {d['mean_diff']:+.6f} | {d['p']} | {d['wins']} |")
    won=[d['trial'] for d in a['comparisons'] if d['wins']]
    lines += ['',f"**Learned residual versus pure search.** Temporal wins the direct arena comparison on {', '.join(won) if won else 'none of the tested trials'}. On the same 32 fresh starts it averages {val['tcn']['x_ok']:.4f} crossovers versus {val['pure']['x_ok']:.4f} for the corrected active-hand phase baseline. Temporal bias-only and zero-head ablations average {val['tcn_bias']['x_ok']:.4f} and {val['tcn_zero']['x_ok']:.4f}; the earlier champion averages {val['previous']['x_ok']:.4f}. Restoring the old right-hand-only phase in the newly trained pure policy reduces it to {val['pure_right_phase']['x_ok']:.4f}. These ablations support contributions from both the active-phase correction and temporal inputs in the tested policies. They are interventions on selected weights, not separately retrained equal-budget architectures. The pure-versus-temporal contenders themselves have matched budgets and a common starting movement. Every fresh selected run still loses the ball; this is an improvement in finite control, not sustained fifteen-second control or general neural superiority.",'']
    lines+=['','### Residual magnitude and measured movement','']
    for k,v in residual.items():lines.append(f"- {k}, shoulder flexion / shoulder abduction / elbow / wrist: sampled peak **{' / '.join(f'{x:.2f}' for x in v['sampled_peak_degrees'])}°**, RMS **{' / '.join(f'{x:.2f}' for x in v['rms_degrees'])}°**. Mean measured arm-excursion shares: {v['mean_arm_excursion_share']}.")
    lines+=['','Offsets are limited to .18 / .18 / .25 / .18 radians and act through geometry conversion and spring filtering. The 10 Hz diagnostic peaks are sampled requests, not continuous maxima. Exact preflight tests preserve zero-head and disabled-mode trajectories. Nonzero active-phase changes first appear when the receiving left hand recovers; temporal mode is exactly independent of this phase argument. Full-horizon commands, activations and measured joint motion are compared in the audit.','','### Failures and champion videos','']
    lines += ['**Separate consumed-start diagnosis.** Offline forward kinematics of two predecessor traces shows one outgoing pass remaining on the wrong side, and another dropping low and forward beyond the receiving stroke. These sampled geometric gaps are not official force-threshold contacts and are not new validation. They motivate a later outgoing-stroke or recovery-selection experiment without changing this round. [Measured trajectory figure]('+str(OUT/'saved_crossover_geometry.png')+') and [source-pinned replay evidence]('+str(OUT/'saved_geometry_diagnosis.json')+').','']
    for k in ['pure','tcn','previous']:lines.append(f"- {k}: losses {failures[k]['lost_reasons']}; fallen starts {failures[k]['fell_seeds']}.")
    if not promotions:lines.append('No qualifying promotion. Previous champions remain in place.')
    for p,v in zip(promotions,videos):lines.append(f"- {p['trial']}, {p['label']}, seed {p['seed']}: [full fifteen-second video]({p['video']}) and [contact sheet]({p['sheet']}). {v['x_ok']} crossovers; control {v['controlled_s']} s; loss: {v['lost']}; fell: {v['fell']}.")
    lines+=['',f"All **{len(checks)} audit checks** pass. [Complete evidence]({OUT/'summary.json'}), [audit]({OUT/'audit.json'}), [frozen candidates]({OUT/'candidates.json'}). Existing trials, shared SDK and physics are unchanged; no commits. Finite crossover results do not establish indefinite ball control or a complete arms-only/finger technique.",'']
    (OUT/'REPORT.md').write_text('\n'.join(lines));print(json.dumps({'passed':True,'checks':len(checks),'validation':{k:val[k] for k in ['pure','tcn','previous']},'promotions':[(p['trial'],p['label']) for p in promotions]},indent=2))
if __name__=='__main__':main()
