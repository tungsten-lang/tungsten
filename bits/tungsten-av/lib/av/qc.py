"""Independent QC of delivered bytes, bounded in RAM and tied to file hashes."""
import json
import math
import pathlib
import re
import tempfile
from inputs import sha256, write_json


def ffmpeg(runner,args):
    return runner.run(['ffmpeg','-nostdin','-hide_banner',*args],capture=True)


def audio(path,settings,runner,directory):
    import numpy as np
    directory=pathlib.Path(directory); directory.mkdir(parents=True,exist_ok=True)
    result=ffmpeg(runner,['-v','info','-i',path,'-map','0:a:0','-af','loudnorm=I=-23:TP=-1:LRA=7:print_format=json','-f','null','-'])
    match=re.search(r'\{\s*"input_i".*?\}',result.stderr.decode(),re.S)
    if not match: raise ValueError('audio meter returned no measurements')
    meter=json.loads(match[0]); integrated=float(meter['input_i']); peak=float(meter['input_tp'])
    # Write decoded samples to disk; chunked statistics never retain the full film in RAM.
    raw=directory/'audio.f32'
    probe=runner.run(['ffprobe','-v','error','-select_streams','a:0','-show_entries','stream=sample_rate,channels','-of','json',path],capture=True)
    stream=json.loads(probe.stdout)['streams'][0]; channels=int(stream['channels']); sr=int(stream['sample_rate'])
    ffmpeg(runner,['-v','error','-y','-i',path,'-map','0:a:0','-c:a','pcm_f32le','-f','f32le',raw])
    clipped=0; frames=0; longest=run=0; energy=np.zeros(channels); threshold=10**(settings.get('silence_threshold',-60)/20)
    try:
        with raw.open('rb') as src:
            while block:=src.read(65536*channels*4):
                runner.check_cancelled(); samples=np.frombuffer(block,dtype='<f4').reshape(-1,channels)
                if not np.isfinite(samples).all(): raise ValueError('decoded audio contains nonfinite samples')
                clipped+=int((np.abs(samples)>=1-1/32768).sum()); energy+=(samples.astype(np.float64)**2).sum(axis=0); frames+=len(samples)
                quiet=np.max(np.abs(samples),axis=1)<threshold
                # Silence runs can span chunk boundaries.
                changes=np.flatnonzero(np.diff(np.r_[False,quiet,False].astype(np.int8)))
                if not len(changes): run=0; continue
                if changes[0]>0: run=0
                for start,end in zip(changes[::2],changes[1::2]):
                    length=int(end-start)+(run if start==0 else 0); longest=max(longest,length)
                    run=length if end==len(quiet) else 0
                if not quiet[-1]: run=0
    finally: raw.unlink(missing_ok=True)
    rms=np.sqrt(energy/max(frames,1)); difference=float(20*math.log10(max(rms)/max(min(rms),1e-12))) if channels>1 and max(rms)>0 else 0
    target=settings.get('target',-16); tolerance=settings.get('tolerance',1)
    checks=dict(loudness=math.isfinite(integrated) and abs(integrated-target)<=tolerance,
                true_peak=math.isfinite(peak) and peak<=settings.get('true_peak',-1),
                clipped_samples=clipped<=settings.get('max_clipped_samples',0),
                silence=longest/sr<=settings.get('max_silence',10),
                channel_balance=difference<=settings.get('max_channel_difference',6))
    return dict(ok=all(checks.values()),checks=checks,integrated_lufs=integrated if math.isfinite(integrated) else None,true_peak_dbtp=peak if math.isfinite(peak) else None,clipped_samples=clipped,longest_silence_seconds=longest/sr,channel_difference_db=difference,decoded_frames=frames,sample_rate=sr,channels=channels)


