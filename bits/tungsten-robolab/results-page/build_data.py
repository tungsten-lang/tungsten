"""Export the audited campaign into a portable, static results page."""
import hashlib,json,re,shutil
from pathlib import Path
import imageio.v2 as imageio
ROOT=Path(__file__).resolve().parents[1];DEST=Path(__file__).resolve().parent/'dist';ASSETS=DEST/'assets';ASSETS.mkdir(exist_ok=True)
R1=ROOT/'out/competitor_20260927';R2=ROOT/'out/competitor_jump_round2';R3=ROOT/'out/competitor_jump_round3'
def read(p):return json.loads(p.read_text())
def asset(p):
    p=Path(p);name='__'.join(p.relative_to(ROOT/'out').parts) if p.is_relative_to(ROOT/'out') else p.parent.name+'__'+p.name;out=ASSETS/name
    if not out.exists() or out.stat().st_mtime<p.stat().st_mtime:shutil.copy2(p,out)
    return 'assets/'+name
report=(ROOT/'GPT_CHALLENGERS_20260927.md').read_text()
report=re.sub(r'\]\((/[^)]+)\)',lambda m:']('+asset(Path(m[1]))+')',report)
(DEST/'report.md').write_text(report)
all_promotions=[(i,p) for i,folder in enumerate([R1,R2,R3],1) for p in read(folder/'promotions.json')]
latest={p['trial']:(i,p) for i,p in all_promotions}
original=read(R1/'champions_before.json');current=read(R3/'completion_audit.json')['details']['current_champions']
labels={'search_jump_legal':'Jump distance','search_jump_robust_legal':'Jump robustness','gpt_jump_stable6':'Six-second recovery','bat_power':'Bat power','dribble_crossover_25':'Crossovers'}
units={'search_jump_legal':'m','search_jump_robust_legal':'m','gpt_jump_stable6':'m','bat_power':'m/s','dribble_crossover_25':'crossovers'}
champions=[]
for trial,(round_,p) in latest.items():
    video=Path(p['video']);reader=imageio.get_reader(video);poster=ASSETS/(trial+'-poster.jpg');imageio.imwrite(poster,reader.get_data(min(40,reader.count_frames()-1)),quality=90);reader.close()
    old=[s for s in original.get(trial,{}).get('scores',[]) if abs(s)<1e8]
    champions.append({'trial':trial,'label':labels[trial],'unit':units[trial],'round':round_,'variant':p['variant'],'mean':current[trial]['mean_valid'],'passes':current[trial]['passes'],'n':current[trial]['n'],'original':sum(old)/len(old) if old else None,'originalPasses':len(old),'originalN':len(original.get(trial,{}).get('scores',[])),'mean_diff':p['mean_diff'],'p':p['p'],'seed':p['seed'],'video':asset(video),'poster':'assets/'+poster.name,'params':asset(ROOT/p['champion']['frozen_params'])})
entries=[]
for i,folder in enumerate([R1,R2,R3],1):
    data=read(folder/('summary.json' if i==1 else 'arena_summary.json'));rows=data['arena'] if i==1 else data['entries']
    for r in rows:
        entries.append({'round':i,'trial':r['trial'],'label':labels[r['trial']],'variant':r['variant'],'passes':r['passes'],'n':r['n'],'mean':r.get('mean_valid',r.get('mean_passed')),'mean_diff':r['mean_diff'],'p':r['p'],'wins':r['wins']})
payload={'champions':champions,'entries':entries,'round1':read(R1/'summary.json'),'round2':read(R2/'summary.json'),'round3':read(R3/'summary.json'),'audit':read(R3/'completion_audit.json')['checks'],'sources':{folder.name:asset(folder/'summary.json') for folder in [R1,R2,R3]}}
from build_followup import build as build_followup
payload['followup']=build_followup(asset)
completion=ROOT/'out/gpt_campaign_final/requirements_audit.json'
if completion.exists():
    audit=read(completion)
    if not audit['passed']:raise ValueError('Final campaign audit did not pass')
    payload['completion']=audit
    payload['completion']['evidence_url']=asset(completion)
(DEST/'results-data.js').write_text('window.RESULTS = '+json.dumps(payload,separators=(',',':'))+';\n')
(DEST/'evidence.json').write_text(json.dumps(payload,indent=2)+'\n')
print(json.dumps({'champions':len(champions),'arena_entries':len(entries),'audit_checks':len(payload['audit']),'assets':len(list(ASSETS.iterdir()))}))

from render_evidence import render
render()

# Stable content versions keep embedded artifact browsers from mixing exports.
index=DEST/'index.html';text=index.read_text()
for filename in ['style.css','app.js','round5.js','round6.js','round7.js','round8.js','round9.js','round10.js','round11.js','round12.js','round13.js','results-data.js']:
    version=hashlib.sha256((DEST/filename).read_bytes()).hexdigest()[:12]
    text=re.sub(r'(["\'])'+re.escape(filename)+r'(?:\?v=[a-z0-9]+)?(["\'])',lambda m:m[1]+filename+'?v='+version+m[2],text)
index.write_text(text)
