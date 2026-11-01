#!/usr/bin/env python3
"""bit av: declarative project plans and verified native AV delivery."""
import argparse
import fcntl
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

PACKAGE=pathlib.Path(__file__).resolve().parents[2]
ROOT=pathlib.Path(os.environ.get('TUNGSTEN_ROOT',PACKAGE.parents[1])).resolve()
sys.path.insert(0,str(ROOT/'apps/studio/tools/tw'))
from config import Project, ConfigError
from process_control import Runner, Cancelled, StageTimeout
from native import Native
from inputs import write_json, sha256
from pipeline import render, verify, project_lock, delivery_context, freeze_profile
from planner import build

FILES=[('CLI and project configuration','bits/tungsten-av/lib/av/cli.py'),('Bitfile schema','bits/tungsten-av/lib/av/config.py'),('Preflight and plans','bits/tungsten-av/lib/av/planner.py'),('Jobs and delivery','bits/tungsten-av/lib/av/pipeline.py'),('Audio, text and anomaly QC','bits/tungsten-av/lib/av/qc.py'),('Bitrate probes','bits/tungsten-av/lib/av/quality.py'),('Snapshots and implementation identity','bits/tungsten-av/lib/av/inputs.py'),('Timeline engine','apps/studio/studio.w'),('Timeline source and cache','apps/studio/lib/project.w'),('Timeline mux','apps/studio/lib/mux.w'),('Transcode API','core/media/transcode.w'),('Scaler API','core/media/scaler.w'),('Media verification','core/media/verify.w'),('Native AV implementation','runtime/media/media_avf.m'),('Segment format and portable media','runtime/media/media.c'),('Banding QC','apps/studio/tools/tw/banding.py'),('Atomic releases','apps/studio/tools/tw/release.py'),('Package subcommand dispatcher','bits/tungsten-bit/lib/package_commands.w')]


def emit(value,args):
    if args.json: print(json.dumps(value,indent=2,allow_nan=False)); return
    if args.command=='plan':
        print(f"{value['project']} — {value['toolchain']}")
        for name,p in value['profiles'].items():
            profile=p['profile']; print(f"  {name}: {p['width']}×{p['height']} {p['rate'][0]}/{p['rate'][1]} fps, {p['frames']} frames → {profile['path']}")
            print(f"    {profile['video']['codec']} {profile['video']['depth']}-bit {profile['video']['chroma']}, audio {profile['audio']['codec']} {profile['audio']['sample_rate']} Hz / {profile['audio']['channels']} ch; jobs {p['resources']['jobs']}, decoder queue {p['resources']['decode_ahead']}")
        print('  '+' → '.join(value['stages']))
        if not value['ready']: print('  BLOCKED: insufficient disk space for the estimated job and reserve')
        print(f"  disk: {value['disk']['free_bytes']//1024**3} GiB free, estimated working space {value['disk']['estimated_bytes']//1024**2} MiB plus reserve")
    else: print(json.dumps(value,indent=2,allow_nan=False))


def init(args):
    directory=pathlib.Path(args.project).expanduser().resolve(); directory.mkdir(parents=True,exist_ok=True); path=directory/'Bitfile'
    content=path.read_text() if path.exists() else f'name {json.dumps(directory.name)}\nversion "0.1.0"\n'
    if any(line.strip().startswith('av.') for line in content.splitlines()): raise ConfigError('Bitfile already defines an AV project')
    source=args.source; timeline=args.timeline
    if not source and not timeline:
        if (directory/'studio/episode.json').exists(): timeline='studio/episode.json'
        else: raise ConfigError('init requires --source movie.mov or --timeline studio/episode.json')
    if source and timeline: raise ConfigError('choose --source or --timeline')
    declaration='timeline' if timeline else 'source'; value=timeline or source
    name=directory.name.lower().replace(' ','-')
    import re
    name=re.sub('[^a-z0-9_-]','-',name)
    if not name or not name[0].isalpha(): name='film-'+name
    extra=f'\nav.project {json.dumps(name)}, {declaration}: {json.dumps(value)}, toolchain: {json.dumps(str(ROOT))}\n'
    extra+='av.output "master", path: "render/master.mov", format: :mov\nav.video "master", codec: :hevc10, quality: 0.85\nav.audio "master", codec: :pcm, sample_format: :s24le, sample_rate: 48000, channels: 2\n'
    extra+='av.output "share", from: "master", path: "render/share.mp4", format: :mp4\nav.video "share", codec: :hevc10, bitrate: "1800k"\nav.audio "share", codec: :aac, bitrate: "192k"\nav.colour "all", primaries: :bt709, transfer: :bt709, matrix: :bt709, range: :limited, untagged: :reject\n'
    extra+='av.resources memory_mb: 4096, jobs: 4, animation_jobs: 4, decode_ahead: 6, segments_ahead: 3, disk_reserve_mb: 1024\n# Add explicit font, subtitles, chapters and QC gates; see bit av files.\n'
    if path.exists(): shutil.copy2(path,path.with_name('Bitfile.before-av-'+str(time.time_ns())))
    temporary=path.with_name('.Bitfile.av-'+str(os.getpid())); temporary.write_text(content.rstrip()+'\n'+extra)
    # Validate before replacing the project manifest.
    probe=directory/('.av-init-'+str(os.getpid())); probe.mkdir()
    try:
        (probe/'Bitfile').write_text(temporary.read_text()); Project.load(probe)
    finally: shutil.rmtree(probe); temporary.unlink(missing_ok=True)
    path.write_text(content.rstrip()+'\n'+extra)
    return dict(ok=True,bitfile=str(path))