def captions(path):
    content=pathlib.Path(path).read_text(encoding='utf-8-sig'); result=[]; previous=-1
    def seconds(value):
        h,m,s,ms=map(int,re.split('[:,.]',value));
        if m>=60 or s>=60: raise ValueError('invalid subtitle timestamp')
        return h*3600+m*60+s+ms/1000
    for block in re.split(r'\n\s*\n',content.strip().replace('\r\n','\n')):
        lines=block.splitlines()
        if not lines: continue
        if lines[0].isdigit(): lines=lines[1:]
        if len(lines)<2: raise ValueError('subtitle cue needs a timestamp and text')
        match=re.fullmatch(r'(\d{2,}:\d{2}:\d{2}[,.]\d{3})\s+-->\s+(\d{2,}:\d{2}:\d{2}[,.]\d{3})',lines[0])
        if not match: raise ValueError('invalid SRT cue timestamp: '+lines[0])
        start,end=map(seconds,match.groups())
        if start<previous or end<=start: raise ValueError('subtitle times must be ordered and have positive duration')
        previous=start; result.append(dict(start=start,end=end,text='\n'.join(lines[1:])))
    return result


def luminance(colour):
    if not re.fullmatch('#[0-9a-fA-F]{6}',colour): raise ValueError('text colours require #rrggbb')
    values=[int(colour[i:i+2],16)/255 for i in (1,3,5)]; values=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in values]
    return sum(a*b for a,b in zip(values,(.2126,.7152,.0722)))


def layout(cues,settings,width,height,font):
    import glyphs
    import xml.etree.ElementTree as ET
    size=settings.get('size',48); minimum=settings.get('minimum_size',24); safe=settings.get('safe_area',.05)
    box=settings.get('box',[safe,.7,1-2*safe,.25]); x,y,w,h=box
    if not 0<=safe<.5 or not (x>=safe and y>=safe and x+w<=1-safe+1e-9 and y+h<=1-safe+1e-9): raise ValueError('caption box violates configured safe area')
    foreground=luminance(settings.get('foreground','#ffffff')); background=luminance(settings.get('background','#000000'))
    contrast=(max(foreground,background)+.05)/(min(foreground,background)+.05)
    issues=[]
    for i,cue in enumerate(cues):
        line_widths=[]
        for line in cue['text'].splitlines():
            if not line.strip(): continue
            svg=ET.fromstring(glyphs.text_svg(line,font,size)); line_widths.append(float(svg.attrib['width']))
        if size<minimum or max(line_widths,default=0)>w*width or len(line_widths)*size*1.3>h*height: issues.append(dict(cue=i+1,problem='text does not fit at the configured size'))
    return dict(ok=not issues and contrast>=settings.get('minimum_contrast',4.5),issues=issues,contrast=contrast,font=str(font),size=size,box=box,cues=len(cues))


def rgb_frame(path,frame,width,height,runner,fit='stretch',fps=None):
    import numpy as np
    scale=f'scale={width}:{height}:flags=lanczos'
    if fit=='contain': scale=f'scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2'
    if fit=='cover': scale=f'scale={width}:{height}:force_original_aspect_ratio=increase:flags=lanczos,crop={width}:{height}'
    args=['-v','error']
    if fps: args+=['-ss',format(frame*fps[1]/fps[0],'.12f')]
    args+=['-i',path,'-vf',scale if fps else f"select=eq(n\\,{frame}),{scale}",'-fps_mode','passthrough','-frames:v','1','-pix_fmt','rgb24','-f','rawvideo','-']
    data=ffmpeg(runner,args).stdout
    if len(data)!=width*height*3: raise ValueError('cannot decode reference/output frame '+str(frame))
    return np.frombuffer(data,np.uint8).reshape(height,width,3).astype(float)/255


