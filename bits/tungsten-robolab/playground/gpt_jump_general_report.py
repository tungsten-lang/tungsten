"""Audit and report round 4 from finished artifacts, preserving prior reports."""
import hashlib,json,math,statistics,subprocess
from pathlib import Path
import imageio.v2 as imageio
import numpy as np
import arena
from gpt_jump_generalize import ROOT,OUT,PARAMS,TRAIN,VALID,BUDGET,BACKBONE,initial,legal,stats,read_params
from gpt_jump_report import summary

def read(p):return json.loads(p.read_text())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pstr(p):return '0 / 4,000 sampled flips' if p==0 else f'{p:.5f}'
def main():
    checks={};details={};before=read(OUT/'champions_before.json');main_before=read(OUT/'main_champions_before.json');a=read(OUT/'arena_summary.json');promotions=read(OUT/'promotions.json')
    checks['trial_definitions_unchanged']=(ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    baseline=read(ROOT/'out/competitor_20260927/baseline_files.json');allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    changed=[p for p,h in baseline.items() if p not in allowed and digest(ROOT/p)!=h];checks['inherited_simulator_and_sdk_unchanged']=not changed;details['unexpected_changes']=changed
    manifests=['competitor_20260927/frozen_manifest.json','competitor_20260927/final_manifest.json','competitor_jump_round2/manifest.json','competitor_jump_round3/manifest.json','competitor_jump_round4/manifest.json','competitor_jump_round4/judge_manifest.json']
    drift=[p for m in manifests for p,h in read(ROOT/'out'/m).items() if digest(ROOT/p)!=h];checks['frozen_source_and_binary_hashes_match']=not drift;details['hash_drift']=drift
    checks['budget_and_archive_counts']=all(read(OUT/f'{v}.json')['used']==BUDGET and np.load(OUT/f'{v}.npz')['X'].shape==(192,16) and np.isfinite(np.load(OUT/f'{v}.npz')['F']).all() and (np.load(OUT/f'{v}.npz')['F']>-1e6).all() for v in ['pure','tcn'])
    checks['parameter_files_match_recorded_best']=all(read_params(PARAMS/f'{v}.txt')==read(OUT/f'{v}.json')['params'] for v in ['pure','tcn'])
    checks['only_declared_parameters_changed']=all(value==read(OUT/f'{v}.json')['params'].get(name) for v in ['pure','tcn'] for name,value in initial(v).items() if name not in BACKBONE)
    checks['archive_best_and_dimensions_match']=all(float(np.load(OUT/f'{v}.npz')['F'].max())==read(OUT/f'{v}.json')['best'] and set(np.load(OUT/f'{v}.npz')['names'].tolist())==set(BACKBONE) for v in ['pure','tcn'])
    details['final_parameter_sha256']={v:digest(PARAMS/f'{v}.txt') for v in ['pure','tcn']}
    checks['heads_remain_frozen']=all(read(OUT/f'{v}.json')['params'].get(f'gpt_w{i}',0)==initial(v).get(f'gpt_w{i}',0) for v in ['pure','tcn'] for i in range(20))
    seedsets=[]
    for folder in ['competitor_20260927','competitor_jump_round2','competitor_jump_round3','competitor_jump_round4']:
        p=read(ROOT/'out'/folder/'protocol.json')
        for key in (['training_seeds','validation_seeds'] if folder=='competitor_20260927' else ['training','validation']):seedsets.append(set(p[key]))
    checks['all_training_validation_seed_sets_disjoint']=all(not aa&bb for i,aa in enumerate(seedsets) for bb in seedsets[i+1:])
    trial_seeds=set(s for t in read(ROOT/'playground/arena/trials.json').values() for s in t['seeds']);checks['new_private_seeds_disjoint_from_arena']=not (set(TRAIN)|set(VALID))&trial_seeds
    validation={};errors=[]
    for v in ['pure','tcn']:
        rows=read(OUT/f'{v}_validate.json');kinds=['previous','candidate','bias_only','zero_head'] if v=='tcn' else ['previous','candidate']
        checks[v+'_fresh_validation_complete']=all({r['seed'] for r in rows if r['kind']==k}==set(VALID) for k in kinds) and len(rows)==len(kinds)*len(VALID)
        errors += [r for r in rows if 'error' in r['metrics']]
        for k in kinds:validation[v+'_'+k]=summary([r['metrics'] for r in rows if r['kind']==k])
    ref=read(OUT/'p6_validate.json');validation['p6']=summary([r['metrics'] for r in ref]);checks['p6_fresh_complete']={r['seed'] for r in ref}==set(VALID)
    errors += [r for r in ref if 'error' in r['metrics']]
    all_validation=[r['metrics'] for v in ['pure','tcn'] for r in read(OUT/f'{v}_validate.json')]+[r['metrics'] for r in ref]
    checks['critical_validation_telemetry_finite']=all(isinstance(m.get(k),(int,float)) and math.isfinite(m[k]) for m in all_validation for k in ['time','mark','peak_grf_bw','peak_loading_bw_s','takeoff_vx','takeoff_vz']) and all(isinstance(m['three_second'].get('mark'),(int,float)) and math.isfinite(m['three_second']['mark']) for m in all_validation)
    checks['observed_residual_outputs_within_bounds']=all(len(m['residual_peak_rad'])==4 and all(isinstance(x,(int,float)) and math.isfinite(x) and 0<=x<=bound+1e-9 for x,bound in zip(m['residual_peak_rad'],[.6,.6,.4,.6])) for m in all_validation)
    checks['p6_exact_arena_replay']=read(OUT/'p6_arena_replay.json')['scores']==main_before['search_jump_robust_legal']['scores']
    reference=read(OUT/'reference/manifest.json');checks['p6_reference_hashes_match']=all(digest(OUT/p)==h for p,h in reference['files'].items())
    recomputed=[]
    for r in a['entries']:
        entry=read(OUT/f"arena_{r['variant']}_{r['trial']}.json");t=r['trial'];errors += [m for m in entry['rows'] if 'error' in m]
        recomputed.append(arena.compare(entry['trial'],before[t]['scores'],entry['scores'])==r['local'])
        if t in main_before:recomputed.append(arena.compare(entry['trial'],main_before[t]['scores'],entry['scores'])==r['main_frontier'])
    checks['all_arena_decisions_recompute']=len(a['entries'])==6 and all(recomputed)
    long=read(OUT/'endurance20.json');errors += [r for r in long if 'error' in r['metrics']];checks['endurance_complete']=len(long)==16 and all({r['seed'] for r in long if r['variant']==v}==set(VALID[:8]) for v in ['pure','tcn'])
    endurance={v:sum(legal(r['metrics']) for r in long if r['variant']==v) for v in ['pure','tcn']}
    checks['no_recorded_simulation_errors']=not errors;details['errors']=errors
    full=np.load(OUT/'tcn_candidate_validation.npz');zero=np.load(OUT/'tcn_zero_head_validation.npz');effects={k:float(np.max(np.abs(full[k]-zero[k]))) for k in ['command','measured','activation','q']}
    checks['temporal_head_changes_actual_motion']=all(v>1e-8 for v in effects.values());details['nonzero_trace_effects']=effects
    checks['promoted_copies_match_candidates']=all(digest(ROOT/r['champion']['frozen_controller'])==digest(Path(r['champion']['controller'])) and digest(ROOT/r['champion']['frozen_params'])==digest(Path(r['champion']['params'])) for r in promotions)
    checks['gpt_notes_and_names']=all(r['champion']['note'].startswith('gpt:') and Path(r['champion']['controller']).name.startswith('gpt-jump-general-') for r in promotions)
    if promotions:
        log=(OUT/'recheck_promoted.log').read_text();checks['promoted_champions_replay']=all(any(line.startswith(r['trial']+':') and line.endswith('  OK') for line in log.splitlines()) for r in promotions) and 'DRIFT' not in log
    video=[]
    for r in promotions:
        p=Path(r['video']);reader=imageio.get_reader(p);meta=reader.get_meta_data();n=0
        for frame in reader:assert frame.shape==(448,800,3);n+=1
        reader.close();m=read(p.with_suffix('.json'))['metrics'];assert n/meta['fps']>=m['time']-.04
        video.append({'file':str(p),'frames':n,'fps':meta['fps'],'seconds':n/meta['fps'],'simulation_seconds':m['time'],'legal_at_end':legal(m),'seed':r['seed']})
    (OUT/'video_audit.json').write_text(json.dumps(video,indent=2)+'\n');checks['all_promoted_videos_decoded']=len(video)==len(promotions)
    checks['no_commits']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()=='85e95c33680a0e04bb4245de3fe86e2ae3c3200a'
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    audit={'passed':all(checks.values()),'checks':checks,'details':details};(OUT/'audit.json').write_text(json.dumps(audit,indent=2)+'\n');assert audit['passed'],checks
    ms=[r['metrics'] for r in read(OUT/'tcn_validate.json') if r['kind']=='candidate'];peak=np.degrees(np.max([m['residual_peak_rad'] for m in ms],axis=0));rms=np.degrees(np.sqrt(np.mean(np.array([m['residual_rms_rad'] for m in ms])**2,axis=0)))
    evidence={'arena':a,'validation':validation,'endurance20_passes_out_of8':endurance,'residual_peak_degrees':peak.tolist(),'residual_rms_degrees':rms.tolist(),'promotions':promotions,'audit_passed':audit['passed']};(OUT/'summary.json').write_text(json.dumps(evidence,indent=2)+'\n')
    lines=['## Round 4: challenging the current robustness frontier','', 'The main arena advanced after the original campaign. Its P6 temporal-convolution keyframe policy reached 1.31534375 m on all 32 perturbed starts. This continuation pins that frozen champion and requires its exact per-seed replay before any comparison. The main agent’s separately recorded cross-evaluations are preserved in `out/competitor_jump_round4/MAIN_CROSS_EVALUATION.md`.','', '**General-recovery pure search.** Start from the round-3 phase-indexed controller, keep its residual weights and contraction keyframe vectors fixed, and tune sixteen explicit launch, balanced-crouch, timing, and landing-feedback parameters. The score heavily penalizes losing legality at either three or eight seconds, then rewards distance and penalizes impact/loading.','', '**General-recovery temporal.** Start from the round-3 learned temporal controller and search the same sixteen explicit parameters under the identical new budget. The inherited twenty readout weights are frozen in this continuation; it is a refinement of a previously learned policy, not new neural training or a common-initialization comparison. Convolution filters remain fixed.','', 'Each family receives **3,072 rollouts**, 16 new training starts 277101–277116, optimizer seed 280928, normalized sigma 0.012, and risk-0.5 (1+1)-ES. Fresh validation uses 64 new starts 278101–278164. The cumulative accepted jump-search budget is now 7,200 rollouts per family, plus the separately disclosed shared probes and validation. P6 has its own training history, so the incumbent comparison is not an equal-compute architecture experiment.','', '### Arena outcomes against both boards','', 'All six entries precede any round-4 promotion. Promotion requires beating both the worktree incumbent and the recorded main incumbent, where one exists. The six-second trial belongs only to this worktree. Large paired differences are guard-scored values, not metres.','', '| Trial | Family | Valid | Mean valid mark, m | Local paired diff | Local p | Local verdict | Main paired diff | Main p | Main verdict |','|---|---|---:|---:|---:|---:|---|---:|---:|---|']
    for r in a['entries']:
        l=r['local'];m=r['main_frontier'];mean='—' if r['mean_valid'] is None else f"{r['mean_valid']:.4f}";front='— | — | —' if m is None else f"{m['mean_diff']:+.9g} | {pstr(m['p'])} | {'WIN' if m['wins'] else 'LOSE'}"
        lines.append(f"| {r['trial']} | {r['variant']} | {r['passes']}/{r['n']} | {mean} | {l['mean_diff']:+.9g} | {pstr(l['p'])} | {'WIN' if l['wins'] else 'LOSE'} | {front} |")
    lines+=['','### Fresh validation and residual attribution','','| Controller | Legal at 3 s | Mean legal mark, m | Legal at 8 s | Mean legal mark, m | Peak force, BW | Peak loading, BW/s |','|---|---:|---:|---:|---:|---:|---:|']
    for k in ['p6','pure_previous','pure_candidate','tcn_previous','tcn_candidate','tcn_bias_only','tcn_zero_head']:
        r=validation[k];fmt=lambda n:'—' if n is None else f'{n:.4f}'
        lines.append(f"| {k} | {r['legal3']}/{r['n']} | {fmt(r['mark3'])} | {r['legal8']}/{r['n']} | {fmt(r['mark8'])} | {r['peak_bw']:.2f} | {r['loading']:.0f} |")
    lines+=['',f"Twenty-second legality: pure **{endurance['pure']}/8**, temporal **{endurance['tcn']}/8**. These remain finite tests. The table reports conditional means on legal starts; failures remain in the arena's guard-coded decision.",'',f"Temporal hip / knee / spine / shoulder output magnitudes: sampled peak **{' / '.join(f'{v:.2f}' for v in peak)} degrees**; full-rollout RMS **{' / '.join(f'{v:.2f}' for v in rms)} degrees**. These 10 Hz samples precede geometry conversion, chunk masks, and springs. Output differences from round 3 reflect changed trajectories with the same frozen readout.",'','### Temporal versus pure on identical arena starts','','| Trial | TCN minus pure | p | TCN wins |','|---|---:|---:|---|']
    for r in a['tcn_vs_pure']:lines.append(f"| {r['trial']} | {r['mean_diff']:+.9g} | {pstr(r['p'])} | {r['wins']} |")
    lines+=['','### Promoted motion and checks','']
    if not promotions:lines+=['No round-4 challenger was promoted. Earlier champion videos and verdicts remain unchanged.','']
    for r,v in zip(promotions,video):lines.append(f"- **{r['trial']}**, {r['variant']}, seed {r['seed']}: [twenty-second video]({r['video']}) and [contact sheet]({r['sheet']}). Legal at the end of this video: **{v['legal_at_end']}**.")
    lines+=['',f"All {len(checks)} round-4 audit checks pass: [audit]({OUT/'audit.json'}), [complete summary]({OUT/'summary.json'}), [P6 exact replay]({OUT/'p6_arena_replay.json'}). No shared SDK or existing trial changes, no commits, and no edits to the main board. Any remaining fresh-start or twenty-second failures are reported above and prevent claims of universal recovery.",'']
    (OUT/'REPORT.md').write_text('\n'.join(lines));print(json.dumps({'audit':audit['passed'],'validation':validation,'endurance':endurance,'promoted':[r['trial'] for r in promotions]},indent=2))
if __name__=='__main__':main()
