"""Plot completed R11 training logs; never treats them as validation evidence."""
import hashlib,json,math,os
from pathlib import Path
os.environ.setdefault('MPLCONFIGDIR','/private/tmp/robolab-r11-mpl')
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'out/competitor_dribble_round11'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    colors={'pure':'#b87333','tcn':'#247b79'};names={'pure':'Pure search','tcn':'Temporal residual'};sources={};series={}
    for v in ['pure','tcn']:
        log=OUT/f'{v}.jsonl';summary=OUT/f'{v}.json';rows=[json.loads(x) for x in log.read_text().splitlines() if x.strip()];result=json.loads(summary.read_text())
        assert len(rows)==128 and rows[-1]['used']==result['used']==result['budget']==4096,'Wait for both complete training budgets'
        assert rows[0]['used']==32 and all(b['used']-a['used']==32 for a,b in zip(rows,rows[1:]))
        assert all(math.isfinite(r['best']) for r in rows)
        assert all(b['best']>=a['best'] for a,b in zip(rows,rows[1:]))
        assert rows[-1]['best']==result['best']
        sources[str(log.relative_to(ROOT))]=sha(log);sources[str(summary.relative_to(ROOT))]=sha(summary)
        series[v]={'rollouts':[r['used'] for r in rows],'best':[r['best'] for r in rows],'initial':rows[0]['best'],'final':rows[-1]['best']}
    assert series['pure']['initial']==series['tcn']['initial'],'Common zero-head start must score identically on shared seeds'
    plt.rcParams.update({'font.size':10,'axes.titlesize':12,'axes.spines.top':False,'axes.spines.right':False})
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.8))
    for v,d in series.items():
        gain=[y-d['initial'] for y in d['best']]
        for ax,y in zip(axes,[d['best'],gain]):ax.step(d['rollouts'],y,where='post',color=colors[v],lw=2.4,label=names[v]);ax.scatter(d['rollouts'][-1],y[-1],color=colors[v],s=28,zorder=3)
        axes[0].annotate(f"{d['final']:.3f}",(4096,d['final']),xytext=(-8,8),textcoords='offset points',ha='right',color=colors[v],fontweight='bold')
        axes[1].annotate(f"+{gain[-1]:.3f}",(4096,gain[-1]),xytext=(-8,8),textcoords='offset points',ha='right',color=colors[v],fontweight='bold')
    axes[0].set(title='Best training objective',ylabel='Mean / worst-start aggregate')
    axes[1].set(title='Gain over the common zero-head baseline',ylabel='Change in training objective')
    for ax in axes:
        ax.set_xlim(0,4260);ax.set_xlabel('Training rollouts per family');ax.set_xticks([0,1024,2048,3072,4096]);ax.grid(alpha=.22);ax.margins(y=.15)
    axes[1].axhline(0,color='#aaaaaa',lw=.7);axes[0].legend(loc='lower right',frameon=False)
    fig.suptitle('Round 11: matched fingered-body training from a common start',fontsize=14,fontweight='bold',y=.98)
    fig.subplots_adjust(left=.08,right=.97,top=.82,bottom=.28,wspace=.25)
    fig.text(.5,.09,'Training evidence only — not fresh validation or arena verdicts.\n4,096 recorded completed rollouts per family · 32 shared starts · 12 backbone parameters + 20 readout weights\nThe interrupted first temporal attempt may include unknown unlogged compute before recovery.',ha='center',fontsize=9,color='#555555')
    image=OUT/'training_curves.png';fig.savefig(image,dpi=165,facecolor='white');plt.close(fig)
    sources['playground/gpt_finger_training_plot.py']=sha(__file__)
    evidence={'scope':'Completed training logs only. Best objectives and gains relative to the common zero-head baseline do not establish generalization or architecture superiority.','sources_sha256':sources,'series':series,'image':str(image),'image_sha256':sha(image),'visual_review_pending':True}
    (OUT/'training_curves.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'image':str(image),'source_files':len(sources),'families':{v:{k:d[k] for k in ['initial','final']} for v,d in series.items()}}))
if __name__=='__main__':main()
