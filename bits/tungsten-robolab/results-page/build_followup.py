"""Keep later main-arena evidence separate from the original campaign snapshot."""
import hashlib,json
import imageio.v2 as imageio
from pathlib import Path
from collections import Counter
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'out/competitor_jump_round4'
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def paired_validation_diagnostic(rows):
    groups={}
    for row in rows:groups.setdefault(row['label'],{})[int(row['seed'])]=row
    definitions=[('pure_bias','pure'),('pure_zero','pure'),('tcn_bias','tcn'),('tcn_zero','tcn')]
    metrics=['score','x_ok','controlled_s','catch_miss']
    comparisons=[]
    def value(row,name):
        if name=='score':return float(row['score'])
        m=row['metrics']
        if name=='catch_miss':return float(m.get('moves',{}).get('X',{}).get('catch_miss') or 0.0)
        return float(m[name])
    for condition,reference in definitions:
        seeds=sorted(groups[condition])
        if seeds!=sorted(groups[reference]) or len(seeds)!=64:
            raise ValueError('Round 11 ablation rows are not paired on all 64 fresh starts')
        indices=np.random.default_rng(1109).integers(0,len(seeds),size=(30000,len(seeds)))
        effects={}
        for name in metrics:
            delta=np.array([value(groups[condition][seed],name)-value(groups[reference][seed],name) for seed in seeds],dtype=float)
            boot=delta[indices].mean(axis=1)
            low,high=np.quantile(boot,[0.025,0.975])
            effects[name]={'mean_delta':round(float(delta.mean()),6),'ci95_low':round(float(low),6),'ci95_high':round(float(high),6)}
        comparisons.append({'condition':condition,'reference':reference,'metrics':effects})
    return {
        'method':'Paired percentile bootstrap over the same 64 fresh validation starts; 30,000 resamples per comparison.',
        'direction':'Positive deltas favor the masked condition for score, crossovers and control seconds; negative deltas favor it for the catch-miss metric.',
        'caveat':'These planned masks are applied to selected frozen readouts, not separately retrained. Intervals are unadjusted across four comparisons and do not replace arena scoring.',
        'comparisons':comparisons
    }
