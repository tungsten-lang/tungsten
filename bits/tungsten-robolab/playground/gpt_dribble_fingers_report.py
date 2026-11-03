"""Audit and report the fixed round-eleven fingered-body experiment."""
import collections,json,math,statistics,subprocess
from pathlib import Path
import imageio.v2 as imageio
import numpy as np
import arena
from search import read_params
from gpt_dribble_fingers import ROOT,OUT,TRAIN,VALID,BUDGET,NAMES,OPTSEED,initial,score,compact,read,write,sha
from gpt_dribble_fingers_judge import check_frozen,TRIALS

def main():
    reg=check_frozen();training={v:read(OUT/f'{v}.json') for v in ['pure','tcn']};validation=read(OUT/'validation.json');a=read(OUT/'arena_summary.json');promotions=read(OUT/'promotions.json');checks={};detail={};endurance=read(OUT/'endurance30.json')
    recovery_dir=OUT/'recovery_20260929';recovery=read(recovery_dir/'recovery_audit.json');recovery_completion=read(recovery_dir/'completion.json');recovery_events=[json.loads(line) for line in (recovery_dir/'events.jsonl').read_text().splitlines()]
    recovery_text=recovery['disclosure']
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
    manifests+=['competitor_dribble_round10/manifest.json','competitor_dribble_round10/judge_manifest.json','competitor_dribble_round11/manifest.json','competitor_dribble_round11/judge_manifest.json']
    checks['current_manifest_matches']=all(sha(ROOT/p)==h for f in manifests[-4:] for p,h in read(ROOT/'out'/f).items())
    preflight=read(OUT/'preflight.json');checks['all_sixteen_pre_training_checks_pass']=preflight['passed'] and len(preflight['checks'])==16 and all(preflight['checks'].values())
    detail['preflight']=preflight
    checks['interrupted_temporal_log_preserved_exactly']=recovery['passed'] and recovery['interrupted_temporal_log']['bytes']==0 and sha(recovery_dir/'interrupted_tcn.jsonl')==recovery['interrupted_temporal_log']['sha256']
    checks['recovery_preserved_completed_pure_and_stale_state']=all(sha(ROOT/path)==digest for path,digest in recovery['preserved_sources_sha256'].items())
    checks['recovery_pipeline_completed_all_stages']=recovery_completion['passed'] and recovery_events[-1]['state']=='complete' and [e['stage'] for e in recovery_events if e['state']=='stage_finished' and e['returncode']==0]==[['train','tcn'],['freeze'],['validate'],['long']]
    checks['matched_4096_rollout_budgets']=all(t['used']==t['budget']==BUDGET and t['seed']==OPTSEED and t['method']=='oneplusone' and len(t['metrics'])==len(TRAIN) for t in training.values())
    checks['same_thirty_two_dimensions_and_ranges']=all(set(read(OUT/f'{v}_representation.json')['names'])==set(NAMES) for v in training)
    reps={v:read(OUT/f'{v}_representation.json') for v in training};checks['same_thirty_two_dimensions_and_ranges']&=all(reps['pure'][k]==reps['tcn'][k] for k in ['names','lo','hi'])
    checks['zero_head_initialization_exact']=all(reps[v]['initial']==initial(v) for v in training)
    checks['all_undeclared_parameters_fixed']=all(all(t['params'][k]==value for k,value in initial(v).items() if k not in NAMES) for v,t in training.items())
    checks['training_objective_recomputes']=all(math.isclose(t['best'],.5*(statistics.mean(score(m) for m in t['metrics'])+min(score(m) for m in t['metrics'])),abs_tol=1e-9,rel_tol=0) for t in training.values())
    checks['archives_complete_and_finite']=all(np.load(OUT/f'{v}.npz')['X'].shape==(BUDGET//len(TRAIN),len(NAMES)) and np.load(OUT/f'{v}.npz')['F'].shape==(BUDGET//len(TRAIN),) and np.isfinite(np.load(OUT/f'{v}.npz')['F']).all() for v in training)
    checks['only_declared_parameters_changed']=all(all(r['params'].get(k)==value for k,value in initial(r['variant']).items() if k not in NAMES) for r in reg)
    checks['selected_candidates_frozen_exactly']=all(r['params']==training[r['variant']]['params']==read_params(r['params_file']) for r in reg)
    checks['both_frozen_binary_copies_match_checked_prototype']=len({sha(r['controller']) for r in reg}|{sha(ROOT/'bin/challengers/gpt-dribble-fingers-prototype')})==1
    labels=set(read(OUT/'protocol.json')['validation_groups']);checks['seven_fresh_groups_complete']=len(validation)==len(VALID)*len(labels) and {r['label'] for r in validation}==labels and all({r['seed'] for r in validation if r['label']==k}==set(VALID) for k in labels)
    old=set()
    for f in (ROOT/'out').glob('competitor*/**/*protocol.json'):
        if f==OUT/'protocol.json':continue
        for k,v in read(f).items():
            if k in ['training_seeds','validation_seeds','training','validation','pilot_seeds','parity_seeds','endurance_seeds'] and isinstance(v,list):old.update(x for x in v if isinstance(x,int))
    old.update(s for t in read(ROOT/'playground/arena/trials.json').values() for s in t['seeds'])
    checks['training_validation_disjoint_and_fresh']=not set(TRAIN)&set(VALID) and not (set(TRAIN)|set(VALID))&old
    ms=[m for t in training.values() for m in t['metrics']]+[r['metrics'] for r in validation]
    checks['all_runs_complete_without_error']=all('error' not in m and 15<=m['time']<15.02 for m in ms)
    checks['thirty_second_three_group_checks_complete']=len(endurance)==24 and {r['label'] for r in endurance}=={'pure','tcn','common_zero'} and all({r['seed'] for r in endurance if r['label']==k}==set(VALID[:8]) for k in ['pure','tcn','common_zero']) and all('error' not in r['metrics'] and 30<=r['metrics']['time']<30.02 for r in endurance)
    ms += [r['metrics'] for r in endurance]
    checks['full_motion_metrics_finite']=all(all(isinstance(m.get(k),(int,float)) and math.isfinite(m[k]) for k in ['controlled_s','x_ok','dribbles','peak_grf_bw','peak_loading_bw_s','trunk_share_upper','trunk_share_if_dribbling']) for m in ms)
    checks['bounded_residuals']=all(len(m['residual_peak_rad'])==4 and all(math.isfinite(x) and 0<=x<=b+1e-9 for x,b in zip(m['residual_peak_rad'],[.18,.15,.2,.2])) for m in ms)
    checks['conditional_arms_metric_recomputes']=all(m['trunk_share_if_dribbling']==(m['trunk_share_upper'] if m['dribbles']>=10 else 1.) for m in ms)
    effects={}
    for left,right in [('pure','common_zero'),('pure','pure_zero'),('pure','pure_bias'),('tcn','common_zero'),('tcn','tcn_bias'),('tcn','tcn_zero')]:
        x=np.load(OUT/f'validation_{left}.npz');y=np.load(OUT/f'validation_{right}.npz')
        effects[left+'_vs_'+right]={k:float(np.max(np.abs(x[k]-y[k]))) for k in ['command','measured','activation','q']}
    detail['actual_motion_ablation_effects']=effects
    detail['shared_parameter_scope']='Finger poses affect launch as well as later strokes. Quiet trunk, stance, drive gains and all undeclared parameters stay fixed. Both contenders use the same v3 body, which differs from earlier v1 paddle-hand experiments.'
    checks['nonzero_readouts_change_actual_motion']=all(not any(abs(training[v]['params'][f'gpt_w{i}'])>1e-12 for i in range(20)) or all(x>1e-8 for x in effects[v+'_vs_'+v+'_zero'].values()) for v in training)
    checks['fingered_trace_has_39_q_coordinates']=all(np.load(OUT/f'validation_{v}.npz')['q'].shape[1]==39 for v in ['pure','tcn','common_zero'])
    import mujoco
    from tasks.dribble_v3 import TASK
    task=TASK();model=mujoco.MjModel.from_xml_string(task.xml(task.builder()))
    joints={name:int(model.joint(name).qposadr[0]) for side in ['r','l'] for name in [side+'_elbow',side+'_wrist_flex',side+'_finger_mcp',side+'_finger_pip']}
    detail['selected_vs_zero_measured_joint_effect_rad']={v:{name:float(np.max(np.abs(np.load(OUT/f'validation_{v}.npz')['q'][:,adr]-np.load(OUT/f'validation_{v}_zero.npz')['q'][:,adr]))) for name,adr in joints.items()} for v in training}
    checks['measured_joint_effects_finite']=all(math.isfinite(x) for d in detail['selected_vs_zero_measured_joint_effect_rad'].values() for x in d.values())

    checks['both_common_backbones_equal']=all(value==initial('tcn')[k] for k,value in initial('pure').items() if k!='gpt_temporal')
    before=read(OUT/'champions_before.json');main=read(OUT/'main_champions_at_judging.json');decisions=[]
    for r in a['entries']:
        e=read(OUT/f"arena_{r['trial']}_{r['label']}.json")
        decisions.extend([arena.compare(e['trial'],before[r['trial']]['scores'],e['scores'])==r['local'],arena.compare(e['trial'],main[r['trial']]['scores'],e['scores'])==r['main_frontier']])
    checks['all_six_arena_verdicts_recompute']=len(a['entries'])==6 and all(decisions)
    checks['all_entries_explicitly_use_fingered_task']=all(read(OUT/f"arena_{r['trial']}_{r['label']}.json")['task']=='dribble_v3' for r in a['entries'])
    checks['direct_family_comparisons_recompute']=len(a['comparisons'])==3 and all({k:v for k,v in d.items() if k not in ['trial','comparison']}==arena.compare(read(OUT/f"arena_{d['trial']}_pure.json")['trial'],read(OUT/f"arena_{d['trial']}_pure.json")['scores'],read(OUT/f"arena_{d['trial']}_tcn.json")['scores']) for d in a['comparisons'])
    checks['main_incumbents_replay_exactly']=all(read(OUT/'main_replay.json')[t]['scores']==main[t]['scores'] for t in TRIALS)
    checks['local_incumbents_replay_exactly']=all(read(OUT/'local_replay.json')[t]['scores']==before[t]['scores'] for t in TRIALS)
    checks['main_frontier_files_pinned']=all(sha(p)==h for p,h in read(OUT/'main_frontier_manifest.json').items())
    checks['promotions_beat_both_incumbents']=all(p['local']['wins'] and p['main_frontier']['wins'] for p in promotions)
    bylabel={r['label']:r for r in reg};checks['promoted_frozen_copies_match']=all(sha(ROOT/p['champion']['frozen_controller'])==bylabel[p['label']]['controller_sha256'] and sha(ROOT/p['champion']['frozen_params'])==bylabel[p['label']]['params_sha256'] for p in promotions)
    checks['gpt_names_and_notes']=all(Path(r['controller']).name.startswith('gpt-dribble-fingers-') for r in reg) and all(p['champion']['note'].startswith('gpt:') for p in promotions)
    if promotions:
        log=(OUT/'recheck_promoted.log').read_text();checks['promoted_replays_exact']=all(any(line.startswith(p['trial']+':') and line.endswith('  OK') for line in log.splitlines()) for p in promotions) and 'DRIFT' not in log
    videos=[]
    for p in promotions:
        path=Path(p['video']);reader=imageio.get_reader(path);meta=reader.get_meta_data();frames=0
        for frame in reader:assert frame.shape==(448,800,3);frames+=1
        reader.close();video_meta=read(path.with_suffix('.json'));assert video_meta['task']=='dribble_v3';m=video_meta['metrics']
        entry=read(OUT/f"promoted_{p['trial']}_{p['label']}.json");metric=entry['trial']['metric'];idx=entry['trial']['seeds'].index(p['seed'])
        assert m[metric]==entry['rows'][idx][metric]
        assert frames/meta['fps']>=m['time']-.04
        videos.append({'file':str(path),'frames':frames,'fps':meta['fps'],'seconds':frames/meta['fps'],'seed':p['seed'],'x_ok':m['x_ok'],'controlled_s':m['controlled_s'],'lost':m.get('lost'),'fell':m.get('fell')})
    write('video_audit.json',videos);checks['new_champion_videos_fully_decoded_and_replay_metric']=len(videos)==len(promotions)
    geometry=read(ROOT/'out/competitor_dribble_fingers_prototype/geometry_diagnosis.json');checks['consumed_geometry_sources_pinned']=len(geometry['rows'])==6 and all(sha(r['source'])==r['source_sha256'] for r in geometry['rows']) and all(sha(ROOT/p)==h for p,h in geometry['sources_sha256'].items())
    saturation=read(ROOT/'out/competitor_dribble_fingers_prototype/feature_saturation_controlled_window.json');detail['in_control_feature_saturation']=saturation
    checks['in_control_saturation_sources_pinned']=len(saturation['traces'])==6 and saturation['analysis_script_sha256']==sha(ROOT/'playground/gpt_finger_sensor_saturation.py') and saturation['rollout_metrics_sha256']==sha(ROOT/'out/competitor_dribble_fingers_prototype/rollouts.json') and all(sha(ROOT/'out/competitor_dribble_fingers_prototype'/r['trace'])==r['source_sha256'] for r in saturation['traces'])
    curve=read(OUT/'training_curves.json');curve_qa=read(OUT/'training_figure_verification.json')
    checks['completed_training_curve_sources_pinned']=all(sha(ROOT/p)==h for p,h in curve['sources_sha256'].items()) and sha(curve['image'])==curve['image_sha256']
    checks['training_figure_visually_checked']=curve_qa['passed'] and curve_qa['sha256']==curve['image_sha256']
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
    for left,right in [('tcn','pure'),('tcn','common_zero'),('pure','common_zero'),('pure','pure_bias'),('tcn','tcn_bias')]:
        for metric in ['x_ok','controlled_s']:
            scores=lambda label:[next(r['metrics'][metric] for r in validation if r['label']==label and r['seed']==s) for s in VALID]
            diagnostics.append({'comparison':left+' minus '+right,'metric':metric,**arena.compare({'higher':True},scores(right),scores(left))})
    long_summary={k:compact([r for r in endurance if r['label']==k]) for k in dict.fromkeys(r['label'] for r in endurance)}
    changes={v:{k:{'before':initial(v)[k],'after':training[v]['params'][k]} for k in NAMES} for v in training}
    changed_names={v:[k for k in NAMES if training[v]['params'][k]!=initial(v)[k]] for v in training}
    summary={'changed_parameter_names':changed_names,'endurance30':long_summary,'parameter_changes':changes,'arena':a,'validation':val,'training':{v:compact([{'metrics':m} for m in t['metrics']]) for v,t in training.items()},'residual':residual,'promotions':promotions,'failures':failures,'validation_comparisons':diagnostics,'recovery_disclosure':recovery_text,'audit_passed':True};write('summary.json',summary)
    lines = [
        '## Round 11: fingered crossover control',
        '',
        'Both contenders start from the same unchanged DribbleV3 baseline, with explicit contraction/keyframe strokes, quiet-trunk choreography and zero residual output. The pure controller searches active-hand phase offsets; the temporal controller learns a zero-initialized readout over fixed causal convolution features of muscle contractions, derivatives and sensors. Four bounded corrections target elbow, wrist, finger MCP and finger PIP, not raw activations. Each also tunes the same twelve catch/outgoing/finger-pose parameters. The finger poses affect launch and later strokes; all undeclared settings remain fixed.',
        '',
        'Each family completed **4,096 recorded full fifteen-second rollouts on 32 shared training starts**, (1+1)-ES seed280935, sigma .02, mean/minimum aggregation. Training rewards crossovers and control duration and penalizes body contacts, missed catches, drift, variable apex, falls, excess trunk activation and complete-rollout force/loading. Selections freeze before **64 untouched starts**, seven validation groups, then eight thirty-second continuations for each selected controller and common zero-head baseline.',
        recovery_text,
        '',
        'Both entries use the arena’s explicit **dribble_v3 task override**. The fingered body differs from earlier paddle-hand contenders. Incumbents replay their own recorded task; cross-body arena gains cannot isolate architecture. The direct pure/temporal comparison uses the same body, starts and initial motion. Existing trial definitions and physics are unchanged.',
        '',
        '### Arena verdicts',
        '',
        '| Trial | Family | Mean | Local paired gain | Local p | Local win | Main paired gain | Main p | Main win |',
        '|---|---|---:|---:|---:|---|---:|---:|---|',
    ]
    for e in a['entries']:
        l=e['local'];m=e['main_frontier'];lines.append(f"| {e['trial']} | {e['label']} | {e['mean_valid']:.4f} | {l['mean_diff']:+.6f} | {l['p']} | {l['wins']} | {m['mean_diff']:+.6f} | {m['p']} | {m['wins']} |")
    lines += ['','Promotion requires wins against both replayed frontiers. All six entries precede any promotion. Arms-only is a conditional penalty: lower is better, and fewer than ten dribbles gives1.0. Raw trunk share is separate. p=0 denotes0/4000 sampled sign flips; comparisons are exploratory and unadjusted.','',f"[Training curves]({OUT/'training_curves.png'}) describe training only; they do not establish fresh-validation or arena gains.",'','### Fresh validation','','| Controller | Crossovers | Control s | Dribbles | Runs ≥10 | Raw trunk share | Conditional penalty | Lost |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for k,v in val.items():lines.append(f"| {k} | {v['x_ok']:.4f} | {v['controlled_s']:.4f} | {v['dribbles']:.4f} | {v['at_least_ten_dribbles']}/{v['n']} | {v['trunk_share_upper']:.5f} | {v['trunk_share_if_dribbling']:.5f} | {v['lost']}/{v['n']} |")
    lines += ['','Bias/zero ablations retain the selected backbone parameters. The common zero-head group retains the starting backbone. Neither ablation is separately retrained.','', '**Contact and impact.** '+ '; '.join(k+f": mean body contacts {val[k]['body_hits']:.3f}, mean peak ground force {val[k]['peak_grf_bw']:.3f} BW, mean peak loading {val[k]['peak_loading_bw_s']:.3f} BW/s" for k in ['pure','tcn','common_zero'])+'. These impact measurements cover the full visible motion. Trunk and excursion shares use the task’s in-control measurement window.','','### Thirty-second continuations','','| Controller | Starts | Crossovers | Control s | Lost |','|---|---:|---:|---:|---:|']
    for k,v in long_summary.items():lines.append(f"| {k} | {v['n']} | {v['x_ok']:.4f} | {v['controlled_s']:.4f} | {v['lost']}/{v['n']} |")
    lines += ['','Movement after ball loss does not count as control. These checks never change the selections.','','### Learned corrections and measured motion','']
    for k,v in residual.items():lines.append(f"{k}: elbow / wrist / MCP / PIP sampled peak offsets {' / '.join(f'{x:.2f}' for x in v['sampled_peak_degrees'])} degrees; RMS {' / '.join(f'{x:.2f}' for x in v['rms_degrees'])} degrees. Mean measured arm-excursion shares: {v['mean_arm_excursion_share']}.")
    lines += ['','Bounds are .18/.15/.20/.20 radians before geometry and spring filtering. Ten-Hz sampled peaks are not continuous maxima. Exact zero-head parity and nonzero measured finger effects passed on the prototype; final selected-vs-zero measured effects are recorded in the audit.','','| Parameter | Pure initial | Pure selected | Temporal initial | Temporal selected |','|---|---:|---:|---:|---:|']
    for k in NAMES:lines.append(f"| {k} | {changes['pure'][k]['before']:.6f} | {changes['pure'][k]['after']:.6f} | {changes['tcn'][k]['before']:.6f} | {changes['tcn'][k]['after']:.6f} |")
    lines += ['', f"**Temporal feature clipping.** On six consumed traces, the estimated 50 Hz in-control window has no clipping of ball-position or horizontal-velocity inputs. Vertical-velocity clipping is 2.5–7.6%; estimated contraction jerk clipping is 3.2–4.8%. Ball-position clipping rises mainly during post-loss wandering across the full motion. These finite-difference estimates do not establish a cause of loss or justify changing the frozen inputs. [Source-pinned in-control trace analysis]({ROOT / 'out/competitor_dribble_fingers_prototype/feature_saturation_controlled_window.json'}).", '', '### Failures and videos', '']
    for k in ['pure','tcn','common_zero']:lines.append(f"- {k}: {failures[k]['lost_reasons']}; fallen starts {failures[k]['fell_seeds']}.")
    if not promotions:lines.append('No qualifying promotion; earlier champions remain in place.')
    for p,v in zip(promotions,videos):lines.append(f"- {p['trial']}, {p['label']}, seed{p['seed']}: [full fifteen-second video]({p['video']}) and [contact sheet]({p['sheet']}). Crossovers{v['x_ok']}; control{v['controlled_s']}s; loss{v['lost']}; fell{v['fell']}.")
    lines += ['','### Temporal residual versus pure search','','| Trial | Temporal minus pure, oriented | p | Temporal wins |','|---|---:|---:|---|']
    for d in a['comparisons']:lines.append(f"| {d['trial']} | {d['mean_diff']:+.6f} | {d['p']} | {d['wins']} |")
    lines += ['',f"Fresh temporal averages{val['tcn']['x_ok']:.4f} crossovers and{val['tcn']['controlled_s']:.4f}scontrol; pure{val['pure']['x_ok']:.4f} and{val['pure']['controlled_s']:.4f}s; common baseline{val['common_zero']['x_ok']:.4f} and{val['common_zero']['controlled_s']:.4f}s. These are finite, matched-budget policy outcomes; they do not establish indefinite control, general neural superiority, or full human technique.",'',f"All {len(checks)} audit checks pass. [Summary]({OUT/'summary.json'}), [audit]({OUT/'audit.json'}), [frozen candidates]({OUT/'candidates.json'}), [protocol]({OUT/'protocol.json'}). No existing trial, shared source or physics changed; no commits.",'']
    (OUT/'REPORT.md').write_text('\n'.join(lines));print(json.dumps({'passed':True,'checks':len(checks),'promotions':[(p['trial'],p['label']) for p in promotions]},indent=2))
if __name__=='__main__':main()