def job_state(project):
    latest=project.workspace/'latest.json'
    if not latest.exists(): return dict(status='no jobs',workspace=str(project.workspace))
    job=pathlib.Path(json.loads(latest.read_text())['job']); state=json.loads((job/'job.json').read_text())
    if state['status']=='running':
        with (project.workspace/'project.lock').open('r') as lock:
            try:
                fcntl.flock(lock,fcntl.LOCK_SH|fcntl.LOCK_NB); state['status']='interrupted'
            except BlockingIOError: pass
    return dict(job=str(job),status=state['status'],started=state.get('started'),finished=state.get('finished'),release=state.get('release'),error=state.get('error'),outputs=list(state['outputs']),child_peak_rss_bytes=state.get('child_peak_rss_bytes'))


def collect(project,apply=False):
    # A project lock excludes writers. Only stale temporary candidates and failed jobs
    # are eligible; retained releases, snapshots and completed jobs remain untouched.
    with project_lock(project):
        before=time.time()-project.resources().get('cache_days',30)*86400; paths=[]
        latest=project.workspace/'latest.json'; keep=json.loads(latest.read_text())['job'] if latest.exists() else None
        retained=set()
        for manifest in (project.workspace/'releases').glob('*/*/manifest.json'):
            try: job=json.loads(manifest.read_text()).get('provenance',{}).get('job')
            except (OSError,ValueError): continue
            if job: retained.add(str(pathlib.Path(job).resolve()))
        for p in (project.workspace/'jobs').glob('*'):
            file=p/'job.json'
            if str(p)==keep or str(p.resolve()) in retained or not file.exists() or p.stat().st_mtime>=before: continue
            state=json.loads(file.read_text())
            if state['status']!='complete':
                try: os.kill(state.get('pid',0),0); alive=True
                except ProcessLookupError: alive=False
                if not alive: paths.append(p)
        for p in (project.workspace/'releases').glob('*/.candidate-*'):
            if p.stat().st_mtime<before: paths.append(p)
        for p in paths:
            if not p.resolve().is_relative_to(project.workspace.resolve()): raise ValueError('refusing GC outside the workspace')
        result=dict(apply=apply,paths=list(map(str,paths)))
        if apply:
            for p in paths: shutil.rmtree(p)
        return result


def publish(project,native,args):
    with project_lock(project): return publish_locked(project,native,args)


