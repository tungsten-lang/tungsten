"""Frozen-input jobs and verified, atomic release activation."""
import contextlib
import copy
import dataclasses
import fcntl
import hashlib
import json
import os
import pathlib
import shutil
import time
import uuid
from config import ConfigError
from inputs import Snapshots, implementation, sha256, stamp, write_json
from planner import build, timeline_inputs, resolve_timeline
from resources import Budget, child_peak_rss
import qc


@contextlib.contextmanager
def project_lock(project):
    project.workspace.mkdir(parents=True,exist_ok=True)
    with (project.workspace/'project.lock').open('a') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: raise ValueError('another AV job is using this project') from None
        yield


def options(project,plan,identity):
    p=plan['profile']; video=p['video']; audio=p['audio']; resources=plan['resources']; settings=project.resources()
    opts=dict(width=plan['width'],height=plan['height'],rate=plan['rate'],start=plan['start'],frames=plan['frames'],
              format=p['format'],fit=p.get('fit','stretch'),filter=p.get('filter','lanczos3'),codec=video['codec'],
              scale_backend=video.get('backend','auto'),audio=False if audio['codec']=='none' else ('pcm_'+audio['sample_format'] if audio['codec']=='pcm' else audio['codec']),
              edit_lists=p['edit_lists'],faststart=p.get('faststart',True),decode_ahead=resources['decode_ahead'],segments_ahead=resources['segments_ahead'],
              disk_reserve_bytes=int(settings.get('disk_reserve_mb',1024)*1024**2),timeout_ms=settings.get('native_timeout_ms',30000),retries=settings.get('retries',2),implementation_id=identity,
              resume_dir=str(project.path(project.settings.get('cache','.av/cache'))/p['name']))
    for key in ('bitrate','quality','level','gop','reorder','speed','crop','rect'):
        if key in video: opts[key]=video[key]
    if 'bitrate' in audio: opts['audio_kbps']=audio['bitrate']//1000
    if project.settings.get('timecode') is not None: opts['tc']=project.settings['timecode']
    if plan['chapters'] is not None: opts['chapters']=plan['chapters']
    return opts


def verify(project,native,path,plan,directory,reference=None,timeline=None,subtitle_paths=None):
    from planner import video_stream, colour_guard
    opts=dict(tc_start=plan.get('timecode'),width=plan['width'],height=plan['height'],rate=plan['rate'],frames=plan['frames'],codec=plan['profile']['video']['codec'],audio=plan['profile']['audio']['codec']!='none',edit_lists=plan['profile']['edit_lists'])
    if plan['chapters'] is not None: opts['chapters']=plan['chapters']
    if plan['profile']['video'].get('level'): opts['level']=plan['profile']['video']['level']
    directory=pathlib.Path(directory); directory.mkdir(parents=True,exist_ok=True)
    if plan['profile']['loudness']['enabled']:
        disk=Budget(project.resources()).disk(directory,plan['samples']*plan['profile']['audio']['channels']*4)
        if not disk['ok']: raise ValueError('insufficient disk for bounded-memory decoded audio QC')
    native_result=native.request('verify',path,opts,directory)
    probe=native.probe(path); colour_guard(probe,dict(plan['profile']['colour'],untagged='reject'))
    audios=[s for s in probe['streams'] if s['codec_type']=='audio']; a=plan['profile']['audio']
    if a['codec']=='none': audio_ok=not audios
    elif a['codec']=='copy': audio_ok=len(audios)==1
    else:
        want='aac' if a['codec']=='aac' else 'pcm_'+a['sample_format']
        audio_ok=len(audios)==1 and audios[0]['codec_name']==want and int(audios[0]['sample_rate'])==a['sample_rate'] and audios[0]['channels']==a['channels']
    result=qc.run(project,native,path,plan,directory,reference,timeline,subtitle_paths)
    result.update(ok=native_result['ok'] and audio_ok and result['ok'],native=native_result,audio_contract=audio_ok)
    write_json(directory/'verification.json',result)
    if not result['ok']: raise ValueError('verification/QC failed for '+str(path)+'; see '+str(directory))
    return result


