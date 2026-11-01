"""Bounded bitrate probes. The result is the lowest tested passing bitrate."""
import json
import math
import pathlib
import re
from inputs import write_json
from qc import ffmpeg, encoded_text, captions


def metrics(reference,candidate,runner,vmaf=False):
    filter_name='libvmaf' if vmaf else 'ssim'
    result=ffmpeg(runner,['-v','info','-i',candidate,'-i',reference,'-lavfi',f'[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]{filter_name}', '-an','-f','null','-'])
    text=result.stderr.decode(); match=re.search(r'VMAF score:\s*([\d.]+)' if vmaf else r'All:([\d.]+)',text)
    if not match: raise ValueError('quality metric unavailable or did not report a score: '+filter_name)
    return float(match[1])


def search(project,native,source,plan,options,directory):
    directory=pathlib.Path(directory); directory.mkdir(parents=True,exist_ok=True)
    settings=plan['profile']['quality']; low=settings.get('minimum_bitrate',500000); high=settings.get('maximum_bitrate',options.get('bitrate',8000000))
    maximum=settings.get('max_probes',6); count=min(settings.get('probe_frames',24),plan['frames'])
    frames=settings.get('sample_frames',[0,max(0,(plan['frames']-count)//2),max(0,plan['frames']-count)])
    if not frames or any(type(f)is not int or not 0<=f<=plan['frames']-count for f in frames): raise ValueError('quality sample_frames must start complete probe clips within the output')
    frames=sorted(set(frames)); base=dict(options,audio=False,tc=False,chapters=False,edit_lists=False,frames=count,format='mov'); base.pop('resume_dir',None); base.pop('quality',None)
    references=[]
    for i,frame in enumerate(frames):
        reference=directory/f'reference-{i}.mov'; opts=dict(base,start=options.get('start',0)+frame,codec='prores422hq'); opts.pop('bitrate',None); opts.pop('level',None)
        native.request('transcode',source,opts,directory,reference); references.append(reference)
    trials=[]; winner=None
    # Geometric ladder covers endpoints with a strict bound and deterministic ordering.
    rates=sorted(set(round(low*(high/low)**(i/(maximum-1))) for i in range(maximum))) if maximum>1 else [high]
    for bits in rates:
        checks=[]
        for i,(frame,reference) in enumerate(zip(frames,references)):
            path=directory/f'{bits}-{i}.mov'; opts=dict(base,start=options.get('start',0)+frame,bitrate=bits)
            native.request('transcode',source,opts,directory,path)
            ssim=metrics(reference,path,native.runner); score=dict(frame=frame,ssim=ssim,ok=ssim>=settings.get('minimum_ssim',.98))
            if settings.get('minimum_vmaf') is not None:
                score['vmaf']=metrics(reference,path,native.runner,True); score['ok'] &=score['vmaf']>=settings['minimum_vmaf']
            # Text compression checks apply to every probe frame in the configured ROI.
            if plan['profile']['text'].get('enabled') and plan['profile']['text'].get('burned'):
                local=dict(plan,start=0,frames=count); cues=[dict(start=0,end=count*plan['rate'][1]/plan['rate'][0],text='probe')]
                score['text']=encoded_text(path,reference,cues,plan['profile']['text'],local,native.runner); score['ok'] &=score['text']['ok']
            checks.append(score)
        trial=dict(bitrate=bits,ok=all(c['ok'] for c in checks),samples=checks); trials.append(trial)
        if trial['ok']: winner=bits; break
    result=dict(ok=winner is not None,bitrate=winner,trials=trials,selection='lowest tested passing bitrate; sampled reference metrics, final-file QC still required')
    write_json(directory/'quality.json',result)
    if not result['ok']: raise ValueError('no tested bitrate passed reference quality thresholds')
    return result
