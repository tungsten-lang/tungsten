from pathlib import Path
import json
import numpy as np
OUT=Path(__file__).resolve().parents[1]/'out/competitor_dribble_round9'

def make_figure(rows):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(2,2,figsize=(11.2,6.8),layout='constrained')
    colors={'ball':'#1d3449','r_palm':'#e17c40','l_palm':'#328b88'}
    for row,seed in enumerate([288001,288002]):
        record=next(r for r in rows if r['label']=='old_tcn' and r['seed']==seed)
        d=np.load(OUT/f'preflight_old_tcn_{seed}_geometry.npz');t=d['t']
        start=record['cycles'][-2]['bounce_start']-.08;end=record['estimated_loss_time']+.03
        take=(t>=start)&(t<=end)
        for col,(coord,label) in enumerate([(2,'Height above ground, m'),(1,'Lateral position, m')]):
            ax=axes[row,col]
            for key,title in [('ball','Ball centre'),('r_palm','Right palm'),('l_palm','Left palm')]:
                ax.plot(t[take],d[key][take,coord],label=title,color=colors[key],lw=2 if key=='ball' else 1.5,ls='-' if key=='ball' else '--')
            for cycle in record['cycles'][-2:]:ax.axvline(cycle['bounce_start'],color='#9099a1',lw=.7,alpha=.7)
            ax.axvline(record['estimated_loss_time'],color='#ac404a',lw=1.2,ls=':')
            ax.set(xlabel='Simulation time, s',ylabel=label,title=f'Seed {seed} · '+('final two bounce cycles' if col==0 else 'outgoing pass and receiving hand'))
            ax.grid(alpha=.15);ax.spines[['top','right']].set_visible(False)
            if col==1:ax.axhline(0,color='#9099a1',lw=.6)
    axes[0,0].legend(loc='upper right',fontsize=8)
    fig.suptitle('Where the saved crossover champion loses the ball',fontsize=16,fontweight='bold')
    fig.supxlabel('Consumed preflight starts • 100 Hz measured joint geometry • dotted red: approximate loss time' + chr(10) + 'Palm and ball centre curves do not represent official force-threshold contact.',fontsize=9)
    fig.savefig(OUT/'saved_crossover_geometry.png',dpi=160);plt.close(fig)

if __name__=='__main__':make_figure(json.loads((OUT/'saved_geometry_diagnosis.json').read_text())['rows'])
