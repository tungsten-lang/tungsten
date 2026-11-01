#!/usr/bin/env python3
"""Shared film orchestration; per-film settings live in tools/tw.json.

Wrappers export TW_FILM_ROOT; direct use: tw.py --film /path render share.
Commands run as argv (no shell interpolation). Film content generators remain
film sources. Every encode uses the chosen isolated Tungsten worktree.
"""
import concurrent.futures
import argparse
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import time

from process_control import Runner, Cancelled, StageTimeout
from timeline import Timeline, delivery, frame_at, rate
from release import BundlePublisher, sha256

HERE=pathlib.Path(__file__).resolve().parent


class Toolkit:
    def __init__(self,film):
        self.root=pathlib.Path(film).resolve()
        self.cfg=json.loads((self.root/'tools/tw.json').read_text())
        self.tw=pathlib.Path(os.environ.get('STUDIO_TW',self.cfg['tungsten'])).expanduser().resolve()
        if self.tw == pathlib.Path.home()/'tungsten':
            raise ValueError('choose an isolated Tungsten worktree; builds in ~/tungsten are forbidden')
        os.environ['STUDIO_TW']=str(self.tw)
        self.studio=self.tw/'apps/studio/bin/studio'
        self.out=self.root/'render/tungsten'
        self.out.mkdir(parents=True,exist_ok=True)
        self.episode=self.cfg.get('episode','studio/episode.json')
        self.runner=Runner(float(os.environ.get('TW_STAGE_TIMEOUT',self.cfg.get('stage_timeout',3600))))

    def call(self,args,**kw):
        print('+',shlex.join(map(str,args)),flush=True)
        return self.runner.run(list(map(str,args)),cwd=self.root,**kw)

    def compile(self,source,out):
        source=pathlib.Path(source)
        if not source.is_absolute(): source=self.root/source
        out=pathlib.Path(out)
        inputs=[source,self.tw/'bin/tungsten-compiler',self.tw/'runtime/runtime.c']
        # Studio and tools can use core/runtime: include their current state in the key.
        for tree,exts in [('apps/studio',{'.w'}),('core/media',{'.w'}),('runtime/media',{'.c','.m','.h'})]:
            inputs.extend(p for p in (self.tw/tree).rglob('*') if p.suffix in exts)
        key=hashlib.sha256()
        for p in sorted(set(inputs)):
            key.update(str(p).encode()); key.update(p.read_bytes())
        tag=out.with_suffix(out.suffix+'.key')
        digest=key.hexdigest()
        if not os.environ.get('COLD') and out.exists() and tag.exists() and tag.read_text().strip()==digest: return
        out.parent.mkdir(parents=True,exist_ok=True)
        part=out.with_suffix(out.suffix+'.part')
        self.call([self.tw/'bin/tungsten','-o',part,source])
        part.replace(out); tag.write_text(digest+'\n')

    def engine(self):
        self.compile(self.tw/'apps/studio/studio.w',self.studio)

    def hook(self,name):
        for command in self.cfg.get(name,[]):
            self.call([sys.executable if x=='{python}' else x for x in command])

    def project(self,short=False,require_resolved=True):
        return Timeline.load(self.root,self.cfg,short,require_resolved)

    def studio_call(self,stage,project,*options):
        return self.call([self.studio,stage,project.episode,'--cut',project.cut,*options],env=self.clock_env(project,False))

    def master(self,project):
        return project.output('master.'+delivery(self.cfg)['format'])

    def banding(self,kind,movie=None,output=None):
        import banding
        short=kind=='short'
        specs=self.cfg.get('banding',{}).get(kind, self.cfg.get('banding',{}).get('film') if kind=='share' else [])
        if not specs: raise ValueError(f'configure banding.{kind} before checking/staging')
        project=self.project(short)
        if isinstance(specs,dict): specs=[specs]
        results=[]
        for i,spec in enumerate(specs):
            spec=dict(spec)
            if spec.get('auto'): spec=banding.film_manifest(self.root,spec,short,project)
            spec['movie']=str(movie or (project.output('share.'+delivery(self.cfg,'share')['format']) if kind=='share' else self.master(project)))
            result=banding.run(spec,self.root,(output or self.out/'banding')/f'{kind}_{i}.json',self.runner)
            if not result['ok']: raise ValueError(f'{kind} banding thresholds failed')
            results.append(result)
        return results

    def render(self,stages):
        stages=stages or ['all']
        def has(s): return 'all' in stages or s in stages
        unknown=set(stages)-{'all','anims','import','picture','mix','master','share','verify','banding'}
        if unknown: raise ValueError(f'unknown stages: {sorted(unknown)}')
        project=self.project(require_resolved=False)
        settings=delivery(self.cfg)
        if os.environ.get('COLD'):
            shutil.rmtree(project.output('timeline.resolved.json').parent,ignore_errors=True)
            (project.episode.parent/'build/assets.json').unlink(missing_ok=True)
            (self.root/'render/scenes_bin.key').unlink(missing_ok=True)
            os.environ['TUNGSTEN_INCREMENTAL']='0'
        self.engine()
        if has('anims') or has('import') or has('picture'): self.plates()
        if has('anims'):
            self.hook('before_anims')
            self.call([sys.executable,'tools/tw_anims.py','--jobs',os.environ.get('AJOBS','8'),*(['--force'] if os.environ.get('COLD') else [])],env=self.clock_env(project))
        if has('import') or has('picture') or has('master'):
            importer=self.cfg.get('import_command',[sys.executable,'tools/studio_import.py'])
            if importer: self.call([*importer,*shlex.split(os.environ.get('IMPORT_OPTS',''))],env=self.clock_env(project))
            self.studio_call('resolve',project)
        if has('picture'):
            self.studio_call('render',project,'--jobs',os.environ.get('JOBS','8'),
                       '--max-frames',os.environ.get('MAX_FRAMES','1000000'),*shlex.split(os.environ.get('RENDER_OPTS','')))
        if has('mix') or has('master'):
            project=self.project()
            project.samples()  # reject fractional sample lengths before writing
            self.compile(HERE/'tw_mix.w',self.out/'tw_mix')
            self.call([self.out/'tw_mix',self.cfg.get('mix_source','render/mix.wav'),project.output('mix.wav'),project.frames,
                       '--rate',f'{project.rate[0]}/{project.rate[1]}',*shlex.split(os.environ.get('MIX_OPTS',''))])
        if has('master'):
            self.studio_call('mux',project,'--out',self.master(project),*self.mux_flags(settings))
        if has('master') or has('verify'):
            project=self.project()
            self.call([self.studio,'verify',self.master(project),'--resolved',project.resolved_path,
                       '--mix',project.output('mix.wav'),*(['--no-edit-lists'] if settings.get('edit_lists') is False else [])])
        if has('share'):
            project=self.project(); share=delivery(self.cfg,'share')
            flags=['--master',self.master(project),'--out',project.output('share.'+share['format']),
                   '--codec',os.environ.get('SHARE_CODEC',share.get('codec','hevc10')),
                   '--kbps',os.environ.get('SHARE_KBPS',str(share.get('kbps',1800))),
                   '--retries','2','--resume',self.out/'resume','--timeout-ms',str(self.cfg.get('native_timeout_ms',30000)),
                   *self.mux_flags(share)]
            for key in ('width','height'):
                if key in share: flags += ['--'+key,str(share[key])]
            self.studio_call('share',project,*flags)
        if has('banding'):
            self.banding('film')
            if project.output('share.'+delivery(self.cfg,'share')['format']).exists(): self.banding('share')

    def clock_env(self,project,check_generator=True):
        # Film generators can declare their supported clock until converted to this env contract.
        authored=self.cfg.get('scene_rate', [24,1] if self.cfg.get('generator_clock')!='env-v1' else None)
        if check_generator and authored and rate(authored)!=project.rate:
            raise ValueError('authored scene_rate differs from the selected cut; update the scene generator')
        return dict(os.environ,TW_RATE_NUM=str(project.rate[0]),TW_RATE_DEN=str(project.rate[1]),
                    TW_WIDTH=str(project.width),TW_HEIGHT=str(project.height))

    @staticmethod
    def mux_flags(settings):
        return (['--no-edit-lists'] if settings.get('edit_lists') is False else []) + (
                ['--audio-codec',settings['audio_codec']] if settings.get('audio_codec') else [])

    def plates(self):
        if self.cfg.get('auto_plates') is False: return
        env=dict(os.environ,TW_FILM_ROOT=str(self.root),STUDIO_TW=str(self.tw))
        self.call([sys.executable,HERE/'tw_plates.py'],env=env)

    def short(self):
        project=self.project(True,False)
        self.engine(); self.plates(); self.hook('before_short')
        self.call([sys.executable,'tools/build_short.py','timeline'],env=self.clock_env(project))
        sources=self.cfg['short_sources']
        # Concatenate only authored sources, preserving the original dispatcher order.
        combined=self.root/'render/short_scenes.w'
        combined.write_text('\n'.join((self.root/p).read_text() for p in sources))
        binary=self.root/'render/short_bin'; self.compile(combined,binary)
        timeline=json.loads((self.root/'short/timeline.json').read_text())
        for beat in timeline['beats']:
            nf=frame_at(beat['dur'],project.rate)
            frames=self.root/'short/frames'/beat['id']; frames.mkdir(parents=True,exist_ok=True)
            key=hashlib.sha256(binary.read_bytes()+json.dumps([beat,project.rate,project.width,project.height],sort_keys=True).encode()).hexdigest()
            tag=frames/'.key'
            if not os.environ.get('COLD') and tag.exists() and tag.read_text().strip()==key and all((frames/f'{i:05d}.png').exists() for i in range(nf)): continue
            for old in frames.glob('*.png'): old.unlink()
            tasks=[(first,min(nf-1,first+59)) for first in range(0,nf,60)]
            def render_range(bounds):
                self.call([binary,'scene',self.root,beat['id'],beat['dur'],*bounds],env=self.clock_env(project))
            with concurrent.futures.ThreadPoolExecutor(max_workers=int(os.environ.get('AJOBS','8'))) as pool:
                list(pool.map(render_range,tasks))
            tag.write_text(key+'\n')
        self.call([sys.executable,'tools/tw_short_import.py'],env=self.clock_env(project))
        for stage in ('resolve','render','mix'):
            if stage=='mix':
                project=self.project(True)
                project.samples()
            self.studio_call(stage,project)
        self.studio_call('mux',project,'--out',self.master(project),*self.mux_flags(delivery(self.cfg)))
        project=self.project(True)
        self.call([self.studio,'verify',self.master(project),'--resolved',project.resolved_path,'--mix',project.output('mix.wav')])
        self.banding('short')

    def thumbs(self):
        thumb=self.root/'render/thumb_bin'; jpeg=self.out/'tw_jpeg'
        self.compile('youtube/thumb.w',thumb); self.compile(HERE/'tw_jpeg.w',jpeg)
        for item in self.cfg.get('thumbnails',[]):
            self.call([thumb,item['kind'],self.root/item['intermediate']])
            self.call([jpeg,self.root/item['intermediate'],self.root/item['output'],*item['size']])

    def verify_candidate(self,path,entry,reports):
        role=entry['role']
        if role not in ('film','short','share'): raise ValueError(f'unknown release role: {role}')
        project=self.project(role=='short')
        chapters=reports/'chapters.frames.txt'
        marks=project.resolved['tracks'][5]['items']
        chapters.write_text(''.join(f'{m["frame"]} {m["title"]}\n' for m in marks))
        flags=['--rate',f'{project.rate[0]}/{project.rate[1]}','--frames',project.frames,
               '--tc',project.timecode,'--json']
        if marks: flags += ['--chapters',chapters]
        settings=delivery(self.cfg,'share' if role=='share' else 'master')
        if settings.get('edit_lists') is False: flags += ['--no-edit-lists']
        result=self.call([self.tw/'bin/tungsten','media','verify',path,*flags],capture=True)
        native=json.loads(result.stdout)
        (reports/'native.json').write_bytes(result.stdout)
        if not native.get('ok'): raise ValueError('native delivery contract failed')
        probe=json.loads(self.call(['ffprobe','-v','error','-select_streams','v:0','-show_streams','-show_format','-of','json',path],capture=True).stdout)
        facts=probe['streams'][0]
        brand=probe['format'].get('tags',{}).get('major_brand','').strip()
        if (brand=='qt') != (settings['format']=='mov'):
            raise ValueError('release container differs from delivery contract')
        facts['container_brand']=brand
        width,height=(settings.get('width',1280 if role=='share' else project.width),settings.get('height',720 if role=='share' else project.height))
        if (facts['width'],facts['height'])!=(width,height): raise ValueError('release geometry differs from delivery contract')
        encoder=project.config.get('encoder',{})
        default_codec='h264' if (os.environ.get('STUDIO_ENCODER') or encoder.get('backend'))=='ffmpeg' else encoder.get('codec','hevc')
        codec=(os.environ.get('SHARE_CODEC',settings.get('codec','hevc10')) if role=='share'
               else settings.get('codec',default_codec))
        want={'hevc10':'hevc','prores422':'prores','prores422hq':'prores','prores422lt':'prores','prores422proxy':'prores'}.get(codec,codec)
        if want and facts['codec_name']!=want: raise ValueError('release codec differs from delivery contract')
        if codec=='hevc10' and (facts.get('profile')!='Main 10' or '10' not in facts.get('pix_fmt','')):
            raise ValueError('release lost Main10 precision')
        if codec=='h264' and (facts.get('profile')!='High' or facts.get('pix_fmt')!='yuv420p'):
            raise ValueError('release H.264 profile or precision differs from delivery contract')
        profiles={'prores422':'Standard','prores422hq':'HQ','prores422lt':'LT','prores422proxy':'Proxy'}
        if codec in profiles and (facts.get('profile')!=profiles[codec] or facts.get('pix_fmt')!='yuv422p10le'):
            raise ValueError('release ProRes profile or precision differs from delivery contract')
        if codec=='hevc' and (facts.get('profile')!='Main' or facts.get('pix_fmt')!='yuv420p'):
            raise ValueError('release HEVC Main8 profile differs from delivery contract')
        (reports/'video.json').write_text(json.dumps(facts,indent=2)+'\n')
        qc=self.banding(role,path,reports)
        return dict(ok=True,media='native.json',video='video.json',qc=[r['sha256'] for r in qc])

    def provenance(self):
        paths=[self.root/'tools/tw.json',self.tw/'bin/tungsten-compiler',self.tw/'bin/tungsten',self.tw/'runtime/runtime.c']
        for short in (False,True):
            project=self.project(short)
            paths += [project.episode,project.resolved_path]
        for tree in ('apps/studio','runtime/media','core/media'):
            paths += [p for p in (self.tw/tree).rglob('*') if p.suffix in ('.py','.w','.c','.m','.h')]
        result={str(p):sha256(p) for p in sorted(set(paths))}
        result['environment']={key:os.environ.get(key) for key in ('SHARE_CODEC','SHARE_KBPS','STUDIO_ENCODER','STUDIO_VT_SESSION','STUDIO_TW')}
        return result

    def publish(self,destination):
        entries=[]
        for pair in self.cfg['publish'][destination]:
            if isinstance(pair,dict):
                src,dst,role=pair['source'],pair['destination'],pair['role']
            else:
                src,dst=pair
                role='short' if 'short' in pathlib.Path(src).stem.lower() else ('share' if 'share' in pathlib.Path(src).stem.lower() else 'film')
            dst=pathlib.Path(dst).expanduser()
            entries.append(dict(source=self.root/src,destination=dst if dst.is_absolute() else self.root/dst,role=role))
        common=pathlib.Path(os.path.commonpath([str(e['destination'].parent) for e in entries]))
        directory=self.cfg.get('release_dirs',{}).get(destination,common/'.tw-releases'/self.root.name/destination)
        directory=pathlib.Path(directory).expanduser()
        if not directory.is_absolute(): directory=self.root/directory
        before=self.provenance()
        def verify(path,entry,reports):
            result=self.verify_candidate(path,entry,reports)
            if self.provenance()!=before: raise ValueError('configuration, timeline or tools changed during verification')
            return result
        release=BundlePublisher(directory,verify,self.runner.check_cancelled).publish(entries,before)
        print(f'published release: {release}',flush=True)
        return release


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--film',default=os.environ.get('TW_FILM_ROOT',os.getcwd()))
    p.add_argument('command',choices=['render','short','thumbs','plates','publish','banding','config'])
    p.add_argument('stages',nargs='*')
    a=p.parse_args()
    try:
        t=Toolkit(a.film)
        if a.command=='config':
            print(json.dumps(t.cfg,indent=2)); return 0
        # Keep the film lock across the whole command; heavy.sh retains the
        # machine's heavy-slot, caffeinate and guard behavior of existing films.
        if not os.environ.get('TW_IN_SLOT') and (t.root/'tools/heavy.sh').exists():
            guard=pathlib.Path.home()/'math/openai/tools/guard.sh'
            env=dict(os.environ,TW_IN_SLOT='1')
            log=t.out/(a.command+'_'+time.strftime('%Y%m%d_%H%M%S')+'.log')
            command=[t.root/'tools/heavy.sh',guard,os.environ.get('GUARD_MB','16384'),
                     os.environ.get('GUARD_S','14400'),sys.executable,HERE/'tw.py','--film',t.root,a.command,*a.stages]
            with t.runner.signals(), log.open('wb') as stream:
                t.call(command,env=env,log=stream)
            return 0
        with t.runner.signals():
            if a.command=='render': t.render(a.stages)
            elif a.command=='publish': t.publish(a.stages[0] if a.stages else 'render')
            elif a.command=='banding': t.banding(a.stages[0] if a.stages else 'film')
            else: getattr(t,a.command)()
    except (ValueError,KeyError,OSError,subprocess.CalledProcessError,Cancelled,StageTimeout) as e:
        print(f'tw: {e}',file=sys.stderr); return 1
    return 0

if __name__=='__main__': sys.exit(main())