def delivery_context(project,name,path):
    """Pin the recorded reference and resolved timeline behind an activated alias."""
    pinned=pathlib.Path(path).resolve(strict=True); manifest_path=pinned.parent/'manifest.json'
    if not manifest_path.is_file(): return None
    manifest=json.loads(manifest_path.read_text()); job_name=manifest.get('provenance',{}).get('job')
    if not job_name: return None
    job=pathlib.Path(job_name).resolve()
    if not job.is_relative_to((project.workspace/'jobs').resolve()): raise ValueError('release provenance points outside project jobs')
    state=json.loads((job/'job.json').read_text()); output=state['outputs'].get(name)
    if not output: raise ValueError('release has no matching profile provenance')
    item=next((item for item in manifest['files'] if item['name']==pinned.name and item['role']==name),None)
    if not item or item['sha256']!=output['sha256'] or sha256(pinned)!=item['sha256']: raise ValueError('delivery differs from its recorded release')
    mapping={item['source']:item.get('frozen',item['path']) for item in state.get('inputs',[])}
    return dict(project=dataclasses.replace(project,settings=output.get('project_settings',project.settings)),
                reference=output.get('reference'),timeline=output.get('timeline'),subtitles=output.get('subtitle_paths'),mapping=mapping)


def freeze_profile(project,plan,mapping):
    for gate in plan.get('gates',[]): gate['path']=mapping.get(str(project.path(gate['path'])),gate['path'])
    profile=plan['profile']; text=profile['text']
    if text.get('font'): text['font']=mapping.get(str(project.path(text['font'])),text['font'])
    spec=profile['banding']
    if spec and not spec.get('auto'):
        if spec.get('background'): spec['background']=mapping.get(str(project.path(spec['background'])),spec['background'])
        for sample in spec.get('samples',[]):
            for key in ('source','next_source'):
                if sample.get(key): sample[key]=mapping.get(str(project.path(sample[key])),sample[key])


def prepared_audio(project,native,source,plan,options,snapshots,mapping):
    a=plan['profile']['audio']
    if a['codec'] in ('none','copy'): return
    external=a.get('source')
    audio_source=pathlib.Path(mapping.get(str(project.path(external)),str(project.path(external)))) if external else pathlib.Path(source)
    probe=native.probe(audio_source); streams=[s for s in probe['streams'] if s['codec_type']=='audio']
    if not streams: raise ValueError('profile requires audio but source has none; choose audio codec: :none')
    stream=streams[0]
    if not external and int(stream['sample_rate'])==a['sample_rate'] and stream['channels']==a['channels']: return
    key=hashlib.sha256(json.dumps([sha256(audio_source),a['sample_rate'],a['channels']],sort_keys=True).encode()).hexdigest()
    output=project.workspace/'audio'/(key+'.wav'); output.parent.mkdir(parents=True,exist_ok=True)
    if not output.exists():
        part=output.with_suffix('.part.wav')
        native.runner.run(['ffmpeg','-nostdin','-v','error','-y','-i',audio_source,'-map','0:a:0','-ar',a['sample_rate'],'-ac',a['channels'],'-c:a','pcm_s24le',part],capture=True)
        part.replace(output)
    sealed=snapshots.seal(output); options['audio_src']=sealed['path']


def validate_documents(plan,records):
    for record in records:
        expected=plan.get('documents',{}).get(record['source'])
        if expected and expected!=record['sha256']: raise ValueError('plan input changed before it could be frozen: '+record['source'])


