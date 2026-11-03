"""Audit the complete landing-depth experiment and generate its report appendix."""
import json,math,statistics,subprocess
from pathlib import Path
import imageio.v2 as imageio
import numpy as np
import arena
from gpt_jump_support_validate import ROOT,OUT,VALID,read,write,sha,check_frozen,compact
from gpt_jump_recover import legal

def pstr(p):return '0 / 4,000 sampled flips' if p==0 else f'{p:.5f}'
def main():
    registry=check_frozen();checks={};details={};round_=OUT.parent
    baseline=read(ROOT/'out/competitor_20260927/baseline_files.json');allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    changes=[p for p,h in baseline.items() if p not in allowed and sha(ROOT/p)!=h]
    checks['inherited_files_unchanged']=not changes;details['unexpected_changes']=changes
    checks['trial_definitions_unchanged']=(ROOT/'playground/arena/trials.json').read_bytes()==(round_/'trials_before.json').read_bytes()
    manifests=['competitor_20260927/frozen_manifest.json','competitor_20260927/final_manifest.json','competitor_jump_round2/manifest.json','competitor_jump_round3/manifest.json','competitor_jump_round4/manifest.json','competitor_jump_round4/judge_manifest.json','competitor_jump_round5/manifest.json','competitor_jump_round5/support/manifest.json','competitor_jump_round5/support/judge_manifest.json']
    drift=[p for f in manifests for p,h in read(ROOT/'out'/f).items() if sha(ROOT/p)!=h]
    checks['all_frozen_sources_and_binaries_match']=not drift;details['hash_drift']=drift
    checks['both_pilots_complete_equal_budgets']=all(len(read(folder/f'{v}_pilot.json'))==count and all(len(r['rows'])==8 and {x['seed'] for x in r['rows']}==set(range(279101,279109)) for r in read(folder/f'{v}_pilot.json')) for folder,count in [(round_,37),(OUT,46)] for v in ['pure','tcn'])
    checks['both_private_builds_exact_off_parity']=all(read(folder/'parity.json')['passed'] and len(read(folder/'parity.json')['checks'])==4 and all(all(r['exact'].values()) for r in read(folder/'parity.json')['checks']) for folder in [round_,OUT])
    mechanism=read(OUT/'mechanism_check.json');checks['gate_is_selective_and_changes_measured_motion']=0<mechanism['captures_on_training_starts']<mechanism['training_starts'] and all(x>1e-8 for x in mechanism['max_trace_changes'].values())
    from search import read_params
    checks['selected_params_match_pilot']=all(read_params(r['params_file'])==read(OUT/f"{r['variant']}_pilot.json")[r['pilot_index']]['params'] for r in registry)
    checks['launch_and_neural_parameters_frozen']=all(all(r['params'].get(k)==value for k,value in read_params(round_/f"reference/previous-{r['variant']}.txt").items()) for r in registry)
    validation=read(OUT/'validation.json');long=read(OUT/'endurance20.json');a=read(OUT/'arena_summary.json');promotions=read(OUT/'promotions.json')
    labels={'pure_previous','tcn_previous','p6_reference'}
    for r in registry:
        labels.update([r['label'],r['label']+'_static'])
        if r['variant']=='tcn':labels.update([r['label']+'_bias',r['label']+'_zero'])
    checks['all_fresh_groups_complete']=len(validation)==64*len(labels) and {r['label'] for r in validation}==labels and all(len([r for r in validation if r['label']==label])==64 and {r['seed'] for r in validation if r['label']==label}==set(VALID) for label in labels)
    checks['endurance_complete']=len(long)==8*len(registry) and all({x['seed'] for x in long if x['label']==r['label']}==set(VALID[:8]) for r in registry)
    old_seeds=set()
    for folder in ['competitor_20260927','competitor_jump_round2','competitor_jump_round3','competitor_jump_round4']:
        protocol=read(ROOT/'out'/folder/'protocol.json')
        for key in ['training_seeds','validation_seeds','training','validation']:old_seeds.update(protocol.get(key,[]))
    arena_seeds=set(seed for t in read(ROOT/'playground/arena/trials.json').values() for seed in t['seeds'])
    checks['private_seeds_separated']=not (set(VALID)|set(range(279001,279003))|set(range(279101,279109)))&(old_seeds|arena_seeds) and not set(VALID)&set(range(279101,279109))
    pilot_metrics=[x['metrics'] for folder in [round_,OUT] for v in ['pure','tcn'] for r in read(folder/f'{v}_pilot.json') for x in r['rows']]
    metrics=pilot_metrics+[r['metrics'] for r in validation+long]
    checks['no_simulation_errors']=not any('error' in m for m in metrics)
    checks['full_rollout_metrics_finite']=all(all(isinstance(m.get(k),(int,float)) and math.isfinite(m[k]) for k in ['time','mark','peak_grf_bw','peak_loading_bw_s','takeoff_vx','takeoff_vz']) for m in metrics)
    checks['residual_bounds_hold']=all(len(m['residual_peak_rad'])==4 and all(math.isfinite(x) and 0<=x<=bound+1e-9 for x,bound in zip(m['residual_peak_rad'],[.6,.6,.4,.6])) for m in metrics)
    candidate_map={r['label']:r for r in registry}
    checks['support_events_match_declared_limits']=all(all(len(e)==5 and all(math.isfinite(x) for x in e) and e[1]>=candidate_map[r['label']]['params']['gpt_support_time']-1e-8 and e[2]<candidate_map[r['label']]['params']['gpt_support_height'] and abs(e[4]-candidate_map[r['label']]['params']['gpt_support_gain'])<1e-8 and .4<=e[4]<=1.4 for e in r['metrics']['capture_events']) for r in validation+long if r['label'] in candidate_map)
    effects={}
    for r in registry:
        if r['variant']=='tcn':
            full=np.load(OUT/f"validation_{r['label']}.npz");zero=np.load(OUT/f"validation_{r['label']}_zero.npz")
            effects[r['label']]={k:float(np.max(np.abs(full[k]-zero[k]))) for k in ['command','measured','activation','q']}
    checks['temporal_heads_reach_measured_motion']=all(all(x>1e-8 for x in e.values()) for e in effects.values());details['head_effects']=effects
    before=read(round_/'champions_before.json');main_before=read(round_/'main_champions_before.json');decisions=[]
    for r in a['entries']:
        entry=read(OUT/f"arena_{r['trial']}_{r['label']}.json")
        decisions.append(arena.compare(entry['trial'],before[r['trial']]['scores'],entry['scores'])==r['local'])
        if r['trial'] in main_before:decisions.append(arena.compare(entry['trial'],main_before[r['trial']]['scores'],entry['scores'])==r['main_frontier'])
    checks['all_arena_comparisons_recompute']=len(a['entries'])==3*len(registry) and all(decisions)
    checks['p6_replays_exactly']=read(OUT/'p6_arena_replay.json')['scores']==main_before['search_jump_robust_legal']['scores']
    checks['promotions_beat_both_required_incumbents']=all(r['local']['wins'] and (r['main_frontier'] is None or r['main_frontier']['wins']) for r in promotions)
    checks['promoted_copies_match']=all(sha(ROOT/r['champion']['frozen_controller'])==sha(candidate_map[r['label']]['controller']) and sha(ROOT/r['champion']['frozen_params'])==candidate_map[r['label']]['params_sha256'] for r in promotions)
    checks['gpt_names_and_notes']=all(Path(r['champion']['controller']).name.startswith('gpt-jump-support-') and r['champion']['note'].startswith('gpt:') for r in promotions)
    if promotions:
        replay=(OUT/'recheck_promoted.log').read_text();checks['promoted_champions_replay']=all(any(line.startswith(r['trial']+':') and line.endswith('  OK') for line in replay.splitlines()) for r in promotions) and 'DRIFT' not in replay
    videos=[]
    for r in promotions:
        p=Path(r['video']);reader=imageio.get_reader(p);meta=reader.get_meta_data();frames=0
        for frame in reader:assert frame.shape==(448,800,3);frames+=1
        reader.close();m=read(p.with_suffix('.json'))['metrics'];assert frames/meta['fps']>=m['time']-.04
        videos.append({'file':str(p),'frames':frames,'fps':meta['fps'],'seconds':frames/meta['fps'],'simulation_seconds':m['time'],'seed':r['seed'],'legal_at_end':legal(m)})
    write('video_audit.json',videos);checks['all_new_videos_decoded']=len(videos)==len(promotions)
    checks['no_commits']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()=='85e95c33680a0e04bb4245de3fe86e2ae3c3200a'
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    audit={'passed':all(checks.values()),'checks':checks,'details':details};write('audit.json',audit);assert audit['passed'],checks
    val={label:compact([r for r in validation if r['label']==label]) for label in dict.fromkeys(r['label'] for r in validation)}
    endurance={r['label']:compact([x for x in long if x['label']==r['label']],20) for r in registry};residual={}
    for r in registry:
        if r['variant']=='tcn':
            ms=[x['metrics'] for x in validation if x['label']==r['label']]
            residual[r['label']]={'sampled_peak_degrees':np.degrees(np.max([m['residual_peak_rad'] for m in ms],axis=0)).tolist(),'rms_degrees':np.degrees(np.sqrt(np.mean(np.array([m['residual_rms_rad'] for m in ms])**2,axis=0))).tolist()}
    selected=[{k:r[k] for k in ['label','variant','choice','pilot_index','params_file','training']}|{'gate':{k:v for k,v in r['params'].items() if k.startswith('gpt_support')}} for r in registry]
    evidence={'arena':a,'validation':val,'endurance20':endurance,'residual':residual,'selected':selected,'promotions':promotions,'audit_passed':True};write('summary.json',evidence)
    lines=['## Round 5: conditional landing support','', 'Round 4 improved longer recovery but did not beat the newer P6 robustness champion. This round returns to the longer-distance round-2 policies and changes recovery only when the measured landing warrants it. Launch parameters, explicit contraction keyframes, and inherited residual weights remain frozen.','', '**Pure search.** Retain the phase-based offset policy. Record the lowest pelvis height during the landing chunk; when it crosses the selected threshold, enter the existing balanced-crouch recovery at the selected time and apply the selected bounded reflex gain. Otherwise, keep the original timing and gain.','', '**Temporal residual.** Apply the same conditional recovery mechanism to the earlier temporal controller. Its convolution features and twenty learned readout weights stay unchanged; sensor-dependent residuals and the explicit gate affect subsequent motion. This round trains gate parameters, not new neural weights.','', 'The first pilot used predicted torso-angle thresholds that proved too low for the observed body-frame angles: the enabled gate triggered on every start. That negative calibration result is preserved, without arena entry. The second pilot uses the lowest measured landing pelvis height and adjusts both recovery timing and support gain. Both private builds reproduce their previous controller exactly when disabled, across four eight-second parity pairs each.','', 'Each family receives **296 first-pilot rollouts + 368 landing-depth rollouts = 664**, on the same eight private starts 279101–279108, plus eight parity rollouts per family across the two builds. Selection rules were frozen before the second grid: best recovery score, and a distance alternative legal at three seconds on all eight training starts with at least six eight-second successes. Every distinct selected candidate then faces **64 untouched starts 281101–281164**, its static timing/gain counterpart, and temporal bias/zero-head ablations. P6 is a separately trained incumbent, not an equal-compute architecture comparison.','', '| Candidate | Trigger height, m | Recovery delay, s | Reflex gain | Pilot legal 3 s / 8 s |','|---|---:|---:|---:|---|']
    for r in selected:
        g=r['gate'];s=r['training'];lines.append(f"| {r['label']} | {g.get('gpt_support_height','—')} | {g.get('gpt_support_time','—')} | {g.get('gpt_support_gain','—')} | {s['legal3']}/8 / {s['legal8']}/8 |")
    lines+=['','### Arena outcomes','', 'All entries precede promotion. Promotion requires a win against both the local and recorded main incumbents wherever both exist. Large guard-scored differences are not metres; a sampled p of zero means zero as-favorable results in 4,000 sampled sign flips. These are unadjusted exploratory comparisons.','', '| Trial | Candidate | Valid | Mean valid mark, m | Local diff | Local p | Local verdict | Main diff | Main p | Main verdict |','|---|---|---:|---:|---:|---:|---|---:|---:|---|']
    for r in a['entries']:
        l=r['local'];m=r['main_frontier'];mark='—' if r['mean_valid'] is None else f"{r['mean_valid']:.5f}";front='— | — | —' if m is None else f"{m['mean_diff']:+.9g} | {pstr(m['p'])} | {'WIN' if m['wins'] else 'LOSE'}"
        lines.append(f"| {r['trial']} | {r['label']} | {r['passes']}/{r['n']} | {mark} | {l['mean_diff']:+.9g} | {pstr(l['p'])} | {'WIN' if l['wins'] else 'LOSE'} | {front} |")
    lines+=['','### Fresh validation, static-gate comparison, and head ablations','','| Controller | Legal 3 s | Mean legal mark, m | Legal 8 s | Gate triggered | Mean peak force, BW |','|---|---:|---:|---:|---:|---:|']
    for label,r in val.items():
        mark='—' if r['mean3'] is None else f"{r['mean3']:.5f}";lines.append(f"| {label} | {r['legal3']}/{r['n']} | {mark} | {r['legal_final']}/{r['n']} | {r['capture_count']}/{r['n']} | {r['peak_bw']:.2f} |")
    lines+=['','A static counterpart applies the selected recovery time and gain to every landing; it disables the conditional gate. Bias/zero-head rows retain the candidate gate and tuned backbone, so they test the contribution of the inherited temporal head within the complete policy. Conditional distance means exclude invalid starts; the arena includes all guard failures.','', '### Longer motion and learned correction magnitude','']
    for label,r in endurance.items():lines.append(f"- {label}: **{r['legal_final']}/{r['n']}** legal at twenty seconds.")
    for label,r in residual.items():lines.append(f"- {label}, hip/knee/spine/shoulder: sampled peak **{' / '.join(f'{x:.2f}' for x in r['sampled_peak_degrees'])}°**; RMS **{' / '.join(f'{x:.2f}' for x in r['rms_degrees'])}°**. These 10 Hz requests precede geometry and spring filtering; sampled peaks are not continuous maxima.")
    lines+=['','### Direct comparisons','','| Trial | Comparison | Oriented paired diff | p | First policy wins |','|---|---|---:|---:|---|']
    for r in a['comparisons']:lines.append(f"| {r['trial']} | {r['comparison']} | {r['mean_diff']:+.9g} | {pstr(r['p'])} | {r['wins']} |")
    lines+=['','### New champion videos and audit','']
    for r,v in zip(promotions,videos):lines.append(f"- {r['trial']}, **{r['label']}**, seed {r['seed']}: [twenty-second video]({r['video']}) and [contact sheet]({r['sheet']}); legal at video end: **{v['legal_at_end']}**.")
    if not promotions:lines.append('No round-5 candidate qualified for promotion; earlier champions remain in place.')
    lines+=['',f"All **{len(checks)} audit checks** pass: [audit]({OUT/'audit.json'}), [complete summary]({OUT/'summary.json'}), [frozen selections]({OUT/'candidates.json'}). Shared SDK, simulator, and existing trial definitions are unchanged; no commits or main-checkout edits were made. Final interpretation must distinguish any actual P6 win from a weaker local-incumbent win, and must retain the fresh-start and twenty-second failures above.",'']
    (OUT/'REPORT.md').write_text('\n'.join(lines));print(json.dumps({'audit_passed':True,'checks':len(checks),'promotions':[r['trial']+':'+r['label'] for r in promotions],'validation':{r['label']:val[r['label']] for r in registry},'endurance':endurance},indent=2))
if __name__=='__main__':main()
