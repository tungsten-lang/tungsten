"""Plot consumed preparatory-motion evidence; no simulation or new score."""
import hashlib,json,os
from pathlib import Path
os.environ.setdefault('MPLCONFIGDIR','/private/tmp/robolab-bat-preparation-mpl')
import gpt_competitor as base
import numpy as np
import mujoco
from tasks.bat import TASK
ROOT=base.ROOT;OUT=ROOT/'out/competitor_bat_prepare_prototype'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    sim=base.Sim(TASK());inds=[int(sim.m.jnt_qposadr[j]) for j in range(sim.m.njnt) if (mujoco.mj_id2name(sim.m,mujoco.mjtObj.mjOBJ_JOINT,j) or '').startswith(('l_shoulder','r_shoulder','l_elbow','r_elbow','l_wrist','r_wrist'))]
    plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    fig,axes=plt.subplots(1,2,figsize=(11.4,4.7),sharey=True);sources={};peaks=[]
    for ax,v,title in zip(axes,['pure','tcn'],['Pure phase residual','Temporal residual']):
        ax.axvspan(2.2,2.56,color='#aaaaaa',alpha=.09)
        for label,color,title2 in [('off','#78818b','Preparation disabled'),('on','#247b79','Preparation enabled')]:
            p=OUT/f'{label}_{v}_271001.npz';sources[str(p.relative_to(ROOT))]=sha(p);a=np.load(p);t=a['t'];speed=np.sqrt(np.mean(np.gradient(a['q'][:,inds],t,axis=0)**2,axis=1));mask=(t>=2.18)&(t<=3.05);ax.plot(t[mask],speed[mask],color=color,lw=2,label=title2);peaks.append(float(speed[mask].max()))
        ax.axhline(.1,color='#b87333',ls='--',lw=1,label='Quiet threshold · 0.1 rad/s');ax.axvline(2.56,color='#999999',ls=':',lw=1);ax.axvline(2.9,color='#999999',ls=':',lw=1)
        ax.set(title=title,xlabel='Simulation time (seconds)',xlim=(2.18,3.05));ax.grid(alpha=.18)
    top=max(peaks)*1.14
    for ax in axes:
        ax.set_ylim(0,top);ax.text(2.36,top*.96,'Leg lift',ha='center',va='top',color='#666666');ax.text(2.72,top*.96,'Stride',ha='center',va='top',color='#666666');ax.text(2.90,top*.96,'Pitch release',ha='right',va='top',rotation=90,color='#666666')
    axes[0].set_ylabel('Measured arm RMS joint speed (rad/s)');axes[0].legend(loc='upper left',bbox_to_anchor=(0,-.18),frameon=False,ncol=1,fontsize=8)
    fig.suptitle('Preparatory correction reduces the interior stride quiet interval',fontsize=14,fontweight='bold')
    fig.subplots_adjust(left=.08,right=.98,top=.84,bottom=.31,wspace=.16)
    fig.text(.55,.11,'Stride quiet interval: pure 89.1 → 0 ms; temporal 89.1 → 29.7 ms.\nThe 99 ms onset interval remains. This is not a perceptual hitch or arena verdict.',ha='center',fontsize=9,color='#555555')
    fig.text(.55,.035,'Consumed seed 271001 · approximately 10 ms q samples · untrained integration diagnostic',ha='center',fontsize=9,color='#555555')
    path=OUT/'preparation_speed.png';fig.savefig(path,dpi=165,facecolor='white');plt.close(fig)
    sources['playground/gpt_bat_preparation_plot.py']=sha(__file__);sources['out/competitor_bat_prepare_prototype/quiet_locations.json']=sha(OUT/'quiet_locations.json')
    with (OUT/'preparation_speed.json').open('x') as f:json.dump({'sources_sha256':sources,'image':str(path),'image_sha256':sha(path),'visual_review_pending':True,'scope':'Illustrates consumed diagnostic start only. No training, fresh validation, arena or perceptual claim.'},f,indent=2)
    print(str(path))
if __name__=='__main__':main()
