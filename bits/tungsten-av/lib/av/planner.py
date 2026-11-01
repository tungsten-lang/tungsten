"""Read-only preflight and explicit dependency/clock/colour/resource plans."""
import fractions
import importlib.util
import json
import pathlib
import shutil
import sys
from config import ConfigError
from resources import Budget


def selected(profiles,names):
    if not names: return profiles
    wanted=set(names)
    unknown=wanted-profiles.keys()
    if unknown: raise ConfigError('unknown profiles: '+', '.join(sorted(unknown)))
    for name in list(wanted):
        parent=profiles[name].get('from')
        while parent:
            wanted.add(parent); parent=profiles[parent].get('from')
    return {name:p for name,p in profiles.items() if name in wanted}


def video_stream(probe):
    return next(s for s in probe['streams'] if s['codec_type']=='video' and not s.get('disposition',{}).get('attached_pic'))


def colour_guard(probe,contract):
    video=video_stream(probe)
    expected={'color_primaries':'bt709','color_transfer':'bt709','color_space':'bt709','color_range':'tv'}
    missing=[]
    for key,value in expected.items():
        actual=video.get(key)
        if actual in (None,'unknown','unspecified'): missing.append(key)
        elif actual!=value: raise ConfigError(f'unsupported source colour {key}={actual}; expected {value}. Convert to BT.709 limited SDR explicitly before rendering')
    if missing and contract.get('untagged')!='bt709': raise ConfigError('untagged source colour: '+', '.join(missing)+'; declare untagged: :bt709 only for known BT.709 sources')
    pixel=video.get('pix_fmt','')
    if '444' in pixel or '12' in pixel or '16' in pixel: raise ConfigError('source pixel format unsupported by the native delivery path: '+pixel)
    return dict(contract=contract,source={key:video.get(key) for key in expected},assumed=missing)


def resolve_timeline(project,native,path=None,cut=None):
    path=path or project.path(project.settings['timeline']); cut=cut or project.settings.get('cut','full')
    result=native.runner.run([native.toolchain/'bin/tungsten',native.package/'lib/av/timeline.w','--',path,cut],capture=True)
    return json.loads(result.stdout.decode().splitlines()[-1])


def timeline_inputs(project,path=None):
    path=path or project.path(project.settings['timeline']); document=json.loads(path.read_text())
    root=(path.parent/document.get('root','.')).resolve(); paths=[path]
    paths.extend(root/a['path'] for a in document.get('assets',{}).values())
    programs=list(document.get('programs',{}).values())
    for section in [document,*document.get('cuts',{}).values()]:
        programs.extend(shot['program'] for shot in section.get('shots',[]) if shot.get('kind')=='program')
    for program in programs:
        paths.append(root/program['source'])
        for entry in program.get('data',[]): paths.append(root/(entry if isinstance(entry,str) else entry['path']))
    return document,root,paths


def chapters(project,name,fps,frames):
    from timeline import snap
    declarations=project.associated('chapters',name)
    if not declarations: return None
    if len(declarations)>1: raise ConfigError('only one chapter file per profile is supported')
    item=declarations[0]; path=project.path(item['name']); fmt=item.get('format','json' if path.suffix=='.json' else 'text')
    if fmt=='json':
        values=json.loads(path.read_text()); result=[]
        for item in values:
            if isinstance(item,list) and len(item)==2: title,frame=item
            else:
                title=item['title']; frame=item.get('frame')
                if frame is None: frame=snap(fractions.Fraction(str(item['seconds']))*fractions.Fraction(*fps))
            if not isinstance(title,str) or type(frame)is not int: raise ConfigError('chapters require title strings and integer frames')
            result.append([title,frame])
    elif fmt=='text':
        result=[]
        for line in path.read_text().splitlines():
            if not line.strip(): continue
            clock,title=line.split(' ',1); parts=clock.split(':'); seconds=sum(fractions.Fraction(v)*60**i for i,v in enumerate(reversed(parts)))
            result.append([title.strip(),snap(seconds*fractions.Fraction(*fps))])
    else: raise ConfigError('chapters format must be json or text')
    if any(not 0<=c[1]<frames or not c[0] for c in result) or any(a[1]>=b[1] for a,b in zip(result,result[1:])): raise ConfigError('chapter frames must increase within the output duration')
    return result