def encoded_text(path,reference,cues,settings,plan,runner):
    import numpy as np
    box=settings.get('box',[.05,.7,.9,.25]); width,height=plan['width'],plan['height']; x,y,w,h=box
    x0,y0,x1,y1=round(x*width),round(y*height),round((x+w)*width),round((y+h)*height)
    fps=plan['rate'][0]/plan['rate'][1]
    frames=sorted(set(min(plan['frames']-1,int((c['start']+c['end'])/2*fps)) for c in cues))
    # Each cue is checked. A project may use a separate banding sample bound, but text is never silently truncated.
    checks=[]
    for frame in frames:
        a=rgb_frame(reference,frame+plan['start'],width,height,runner,plan['profile'].get('fit','stretch'),plan['rate'])[y0:y1,x0:x1]
        b=rgb_frame(path,frame,width,height,runner,fps=plan['rate'])[y0:y1,x0:x1]
        ga=np.mean(a,axis=2); gb=np.mean(b,axis=2)
        edge=np.hypot(*np.gradient(ga)); encoded=np.hypot(*np.gradient(gb)); mask=edge>.08
        if not mask.any(): checks.append(dict(frame=frame,ok=False,problem='reference caption ROI has no edges')); continue
        recall=float((encoded[mask]>.04).mean()); error=float(np.abs(a-b).mean())
        checks.append(dict(frame=frame,edge_recall=recall,mean_error=error,ok=recall>=settings.get('minimum_edge_recall',.85) and error<=settings.get('max_error',.06)))
    return dict(ok=bool(checks) and all(c['ok'] for c in checks),frames=checks,scope='reference ROI edge retention and pixel error; no OCR claim')


def uncovered(start,end,allowed):
    remaining=[(start,end)]
    for lo,hi in sorted(allowed):
        remaining=[part for a,b in remaining for part in ((a,min(b,lo)),(max(a,hi),b)) if part[1]>part[0]]
    return remaining


def anomalies(path,settings,runner,plan,timeline=None):
    black=settings.get('black_min',1); freeze=settings.get('freeze_min',3); noise=settings.get('noise',.001)
    result=ffmpeg(runner,['-v','info','-xerror','-i',path,'-an','-vf',f'scale=320:-2,blackdetect=d={black}:pix_th=0.10,freezedetect=n={noise}:d={freeze}','-f','null','-'])
    log=result.stderr.decode(); duration=plan['frames']*plan['rate'][1]/plan['rate'][0]
    events=[]
    for match in re.finditer(r'black_start:([\d.]+) black_end:([\d.]+)',log): events.append(dict(kind='black',start=float(match[1]),end=float(match[2])))
    starts=[]
    for match in re.finditer(r'freeze_(start|end):\s*([\d.]+)',log):
        if match[1]=='start': starts.append(float(match[2]))
        elif starts: events.append(dict(kind='freeze',start=starts.pop(0),end=float(match[2])))
    events.extend(dict(kind='freeze',start=x,end=duration) for x in starts)
    allowed={kind:list(settings.get('allow_'+kind,[])) for kind in ('black','freeze')}
    if timeline:
        fps=plan['rate'][0]/plan['rate'][1]; offset=plan['start']/fps
        for item in timeline['tracks'][0]['items']:
            kind=item.get('kind'); lo=item.get('f0',0)/fps-offset; hi=item.get('f1',item.get('f0',0)+item.get('n',0))/fps-offset
            if kind=='black': allowed['black'].append([lo,hi])
            if kind in ('black','still','card'): allowed['freeze'].append([lo,hi])
    for event in events:
        event['unexpected']=uncovered(event['start'],event['end'],allowed[event['kind']])
        event['unexpected']=[r for r in event['unexpected'] if r[1]-r[0] >= (black if event['kind']=='black' else freeze)-.05]
    unexpected=[e for e in events if e['unexpected']]
    return dict(ok=not unexpected or settings.get('policy','fail')=='report',events=events,unexpected=len(unexpected),decoded_entire_video=True,scope='320-pixel detection; all output pictures are decoded')


def source_gates(gates):
    results=[]
    for gate in gates:
        path=pathlib.Path(gate['path'])
        if path.stat().st_size>16*1024**2: raise ValueError('source gate report exceeds 16 MiB')
        match=re.search(gate['pattern'],path.read_text(),re.M); equal=gate.get('equal')
        ok=match is not None and (not equal or match.group(equal[0])==match.group(equal[1]))
        results.append(dict(file=str(path),sha256=sha256(path),pattern=gate['pattern'],ok=ok))
    return dict(ok=all(item['ok'] for item in results),reports=results)