def timeline_source(project,native,plan,job,snapshots,identity):
    document,root,paths=timeline_inputs(project)
    paths.append(project.file)
    paths.extend(project.path(i['name']) for i in [*project.declarations['chapters'],*project.declarations['gate']])
    paths.extend(project.path(p['profile']['text']['font']) for p in plan['profiles'].values() if p['profile']['text'].get('font'))
    paths.extend(project.path(p['profile']['audio']['source']) for p in plan['profiles'].values() if p['profile']['audio'].get('source'))
    paths.extend(project.path(i.get('path',i['name'])) for i in project.declarations['input'])
    if project.settings.get('mix'): paths.append(project.path(project.settings['mix']))
    paths.extend(project.path(i['name']) for i in project.declarations['subtitles'])
    records,mapping=snapshots.tree(paths,root,project.workspace/'trees')
    frozen_root=pathlib.Path(next(iter(mapping.values()))).parent
    # Each mapped path is absolute; root is only a base for generator argv/data links.
    frozen_document=json.loads(pathlib.Path(mapping[str(project.path(project.settings['timeline']))]).read_text())
    if (project.path(project.settings['timeline']).parent/frozen_document.get('root','.')).resolve()!=root: raise ValueError('timeline asset root changed while freezing inputs')
    document=copy.deepcopy(frozen_document)
    validate_documents(plan,records)
    tree_root=pathlib.Path(next(iter(mapping.values())))
    while tree_root.parent != project.workspace/'trees': tree_root=tree_root.parent
    document['root']=str(tree_root)
    if project.settings.get('title'): document['title']=project.settings['title']
    for asset in document.get('assets',{}).values():
        original=(root/asset['path']).resolve()
        if original.is_dir():
            # Tree snapshots preserve relative directory layout under one content tree.
            first=next((pathlib.Path(value) for key,value in mapping.items() if pathlib.Path(key).parent==original),None)
            if first is None: raise ValueError('empty frame directory: '+str(original))
            asset['path']=str(first.parent)
        else: asset['path']=mapping[str(original)]
    programs=list(document.get('programs',{}).values())
    for section in [document,*document.get('cuts',{}).values()]:
        programs.extend(shot['program'] for shot in section.get('shots',[]) if shot.get('kind')=='program')
    for program in programs:
        program['source']=mapping[str((root/program['source']).resolve())]
        program['data']=[mapping[str((root/(entry if isinstance(entry,str) else entry['path'])).resolve())] for entry in program.get('data',[])]
    cut=project.settings.get('cut','full'); settings=document['cuts'][cut]
    # High-quality 10-bit 4:2:2 intermediates retain timeline detail before profile encodes.
    settings['encoder']=dict(codec='prores422hq',quality=1)
    subtitles=[i for i in project.associated('subtitles',next(iter(plan['profiles']))) if i.get('mode')=='timeline']
    if subtitles:
        # Studio captions are cue entries anchored at milliseconds.
        document['cuts'][cut]['captions']=[dict(id='bit-caption-'+str(i),text=c['text'],at={'ref':'start'},from_ms=round(c['start']*1000),to_ms=round(c['end']*1000)) for i,c in enumerate(qc.captions(mapping[str(project.path(subtitles[0]['name']))]))]
    if subtitles:
        text=next(iter(plan['profiles'].values()))['profile']['text']
        if not text.get('font'): raise ValueError('timeline subtitles require av.text font: with an explicit font file')
        font_original=str(project.path(text['font']))
        # Fonts are inputs, just as subtitle files and generator sources are.
        font=snapshots.seal(project.path(text['font'])); records.append(font)
        cues=qc.captions(mapping[str(project.path(subtitles[0]['name']))])
        document['burned_captions']=qc.outline_captions(cues,text,settings['w'],settings['h'],font['path'])
    recipe=hashlib.sha256(json.dumps([document,identity,[(r['sha256'],r['source']) for r in records]],sort_keys=True).encode()).hexdigest()
    directory=project.workspace/'timelines'/recipe; directory.mkdir(parents=True,exist_ok=True)
    episode=directory/'episode.json'; write_json(episode,document)
    env=dict(os.environ,TW_RATE_NUM=str(settings['rate'][0]),TW_RATE_DEN=str(settings['rate'][1]),TW_WIDTH=str(settings['w']),TW_HEIGHT=str(settings['h']),STUDIO_TUNGSTEN=str(project.toolchain/'bin/tungsten'),STUDIO_IMPLEMENTATION_ID=identity,STUDIO_ENCODER='videotoolbox')
    def studio(command,*args):
        with (job/'studio.log').open('ab') as log:
            native.runner.run([project.toolchain/'bin/tungsten',project.toolchain/'apps/studio/studio.w','--',command,episode,'--cut',cut,*args],cwd=project.root,env=env,log=log,echo=sys.stderr.buffer)
    studio('resolve'); resolved=json.loads((directory/'build'/cut/'timeline.resolved.json').read_text()); resolved['av_episode']=str(episode)
    primary=next(iter(plan['profiles'].values())); budget=Budget(project.resources()).choose(primary['width'],primary['height'])
    studio('render','--jobs',budget['jobs'],'--animation-jobs',budget['animation_jobs'],'--max-frames',resolved['frames'])
    if project.settings.get('mix'):
        mix=pathlib.Path(mapping[str(project.path(project.settings['mix']))]); target=directory/'build'/cut/'mix.wav'
        if not Budget(project.resources()).disk(target,resolved['samples']*6)['ok']: raise ValueError('insufficient disk for timeline audio preparation')
        native.runner.run(['ffmpeg','-nostdin','-v','error','-y','-i',mix,'-ar','48000','-ac','2','-af','apad,atrim=end_sample='+str(resolved['samples']),'-c:a','pcm_s24le','-rf64','auto',target],capture=True)
    else: studio('mix')
    picture=directory/'picture.mov'
    manifest=directory/'picture.json'
    reusable=picture.is_file() and manifest.is_file() and json.loads(manifest.read_text()).get('sha256')==sha256(picture)
    if not reusable: studio('mux','--out',picture,'--no-edit-lists','--audio-codec','pcm')
    sealed=snapshots.seal(picture)
    write_json(manifest,dict(sha256=sealed['sha256'],frames=resolved['frames'],rate=resolved['rate']))
    return pathlib.Path(sealed['path']),records,mapping,resolved