def publish_locked(project,native,args):
    from release import BundlePublisher
    declarations=[i for i in project.declarations['publish'] if i['name']==args.target]
    if not declarations: raise ConfigError('define av.publish '+json.dumps(args.target)+', root: ..., profiles: [...] in the Bitfile')
    declaration=declarations[0]; plans=build(project,native,args.profiles,require_space=False)['profiles']; chosen=declaration.get('profiles',list(plans)); root=project.path(declaration['root'])
    entries=[]
    if declaration.get('layout','flat') not in ('flat','profiles'): raise ConfigError('publish layout must be flat or profiles')
    for name in chosen:
        if name not in plans: raise ConfigError('unknown publish profile: '+name)
        p=plans[name]; source=project.output_path(p['profile']['path']); destination=root/(name if declaration.get('layout')=='profiles' else '')/source.name
        context=delivery_context(project,name,source)
        if context: freeze_profile(project,p,context['mapping'])
        entries.append(dict(source=source,destination=destination,role=name,plan=p,context=context))
        suffixes=['.'+item['language']+'.srt' if item.get('language') else '.srt' for item in project.associated('subtitles',name)]
        for suffix in suffixes:
            sidecar=source.with_suffix(suffix)
            if sidecar.exists(): entries.append(dict(source=sidecar,destination=destination.with_suffix(suffix),role='subtitle'))
    for file in declaration.get('files',[]):
        source=project.path(file); entries.append(dict(source=source,destination=root/source.name,role='file'))
    def check(path,entry,reports):
        if entry['role']=='subtitle':
            import qc
            qc.captions(path); return dict(ok=True,sha256=sha256(path))
        if entry['role']=='file': return dict(ok=path.stat().st_size>0,sha256=sha256(path))
        reference=project.path(project.settings['source']) if project.settings.get('source') else None
        context=entry.get('context')
        if context: return verify(context['project'],native,path,entry['plan'],reports,context['reference'],context['timeline'],context['subtitles'])
        return verify(project,native,path,entry['plan'],reports,reference)
    release=BundlePublisher(project.path(declaration.get('release_dir',str(root/'.av-releases'))),check,native.runner.check_cancelled).publish(entries,dict(project=project.name,bitfile_sha256=sha256(project.file)))
    return dict(ok=True,release=str(release))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['doctor','plan','render','init','files','status','verify','qc','share','short','publish','stage','gc','quality'])
    parser.add_argument('--project',default='.',help='project directory or Bitfile (nearest parent by default)')
    parser.add_argument('--profile',dest='profiles',action='append',help='select an output profile; dependencies are included')
    parser.add_argument('--json',action='store_true',help='machine-readable output')
    parser.add_argument('--source',help='init: source movie path'); parser.add_argument('--timeline',help='init: authored timeline path')
    parser.add_argument('--target',default='upload',help='publish/stage: named av.publish destination')
    parser.add_argument('--apply',action='store_true',help='gc: remove listed stale temporary artifacts; default is a preview')
    args=parser.parse_args(argv)
    if (args.source or args.timeline) and args.command!='init': parser.error('--source/--timeline belong to init; configure render sources in the Bitfile')
    if args.apply and args.command!='gc': parser.error('--apply belongs to gc')
    try:
        if args.command=='files':
            if args.json: emit([dict(purpose=a,path=str(ROOT/b)) for a,b in FILES],args)
            else:
                for purpose,path in FILES: print(f'{purpose}:\n  {ROOT/path}')
            return 0
        if args.command=='init': emit(init(args),args); return 0
        project=Project.load(args.project)
        if project.toolchain==pathlib.Path.home()/'tungsten': raise ConfigError('select an isolated toolchain; builds in ~/tungsten are forbidden')
        sys.path.insert(0,str(project.toolchain/'apps/studio/tools/tw'))
        if args.command=='status': emit(job_state(project),args); return 0
        if args.command=='gc': emit(collect(project,args.apply),args); return 0
        runner=Runner(project.resources().get('timeout',3600)); native=Native(project.toolchain,PACKAGE,runner)
        with runner.signals():
            if args.command in ('doctor','plan'):
                plan=build(project,native,args.profiles,require_space=False)
                if args.command=='doctor':
                    tools={name:shutil.which(name) for name in ('ffmpeg','ffprobe')}
                    versions={tool:runner.run([tool,'-version'],capture=True).stdout.decode().splitlines()[0] for tool in tools}
                    result=dict(tool_versions=versions,encoder_sessions='selected codec, size and rate opened and closed without writing media',ok=plan['disk']['ok'],project=project.name,bitfile=str(project.file),toolchain=str(project.toolchain),capabilities=plan['capabilities'],tools=tools,inputs=len(plan['inputs']),profiles=list(plan['profiles']),disk=plan['disk'])
                    for mod in ('numpy','PIL','fontTools','uharfbuzz'):
                        import importlib.util
                        result.setdefault('python',{})[mod]=importlib.util.find_spec(mod) is not None
                    emit(result,args)
                else: emit(plan,args)
            elif args.command in ('render','share','short','quality'):
                profiles=args.profiles or ([args.command] if args.command in ('share','short') else None)
                state=render(project,native,profiles,args.command=='quality'); emit(dict(ok=True,status=state['status'],release=state.get('release'),outputs=state['outputs'],quality=state.get('quality'),child_peak_rss_bytes=state['child_peak_rss_bytes']),args)
            elif args.command in ('publish','stage'): emit(publish(project,native,args),args)
            elif args.command in ('verify','qc'):
                plan=build(project,native,args.profiles,require_space=False); results={}
                with project_lock(project):
                    for name,p in plan['profiles'].items():
                        reference=project.output_path(project.profiles()[p['profile']['from']]['path']) if p['profile'].get('from') else (project.path(plan['source']) if plan['source'] else None)
                        context=delivery_context(project,name,project.output_path(p['profile']['path']))
                        if context:
                            freeze_profile(project,p,context['mapping'])
                            results[name]=verify(context['project'],native,project.output_path(p['profile']['path']),p,project.workspace/'checks'/name,context['reference'],context['timeline'],context['subtitles'])
                        else: results[name]=verify(project,native,project.output_path(p['profile']['path']),p,project.workspace/'checks'/name,reference,p.get('timeline') or plan['timeline'])
                emit(dict(ok=True,profiles=results),args)
        return 1 if args.command=='doctor' and not plan['disk']['ok'] else 0
    except (ConfigError,ValueError,OSError,RuntimeError,subprocess.CalledProcessError,TimeoutError) as error:
        message=str(error)
        if isinstance(error,subprocess.CalledProcessError): message+='\n'+((error.stderr or b'')+(error.stdout or b'')).decode(errors='replace')[-4000:]
        if args.json: print(json.dumps(dict(ok=False,error=message)))
        else: print('bit av: '+message,file=sys.stderr)
        return 1


if __name__=='__main__': raise SystemExit(main())