def run(project,native,path,plan,directory,reference=None,timeline=None,subtitle_paths=None):
    directory=pathlib.Path(directory); directory.mkdir(parents=True,exist_ok=True); profile=plan['profile']; results={}; before=sha256(path)
    if plan.get('gates'): results['source_gates']=source_gates(plan['gates'])
    if profile['loudness']['enabled']: results['audio']=audio(path,profile['loudness'],native.runner,directory)
    if profile['text']['enabled']:
        settings=profile['text']; declarations=project.associated('subtitles',profile['name'])
        paths=subtitle_paths if subtitle_paths is not None else [project.path(i['name']) for i in declarations]
        cues=[cue for path in paths for cue in captions(path)]
        if not cues: raise ValueError('text QC needs a nonempty subtitle file')
        font=project.path(settings['font']) if settings.get('font') else None
        if not font: raise ValueError('text QC requires an explicit av.text font: file')
        duration=plan['frames']*plan['rate'][1]/plan['rate'][0]
        if any(c['end']>duration+.001 for c in cues): raise ValueError('caption extends beyond output duration')
        results['text_layout']=layout(cues,settings,plan['width'],plan['height'],font)
        if settings.get('burned'):
            if not reference: raise ValueError('burned text QC requires a reference source')
            results['encoded_text']=encoded_text(path,reference,cues,settings,plan,native.runner)
    if profile['anomalies']['enabled']: results['anomalies']=anomalies(path,profile['anomalies'],native.runner,plan,timeline)
    if profile['banding']:
        import banding
        spec=dict(profile['banding'])
        if spec.get('auto'):
            from timeline import Timeline
            t=Timeline.load(project.root,{'episode':timeline.get('av_episode',project.settings['timeline']) if timeline else project.settings['timeline'],'cut':project.settings.get('cut','full')},require_resolved=False)
            if timeline: t.resolved=timeline
            document=json.loads(t.episode.read_text()); asset_root=(t.episode.parent/document.get('root','.')).resolve()
            short=profile.get('role')=='short'
            spec=banding.film_manifest(asset_root,spec,short,t)
        spec['movie']=str(path); results['banding']=banding.run(spec,asset_root if profile['banding'].get('auto') else project.root,directory/'banding.json',native.runner)
    if sha256(path)!=before: raise ValueError('output changed while running QC')
    result=dict(ok=all(r['ok'] for r in results.values()),sha256=before,checks=results)
    write_json(directory/'qc.json',result); return result


def outline_captions(cues,settings,width,height,font):
    """Shape once with the exact font; native Canvas paints the resulting paths."""
    import glyphs
    import xml.etree.ElementTree as ET
    report=layout(cues,settings,width,height,font)
    if not report['ok']: raise ValueError('caption layout fails before rendering: '+str(report))
    size=settings.get('size',48); box=settings.get('box',[.05,.7,.9,.25]); x,y,w,h=box; output=[]
    for cue in cues:
        lines=[]; texts=cue['text'].splitlines()
        for i,text in enumerate(texts):
            if not text.strip(): continue
            svg=ET.fromstring(glyphs.text_svg(text,font,size)); vx,vy,vw,vh=map(float,svg.attrib['viewBox'].split())
            left=x*width+(w*width-vw)/2-vx; top=y*height+(h*height-len(texts)*size*1.3)/2+i*size*1.3-vy
            lines.append(dict(x=left,y=top,paths=[p.attrib['d'] for p in svg.iter() if p.tag.endswith('path')]))
        output.append(dict(start_ms=round(cue['start']*1000),end_ms=round(cue['end']*1000),lines=lines,
                           box=[round(x*width),round(y*height),round(w*width),round(h*height)],
                           foreground=settings.get('foreground','#ffffff'),background=settings.get('background','#000000')))
    return output