def build(asset):
    history=read(OUT/'main_cross_evaluations.json')
    result={'main_history':history,'round4':None,'round4_audit':None,'videos':[]}
    if (OUT/'summary.json').exists() and (OUT/'audit.json').exists():
        audit=read(OUT/'audit.json')
        if not audit['passed']:raise ValueError('Round 4 audit did not pass')
        result['round4']=read(OUT/'summary.json');result['round4_audit']=audit
        for row in result['round4']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round4-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    support=ROOT/'out/competitor_jump_round5/support'
    result['round5']=None;result['round5_videos']=[]
    if (support/'summary.json').exists() and (support/'audit.json').exists():
        audit=read(support/'audit.json')
        if not audit['passed']:raise ValueError('Round 5 audit did not pass')
        result['round5']=read(support/'summary.json');result['round5_audit']=audit
        for row in result['round5']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round5-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round5_videos'].append({'trial':row['trial'],'label':row['label'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    r6=ROOT/'out/competitor_jump_round6'
    result['round6']=None;result['round6_videos']=[]
    if (r6/'summary.json').exists() and (r6/'audit.json').exists():
        audit=read(r6/'audit.json')
        if not audit['passed']:raise ValueError('Round 6 audit did not pass')
        result['round6']=read(r6/'summary.json');result['round6_audit']=audit
        for row in result['round6']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round6-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round6_videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    r7=ROOT/'out/competitor_jump_round7'
    result['round7']=None;result['round7_videos']=[]
    if (r7/'summary.json').exists() and (r7/'audit.json').exists():
        audit=read(r7/'audit.json')
        if not audit['passed']:raise ValueError('Round 7 audit did not pass')
        result['round7']=read(r7/'summary.json');result['round7_audit']=audit
        for row in result['round7']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round7-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round7_videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    r8=ROOT/'out/competitor_jump_round8'
    result['round8']=None;result['round8_videos']=[]
    if (r8/'summary.json').exists() and (r8/'audit.json').exists():
        audit=read(r8/'audit.json')
        if not audit['passed']:raise ValueError('Round 8 audit did not pass')
        result['round8']=read(r8/'summary.json');result['round8_audit']=audit;result['round8_audit_url']=asset(r8/'audit.json')
        for row in result['round8']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round8-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round8_videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    r9=ROOT/'out/competitor_dribble_round9'
    result['round9']=None;result['round9_videos']=[]
    if (r9/'summary.json').exists() and (r9/'audit.json').exists():
        audit=read(r9/'audit.json')
        if not audit['passed']:raise ValueError('Round 9 audit did not pass')
        result['round9']=read(r9/'summary.json');result['round9_audit']=audit;result['round9_audit_url']=asset(r9/'audit.json');result['round9_diagnostic_url']=asset(r9/'saved_crossover_geometry.png')
        for row in result['round9']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round9-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round9_videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    r10=ROOT/'out/competitor_dribble_round10'
    result['round10']=None;result['round10_videos']=[]
    if (r10/'summary.json').exists() and (r10/'audit.json').exists():
        audit=read(r10/'audit.json')
        if not audit['passed']:raise ValueError('Round 10 audit did not pass')
        result['round10']=read(r10/'summary.json');result['round10_audit']=audit;result['round10_audit_url']=asset(r10/'audit.json');result['round10_diagnostic_url']=asset(r10/'parent_geometry.json');result['round10_training_url']=asset(r10/'training_curves.png')
        for row in result['round10']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round10-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round10_videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    r11=ROOT/'out/competitor_dribble_round11'
    result['round11']=None;result['round11_videos']=[]
    if (r11/'summary.json').exists() and (r11/'audit.json').exists():
        audit=read(r11/'audit.json')
        if not audit['passed']:raise ValueError('Round 11 audit did not pass')
        result['round11']=read(r11/'summary.json');result['round11_ablation']=paired_validation_diagnostic(read(r11/'validation.json'));result['round11_audit']=audit;result['round11_audit_url']=asset(r11/'audit.json');result['round11_diagnostic_url']=asset(ROOT/'out/competitor_dribble_fingers_prototype/geometry_diagnosis.json');result['round11_training_url']=asset(r11/'training_curves.png');result['round11_protocol_url']=asset(r11/'protocol.json');result['round11_recovery_url']=asset(r11/'recovery_20260929/recovery_audit.json');result['round11_saturation_url']=asset(ROOT/'out/competitor_dribble_fingers_prototype/feature_saturation_controlled_window.json')
        for row in result['round11']['promotions']:
            poster=ROOT/'results-page/dist/assets'/(row['trial']+'-round11-poster.jpg')
            reader=imageio.get_reader(row['video']);imageio.imwrite(poster,reader.get_data(40),quality=90);reader.close()
            result['round11_videos'].append({'trial':row['trial'],'variant':row['variant'],'seed':row['seed'],'video':asset(row['video']),'sheet':asset(row['sheet']),'poster':'assets/'+poster.name,'params':asset(ROOT/row['champion']['frozen_params'])})
    result['round11_pending']=None
    if result['round11'] is None and not (r11/'arena_summary.json').exists():
        required=[r11/'preflight.json',r11/'protocol.json',r11/'candidates.json',r11/'validation.json',r11/'validation_summary.json',r11/'endurance30.json',r11/'endurance30_summary.json',r11/'recovery_20260929/recovery_audit.json']
        if all(p.exists() for p in required):
            preflight=read(r11/'preflight.json');protocol=read(r11/'protocol.json')
            validation=read(r11/'validation_summary.json');endurance=read(r11/'endurance30_summary.json')
            validation_rows=read(r11/'validation.json');endurance_rows=read(r11/'endurance30.json')
            if not preflight.get('passed'):raise ValueError('Round 11 preflight did not pass')
            candidates=read(r11/'candidates.json')
            if {c['label'] for c in candidates}!={'pure','tcn'}:raise ValueError('Round 11 frozen candidates are incomplete')
            for c in candidates:
                if sha(c['params_file'])!=c['params_sha256'] or sha(c['controller'])!=c['controller_sha256']:
                    raise ValueError('Round 11 frozen candidate hash changed')
                if read(r11/(c['variant']+'.json'))['used']!=protocol['training_rollouts_per_family']:
                    raise ValueError('Round 11 completed rollout count does not match the protocol')
            expected_validation=len(protocol['validation_groups'])*len(protocol['validation_seeds'])
            expected_endurance=len(protocol['endurance_groups'])*len(protocol['endurance_seeds'])
            if len(validation_rows)!=expected_validation or len(endurance_rows)!=expected_endurance:
                raise ValueError('Round 11 diagnostic row count does not match the frozen protocol')
            if set(validation)!=set(protocol['validation_groups']):raise ValueError('Round 11 validation groups do not match the frozen protocol')
            if any(validation[k]['n']!=len(protocol['validation_seeds']) for k in protocol['validation_groups']):
                raise ValueError('Round 11 validation summary has incomplete groups')
            recovery=read(r11/'recovery_20260929/recovery_audit.json')
            if not recovery.get('passed'):raise ValueError('Round 11 recovery audit did not pass')
            loss_reasons={label:dict(Counter(str(row['metrics'].get('lost','not recorded')) for row in validation_rows if row['label']==label)) for label in protocol['validation_groups']}
            validation_errors=sum('error' in row.get('metrics',{}) for row in validation_rows)
            endurance_errors=sum('error' in row.get('metrics',{}) for row in endurance_rows)
            if validation_errors or endurance_errors:raise ValueError('Round 11 diagnostics contain runtime errors')
            result['round11_pending']={
                'problem':protocol['problem'],
                'training_rollouts_per_family':protocol['training_rollouts_per_family'],
                'training_seed_count':len(protocol['training_seeds']),
                'validation_seed_count':len(protocol['validation_seeds']),
                'validation_rows':len(validation_rows),
                'validation_errors':validation_errors,
                'validation':validation,
                'loss_reasons':loss_reasons,
                'paired_ablation':paired_validation_diagnostic(validation_rows),
                'endurance30_seed_count':len(protocol['endurance_seeds']),
                'endurance30_rows':len(endurance_rows),
                'endurance30_errors':endurance_errors,
                'endurance30':endurance,
                'recovery_disclosure':recovery['disclosure']
            }
            result['round11_validation_url']=asset(r11/'validation_summary.json')
            result['round11_endurance_url']=asset(r11/'endurance30_summary.json')
            result['round11_protocol_url']=asset(r11/'protocol.json')
            result['round11_recovery_url']=asset(r11/'recovery_20260929/recovery_audit.json')
    r12=ROOT/'out/competitor_dribble_round12'
    result['round12']=None
    if (r12/'arena_summary.json').exists() and (r12/'audit.json').exists():
        audit=read(r12/'audit.json')
        if not audit.get('passed'):raise ValueError('Round 12 audit did not pass')
        result['round12']=read(r12/'arena_summary.json')
        result['round12_audit']=audit
        result['round12_audit_url']=asset(r12/'audit.json')
        result['round12_progress_url']=asset(r12/'PROGRESS.md')
        result['round12_protocol_url']=asset(r12/'protocol.json')
        result['round12_candidates_url']=asset(r12/'candidates.json')
        result['round12_validation_url']=asset(r12/'validation_summary.json')
        result['round12_validation_rows_url']=asset(r12/'validation.json')
        result['round12_endurance_url']=asset(r12/'endurance30_summary.json')
        result['round12_endurance_rows_url']=asset(r12/'endurance30.json')
        result['round12_local_replay_url']=asset(r12/'local_replay.json')
        result['round12_main_replay_url']=asset(r12/'main_replay.json')
        result['round12_raw_urls']={f'{e["trial"]}_{e["label"]}':asset(r12/f'arena_raw_{e["trial"]}_{e["label"]}.json') for e in result['round12']['arena']['entries']}
        result['round12_parameter_urls']={c['label']:asset(Path(c['params_file'])) for c in read(r12/'candidates.json')}
    r13=ROOT/'out/competitor_dribble_round13'
    result['round13']=None
    if (r13/'summary.json').exists() and (r13/'audit.json').exists():
        audit=read(r13/'audit.json')
        if not audit.get('passed'):raise ValueError('Round 13 audit did not pass')
        result['round13']=read(r13/'summary.json')
        result['round13_audit']=audit
        result['round13_audit_url']=asset(r13/'audit.json')
        result['round13_progress_url']=asset(r13/'PROGRESS.md')
        result['round13_summary_url']=asset(r13/'summary.json')
        result['round13_arena_url']=asset(r13/'arena_summary.json')
        result['round13_protocol_url']=asset(r13/'protocol.json')
        result['round13_candidates_url']=asset(r13/'candidates.json')
        result['round13_validation_url']=asset(r13/'validation_summary.json')
        result['round13_validation_rows_url']=asset(r13/'validation.json')
        result['round13_endurance_url']=asset(r13/'endurance30_summary.json')
        result['round13_endurance_rows_url']=asset(r13/'endurance30.json')
        result['round13_local_replay_url']=asset(r13/'local_replay.json')
        result['round13_main_replay_url']=asset(r13/'main_replay.json')
        result['round13_frontier_manifest_url']=asset(r13/'main_frontier_manifest.json')
        result['round13_raw_urls']={f'{e["trial"]}_{e["label"]}':asset(r13/f'arena_raw_{e["trial"]}_{e["label"]}.json') for e in result['round13']['arena']['entries']}
        result['round13_parameter_urls']={c['label']:asset(Path(c['params_file'])) for c in read(r13/'candidates.json')}
    return result