def build(project,native,names=None,require_space=True):
    from inputs import sha256
    if sha256(project.file)!=project.content_sha256: raise ConfigError('Bitfile changed after parsing; run the command again')
    profiles=selected(project.profiles(),names); caps=native.capabilities()
    if not caps['available']: raise ConfigError('native AV rendering requires macOS VideoToolbox')
    required={'numpy','PIL'}
    if any(p['text']['enabled'] or any(i.get('mode')=='timeline' for i in project.associated('subtitles',n)) for n,p in profiles.items()): required.update(('fontTools','uharfbuzz'))
    absent_modules=[name for name in sorted(required) if importlib.util.find_spec(name) is None]
    if absent_modules: raise ConfigError('missing Python modules: '+', '.join(absent_modules)+'; install apps/studio/tools/tw/requirements.txt or set TW_PYTHON')
    missing=[tool for tool in ('ffmpeg','ffprobe') if not shutil.which(tool)]
    if missing: raise ConfigError('missing tools: '+', '.join(missing))
    if any(p['quality'].get('minimum_vmaf') is not None for p in profiles.values()):
        filters=native.runner.run(['ffmpeg','-hide_banner','-filters'],capture=True).stdout.decode()
        if 'libvmaf' not in filters: raise ConfigError('minimum_vmaf requires an FFmpeg build with libvmaf')
    source=None; timeline=None; inputs=[project.file]; facts={}
    if project.settings.get('source'):
        source=project.path(project.settings['source'])
        if not source.is_file(): raise ConfigError('missing source: '+str(source))
        facts=native.facts(source); probe=native.probe(source); facts['has_audio']=any(s['codec_type']=='audio' for s in probe['streams']); inputs.append(source)
    else:
        document,root,paths=timeline_inputs(project); inputs.extend(paths)
        timeline=resolve_timeline(project,native)
        cut=document['cuts'][project.settings.get('cut','full')]
        if cut.get('colour','bt709')!='bt709': raise ConfigError('timeline colour contract must be bt709')
        facts=dict(width=timeline['w'],height=timeline['h'],rate=timeline['rate'],frames=timeline['frames'],tc=timeline.get('tc_start'),tc_label=timeline.get('tc_start'),chapters=[[c['title'],c['frame']] for c in timeline['tracks'][5]['items']])
        authored=project.settings.get('scene_rate',[24,1] if project.settings.get('generator_clock')!='env-v1' else facts['rate'])
        if list(authored)!=facts['rate']: raise ConfigError('scene_rate differs from selected cut rate; update generator or use its env-v1 clock contract')
        if project.settings.get('mix'): inputs.append(project.path(project.settings['mix']))
    for item in project.declarations['input']:
        path=project.path(item.get('path',item['name']))
        if not item.get('generated'): inputs.append(path)
    for kind in ('subtitles','chapters','gate'):
        inputs.extend(project.path(item['name']) for item in project.declarations[kind])
    for p in profiles.values():
        if p['text'].get('font'): inputs.append(project.path(p['text']['font']))
        if p['audio'].get('source'): inputs.append(project.path(p['audio']['source']))
        if p['banding'].get('background'): inputs.append(project.path(p['banding']['background']))
        for sample in p['banding'].get('samples',[]):
            for key in ('source','next_source'):
                if sample.get(key): inputs.append(project.path(sample[key]))
    absent=[str(p) for p in inputs if not p.exists()]
    if absent: raise ConfigError('missing inputs:\n'+'\n'.join(absent[:30]))
    # Account for the compressed 4:2:2 segment store plus its muxed intermediate.
    # ProRes varies with content; estimate six bits/pixel/frame and reserve both.
    intermediate_frames=0
    if timeline and any(not p.get('timeline') for p in profiles.values()):
        intermediate_frames=timeline['w']*timeline['h']*timeline['frames']
    plan={}; estimated=intermediate_frames*1.5; budget=Budget(project.resources())
    for name,p in profiles.items():
        parent=plan.get(p.get('from')); base=parent or facts; alternate=None
        if p.get('timeline'):
            path=project.path(p['timeline']); document,root,paths=timeline_inputs(project,path); inputs.extend(paths)
            alternate=resolve_timeline(project,native,path,p.get('cut','full'))
            estimated+=alternate['w']*alternate['h']*alternate['frames']*1.5
            base=dict(width=alternate['w'],height=alternate['h'],rate=alternate['rate'],frames=alternate['frames'],tc_label=alternate.get('tc_start'),chapters=[[c['title'],c['frame']] for c in alternate['tracks'][5]['items']])
            if document['cuts'][p.get('cut','full')].get('colour','bt709')!='bt709': raise ConfigError('timeline colour contract must be bt709')
            if p.get('mix'): inputs.append(project.path(p['mix']))
        if p['audio']['codec']=='copy' and (p.get('start_frame',0) or p['audio'].get('source')): raise ConfigError('audio copy requires a complete source starting at frame zero')
        if p.get('source'): raise ConfigError('use av.project source: and output from: dependencies; per-output source overrides are unsupported')
        if p['video']['codec'] not in caps['codecs']: raise ConfigError('unavailable codec '+p['video']['codec'])
        backend=p['video'].get('backend','auto')
        if backend!='auto' and backend not in caps['backends']: raise ConfigError('unavailable scaler backend '+backend)
        width=p.get('width',base['width']); height=p.get('height',base['height']); fps=p.get('rate',base['rate'])
        if list(fps)!=list(base['rate']): raise ConfigError('output rate must match source/cut; explicit frame-rate conversion is required before this pipeline')
        start=p.get('start_frame',0); frames=p.get('frames',base['frames']-start)
        if type(start)is not int or start<0 or start+frames>base['frames']: raise ConfigError('output frame range is outside source: '+name)
        if width%2 or height%2: raise ConfigError('native output dimensions must be even')
        audio=p['audio']
        if audio['codec']!='none':
            if audio.get('source'):
                audio_probe=native.probe(project.path(audio['source']))
                if not any(s['codec_type']=='audio' for s in audio_probe['streams']): raise ConfigError('external audio source has no audio track: '+name)
            elif not base.get('has_audio',True): raise ConfigError('profile '+name+' requires audio but its source has no audio track; select codec: :none or declare an audio source')
        samples=fractions.Fraction(frames*fps[1]*audio['sample_rate'],fps[0])
        if audio['codec']!='none' and samples.denominator!=1: raise ConfigError('output duration must be an exact number of audio samples: '+name)
        contract=colour_guard(probe,p['colour']) if source and not parent else dict(contract=p['colour'],source='timeline RGB -> BT.709' if timeline else 'parent profile',assumed=[])
        gates=[dict(item,path=str(project.path(item['name']))) for item in project.associated('gate',name)]
        if gates:
            import qc
            result=qc.source_gates(gates)
            if not result['ok']: raise ConfigError('source correctness gate failed for '+name+': '+str(result))
        declarations=project.associated('subtitles',name)
        if sum(i.get('mode')=='timeline' for i in declarations)>1: raise ConfigError('choose one burned subtitle language per output family')
        if declarations:
            import qc
            cues=[cue for item in declarations for cue in qc.captions(project.path(item['name']))]
            duration=frames*fps[1]/fps[0]
            if any(c['end']>duration+.001 for c in cues): raise ConfigError('subtitle cue extends beyond '+name+' duration')
            if p['text']['enabled'] or any(i.get('mode')=='timeline' for i in declarations):
                if not p['text'].get('font'): raise ConfigError('timeline/text captions require an explicit font file')
                report=qc.layout(cues,p['text'],width,height,project.path(p['text']['font']))
                if not report['ok']: raise ConfigError('caption layout/contrast fails for '+name+': '+str(report))
        chapter_list=chapters(project,name,fps,frames)
        if chapter_list is None:
            chapter_list=[]
            for title,frame in base.get('chapters') or []:
                frame-=start
                if frame<=0: chapter_list=[[title,0]]
                elif frame<frames: chapter_list.append([title,frame])
        queue=budget.choose(width,height,base['width'],base['height'])
        encoder_options=dict(p['video'],rate=fps)
        native.call('encoder',str(width),str(height),json.dumps(encoder_options))
        # ProRes is variable rate; conservative uncompressed frame estimate plus audio.
        bits=p['video'].get('bitrate',width*height*int(fps[0]/fps[1])*8 if p['video']['codec'].startswith('prores') else width*height*int(fps[0]/fps[1])*.35)
        size=int(bits*frames*fps[1]/fps[0]/8+float(samples)*audio['channels']*4)
        estimated+=size*3
        timecode=project.settings.get('timecode',base.get('tc_label',base.get('timecode')))
        if timecode is False: timecode=None
        if timecode and start and 'timecode' not in project.settings: timecode=native.call('timecode',timecode,json.dumps(fps),str(start))
        plan[name]=dict(gates=gates,has_audio=audio['codec']!='none',timeline=alternate,timecode=timecode,profile=p,width=width,height=height,rate=fps,frames=frames,start=start,samples=samples.numerator if samples.denominator==1 else None,chapters=chapter_list,colour=contract,resources=queue,estimated_bytes=size)
    absent=[str(p) for p in inputs if not p.exists()]
    if absent: raise ConfigError('missing inputs: '+', '.join(absent[:30]))
    disk=budget.disk(project.workspace,estimated)
    if not disk['ok'] and require_space: raise ConfigError(f"insufficient disk space: {disk['free_bytes']//1024**3} GiB free, estimated {disk['estimated_bytes']//1024**3} GiB plus {disk['reserve_bytes']//1024**2} MiB reserve")
    documents={str(p):sha256(p) for p in inputs if p.is_file() and (p==project.file or p.suffix.lower() in ('.json','.srt','.txt'))}
    return dict(ready=disk['ok'],documents=documents,disk_estimate='includes two ProRes HQ intermediate stores at an estimated 6 bits/pixel/frame; content-dependent',schema=1,project=project.name,root=str(project.root),bitfile=str(project.file),toolchain=str(project.toolchain),capabilities=caps,inputs=sorted(set(map(str,inputs))),source=str(source) if source else None,timeline=timeline,profiles=plan,disk=disk,stages=['prepare','snapshot','render timeline' if timeline else 'decode source','encode profiles','verify exact candidates','audio/text/anomaly/banding QC','activate verified release'])