def render(project,native,names=None,quality_only=False):
    from release import BundlePublisher
    from quality import search
    with project_lock(project):
        # Declared preparation is a real argv stage. Doctor/plan never execute it.
        prepare_env=dict(os.environ)
        if project.settings.get('timeline'):
            authored=json.loads(project.path(project.settings['timeline']).read_text())['cuts'][project.settings.get('cut','full')]
            prepare_env.update(TW_RATE_NUM=str(authored['rate'][0]),TW_RATE_DEN=str(authored['rate'][1]),TW_WIDTH=str(authored['w']),TW_HEIGHT=str(authored['h']))
        for hook in project.declarations['prepare']:
            argv=hook.get('argv')
            if not isinstance(argv,list) or not argv or any(not isinstance(a,str) for a in argv): raise ConfigError('prepare argv: must be a nonempty string array')
            with (project.workspace/'prepare.log').open('ab') as log:
                native.runner.run([sys.executable if a=='{python}' else a for a in argv],cwd=project.path(hook.get('cwd','.')),env=prepare_env,log=log,echo=sys.stderr.buffer)
        plan=build(project,native,names); identity=implementation(project.toolchain,native.package)
        job=project.workspace/'jobs'/(time.strftime('%Y%m%dT%H%M%S')+'-'+uuid.uuid4().hex[:10]); job.mkdir(parents=True)
        state=dict(schema=1,status='running',pid=os.getpid(),started=time.time(),plan=plan,implementation=identity,outputs={})
        write_json(job/'job.json',state); write_json(project.workspace/'latest.json',dict(job=str(job)))
        snapshots=Snapshots(project.workspace/'inputs',native.runner,reserve_bytes=int(project.resources().get('disk_reserve_mb',1024)*1024**2))
        records=[]; mapping={}; timeline=plan['timeline']
        try:
            if plan['source']:
                sealed=snapshots.seal(plan['source']); source=pathlib.Path(sealed['path']); records.append(sealed)
                other=[p for p in plan['inputs'] if p!=plan['source']]
                frozen,mapping=snapshots.tree(other,project.root,project.workspace/'trees'); records.extend(frozen)
            else:
                primary={n:p for n,p in plan['profiles'].items() if not p['profile'].get('timeline')}
                if primary: source,records,mapping,timeline=timeline_source(project,native,dict(plan,profiles=primary),job,snapshots,identity['sha256'])
                else: source=None
            validate_documents(plan,records)
            state['inputs']=records; write_json(job/'job.json',state)
            probe_targets=set(names or [n for n,p in plan['profiles'].items() if p['profile']['video']['codec'] in ('h264','hevc','hevc10')])
            if quality_only and any(plan['profiles'][n]['profile']['video']['codec'].startswith('prores') for n in probe_targets): raise ValueError('quality bitrate probes require H.264 or HEVC profiles')
            entries=[]; sources={}; refs={}; subtitles_by_name={}; contexts={}; timelines={}; mappings={}
            for name,p in plan['profiles'].items():
                native.runner.check_cancelled(); origin=sources.get(p['profile'].get('from'),source)
                context=contexts.get(p['profile'].get('from'),project); current_timeline=timelines.get(p['profile'].get('from'),timeline); current_mapping=mappings.get(p['profile'].get('from'),mapping)
                if p['profile'].get('timeline'):
                    settings=dict(project.settings,timeline=p['profile']['timeline'],cut=p['profile'].get('cut','full')); settings.pop('source',None); settings.pop('mix',None)
                    if p['profile'].get('mix'): settings['mix']=p['profile']['mix']
                    context=dataclasses.replace(project,settings=settings)
                    origin,extra,current_mapping,current_timeline=timeline_source(context,native,dict(plan,profiles={name:p}),job,snapshots,identity['sha256']);records.extend(extra)
                contexts[name]=context; timelines[name]=current_timeline; mappings[name]=current_mapping
                # Re-budget between profiles in case memory pressure changed after timeline rendering.
                p['resources']=Budget(project.resources()).choose(p['width'],p['height'])
                if current_timeline and not p['profile'].get('from') and (list(current_timeline['rate'])!=list(p['rate']) or current_timeline['frames']<p['start']+p['frames']): raise ValueError('resolved timeline clock differs from the plan')
                freeze_profile(project,p,current_mapping)
                opts=options(project,p,identity['sha256']); prepared_audio(project,native,origin,p,opts,snapshots,current_mapping)
                directory=job/name; directory.mkdir(); destination=directory/('output.'+p['profile']['format'])
                if p['profile']['quality'].get('mode')=='search' or (quality_only and name in probe_targets):
                    choice=search(project,native,origin,p,opts,directory/'quality'); opts.pop('quality',None); opts['bitrate']=choice['bitrate']; state.setdefault('quality',{})[name]=choice
                if quality_only and name in probe_targets: continue
                result=native.request('transcode',origin,opts,directory,destination)
                if p['chapters'] is None: p['chapters']=result.get('chapters') or None
                if result.get('tc_start'): p['timecode']=result['tc_start']
                # Freeze each encoded parent before a dependent profile reads it.
                sealed=snapshots.seal(destination); sources[name]=pathlib.Path(sealed['path']); refs[name]=origin
                subtitles=[pathlib.Path(current_mapping.get(str(project.path(i['name'])),str(project.path(i['name'])))) for i in project.associated('subtitles',name)]
                subtitles_by_name[name]=subtitles
                verification=verify(context,native,destination,p,directory/'checks',origin,current_timeline,subtitles)
                state['outputs'][name]=dict(path=str(destination),sha256=sha256(destination),result=result,verification=verification,reference=str(origin),timeline=current_timeline,project_settings=context.settings,subtitle_paths=list(map(str,subtitles)))
                write_json(job/'job.json',state)
                entries.append(dict(source=destination,destination=project.output_path(p['profile']['path']),role=name,plan=p))
                for i,subtitle in enumerate(subtitles):
                    # Sidecars are part of the same activated release as their media.
                    language=project.associated('subtitles',name)[i].get('language')
                    suffix=('.'+language if language else ('.'+str(i) if i else ''))+'.srt'
                    target=project.output_path(p['profile']['path']).with_suffix(suffix)
                    entries.append(dict(source=subtitle,destination=target,role='subtitle',profile=name))
                for chapter in project.associated('chapters',name):
                    file=pathlib.Path(current_mapping.get(str(project.path(chapter['name'])),str(project.path(chapter['name'])))); entries.append(dict(source=file,destination=project.output_path(p['profile']['path']).with_suffix('.chapters'+file.suffix),role='chapters'))
            if not quality_only:
                if implementation(project.toolchain,native.package)['sha256']!=identity['sha256']: raise ValueError('toolchain changed during the job; run again with the new implementation')
                if sha256(project.file)!=project.content_sha256: raise ValueError('Bitfile changed during the job; run again with the new plan')
                def check(path,entry,reports):
                    if entry['role']=='subtitle': qc.captions(path); return dict(ok=True,sha256=sha256(path))
                    if entry['role']=='chapters': return dict(ok=path.stat().st_size>0,sha256=sha256(path))
                    return verify(contexts[entry['role']],native,path,entry['plan'],reports,refs[entry['role']],timelines[entry['role']],subtitles_by_name[entry['role']])
                # A selected subset has its own stable release mapping.
                label=hashlib.sha256(json.dumps(sorted(e['role']+str(e['destination']) for e in entries)).encode()).hexdigest()[:16]
                release=BundlePublisher(project.workspace/'releases'/label,check,native.runner.check_cancelled).publish(entries,dict(job=str(job),implementation=identity['sha256'],inputs=records))
                state['release']=str(release)
            state.update(status='complete',finished=time.time(),child_peak_rss_bytes=child_peak_rss()); write_json(job/'job.json',state)
            return state
        except BaseException as error:
            state.update(status='failed',finished=time.time(),error=str(error),child_peak_rss_bytes=child_peak_rss()); write_json(job/'job.json',state); raise


import sys
