"""Offline candidate recovery trigger on consumed R9 geometry; no new rollout."""
import hashlib,json
from pathlib import Path
import gpt_competitor as base
import numpy as np
ROOT=base.ROOT;OUT=ROOT/'out/competitor_dribble_round10'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    report=json.loads((OUT/'parent_geometry.json').read_text());rows=[];sources={}
    for row in report['rows']:
        p=OUT/('validation_'+row['label']+'_geometry.npz');a=np.load(p);sources[str(p.relative_to(ROOT))]=sha(p)
        t=a['t'];ball=a['ball'];velocity=np.gradient(ball,t,axis=0);cycles=[]
        for cycle in row['cycles']:
            i=int(np.searchsorted(t,cycle['bounce_start']+.05));receiver=cycle['receiving_hand_inferred_from_phase'];other='r' if receiver=='l' else 'l'
            assert velocity[i,2]>0,(row['label'],i)
            flight=velocity[i,2]/9.81;apex=ball[i]+velocity[i]*flight;apex[2]-=.5*9.81*flight**2
            target=apex+np.array([0.,0.,.12])
            distance={s:float(np.linalg.norm(target-a[s+'_palm'][i])) for s in ['r','l']}
            # A hypothetical fallback, deliberately separate from task outcome.
            wrong_side=apex[1]<-.04 if receiver=='l' else apex[1]>.04
            trigger=wrong_side and distance[receiver]-distance[other]>.15 and distance[receiver]>.25 and distance[other]<.45
            cycles.append({'bounce':cycle['bounce_start'],'sample_time':float(t[i]),'receiver':receiver,'predicted_apex_xyz':apex.tolist(),'ball_time_to_apex_s':float(flight),'distance_to_palm_m':distance,'hypothetical_fallback':bool(trigger),'minimum_recorded_receiver_surface_gap_m':cycle['closest_surface_gap_m'],'last_cycle':cycle is row['cycles'][-1]})
        rows.append({'label':row['label'],'seed':row['seed'],'cycles':cycles,'triggers_before_last':sum(c['hypothetical_fallback'] for c in cycles[:-1]),'trigger_on_last':cycles[-1]['hypothetical_fallback']})
    sources['out/competitor_dribble_round10/parent_geometry.json']=sha(OUT/'parent_geometry.json')
    result={'scope':'Offline counterfactual trigger only on consumed R9 seed289101 traces. Velocity uses ~100 Hz finite differences. A predicted trigger says nothing about whether a changed controller would catch the ball. Surface separation does not establish official contact. This does not change the running R10 protocol or selection.','hypothesis':'At 50 ms after a floor bounce, if predicted apex remains on the previous hand side and is >15 cm closer to its current palm, current receiver distance >25 cm and previous palm distance <45 cm, let the previous hand attempt recovery. Any same-hand catch must remain an official failed crossover.','sources_sha256':sources,'rows':rows}
    (OUT/'recovery_trigger_diagnosis.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'scope':result['scope'],'results':[{k:r[k] for k in ['label','seed','triggers_before_last','trigger_on_last']}|{'last_cycle':r['cycles'][-1]} for r in rows]},indent=2))
if __name__=='__main__':main()
