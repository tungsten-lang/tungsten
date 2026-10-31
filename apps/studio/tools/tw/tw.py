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

    def call(self,args,**kw):
        print('+',shlex.join(map(str,args)),flush=True)
        subprocess.run(list(map(str,args)),cwd=self.root,check=True,**kw)

    def compile(self,source,out):
        source=pathlib.Path(source)
        if not source.is_absolute(): source=self.root/source
        out=pathlib.Path(out)
        inputs=[source,self.tw/'bin/tungsten-compiler']
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

    def banding(self,kind):
        specs=self.cfg.get('banding',{}).get(kind,[])
        if not specs: raise ValueError(f'configure banding.{kind} before checking/staging')
        import banding
        if isinstance(specs,dict): specs=[specs]
        for i,spec in enumerate(specs):
            if spec.get('auto'): spec=banding.film_manifest(self.root,spec,short=kind=='short')
            result=banding.run(spec,self.root,self.out/f'banding/{kind}_{i}.json')
            if not result['ok']: raise ValueError(f'{kind} banding thresholds failed; see {self.out}/banding')

    def render(self,stages):
        stages=stages or ['all']
        def has(s): return 'all' in stages or s in stages
        unknown=set(stages)-{'all','anims','import','picture','mix','master','share','verify','banding'}
        if unknown: raise ValueError(f'unknown stages: {sorted(unknown)}')
        if os.environ.get('COLD'):
            for relative in ('studio/build/segments','studio/build/full'):
                shutil.rmtree(self.root/relative,ignore_errors=True)
            (self.root/'studio/build/assets.json').unlink(missing_ok=True)
            (self.root/'render/scenes_bin.key').unlink(missing_ok=True)
            os.environ['TUNGSTEN_INCREMENTAL']='0'
        self.engine()
        if has('anims') or has('import') or has('picture'): self.plates()
        if has('anims'):
            self.hook('before_anims')
            self.call([sys.executable,'tools/tw_anims.py','--jobs',os.environ.get('AJOBS','8'),*(['--force'] if os.environ.get('COLD') else [])])
        if has('import') or has('picture') or has('master'):
            self.call([sys.executable,'tools/studio_import.py',*shlex.split(os.environ.get('IMPORT_OPTS',''))])
            self.call([self.studio,'resolve',self.episode])
        if has('picture'):
            self.call([self.studio,'render',self.episode,'--jobs',os.environ.get('JOBS','8'),
                       '--max-frames',os.environ.get('MAX_FRAMES','1000000'),*shlex.split(os.environ.get('RENDER_OPTS',''))])
        if has('mix') or has('master'):
            self.compile(HERE/'tw_mix.w',self.out/'tw_mix')
            nf=json.loads((self.root/'studio/build/full/timeline.resolved.json').read_text())['frames']
            self.call([self.out/'tw_mix','render/mix.wav','studio/build/full/mix.wav',nf,*shlex.split(os.environ.get('MIX_OPTS',''))])
        if has('master'): self.call([self.studio,'mux',self.episode])
        if has('master') or has('verify'):
            self.call([self.studio,'verify','studio/build/full/master.mp4','--resolved',
                       'studio/build/full/timeline.resolved.json','--mix','studio/build/full/mix.wav'])
        if has('share'):
            self.call([self.studio,'share',self.episode,'--codec',os.environ.get('SHARE_CODEC','hevc10'),
                       '--kbps',os.environ.get('SHARE_KBPS','1800'),'--retries','2'])
        if has('banding'): self.banding('film')

    def plates(self):
        env=dict(os.environ,TW_FILM_ROOT=str(self.root),STUDIO_TW=str(self.tw))
        self.call([sys.executable,HERE/'tw_plates.py'],env=env)

    def short(self):
        self.engine(); self.plates(); self.hook('before_short')
        self.call([sys.executable,'tools/build_short.py','timeline'])
        sources=self.cfg['short_sources']
        # Concatenate only authored sources, preserving the original dispatcher order.
        combined=self.root/'render/short_scenes.w'
        combined.write_text('\n'.join((self.root/p).read_text() for p in sources))
        binary=self.root/'render/short_bin'; self.compile(combined,binary)
        timeline=json.loads((self.root/'short/timeline.json').read_text())
        for beat in timeline['beats']:
            nf=round(beat['dur']*24)
            frames=self.root/'short/frames'/beat['id']; frames.mkdir(parents=True,exist_ok=True)
            key=hashlib.sha256(binary.read_bytes()+json.dumps(beat,sort_keys=True).encode()).hexdigest()
            tag=frames/'.key'
            if not os.environ.get('COLD') and tag.exists() and tag.read_text().strip()==key and all((frames/f'{i:05d}.png').exists() for i in range(nf)): continue
            for old in frames.glob('*.png'): old.unlink()
            tasks=[(first,min(nf-1,first+59)) for first in range(0,nf,60)]
            def render_range(bounds):
                self.call([binary,'scene',self.root,beat['id'],beat['dur'],*bounds])
            with concurrent.futures.ThreadPoolExecutor(max_workers=int(os.environ.get('AJOBS','8'))) as pool:
                list(pool.map(render_range,tasks))
            tag.write_text(key+'\n')
        self.call([sys.executable,'tools/tw_short_import.py'])
        ep=self.cfg.get('short_episode','studio/short.json')
        for stage in ('resolve','render','mix','mux'): self.call([self.studio,stage,ep])
        self.call([self.studio,'verify','studio/build/full/short.master.mp4','--resolved',
                   'studio/build/full/short.timeline.resolved.json','--mix','studio/build/full/short.mix.wav'])
        self.banding('short')

    def thumbs(self):
        thumb=self.root/'render/thumb_bin'; jpeg=self.out/'tw_jpeg'
        self.compile('youtube/thumb.w',thumb); self.compile(HERE/'tw_jpeg.w',jpeg)
        for item in self.cfg.get('thumbnails',[]):
            self.call([thumb,item['kind'],self.root/item['intermediate']])
            self.call([jpeg,self.root/item['intermediate'],self.root/item['output'],*item['size']])

    def publish(self,destination):
        # Run the standing checks immediately before every render publication/staging.
        self.banding('film'); self.banding('short')
        mapping=self.cfg['publish'][destination]
        for src,dst in mapping:
            src=self.root/src; dst=pathlib.Path(dst).expanduser()
            if not dst.is_absolute(): dst=self.root/dst
            if not src.is_file() or src.stat().st_size==0: raise ValueError(f'missing {src}')
            part=dst.with_name(dst.name+'.part'); dst.parent.mkdir(parents=True,exist_ok=True)
            try:
                # macOS APFS clone; ordinary copy is a portable fallback.
                result=subprocess.run(['cp','-c',str(src),str(part)],capture_output=True)
                if result.returncode: shutil.copyfile(src,part)
                import filecmp
                if not filecmp.cmp(src,part,shallow=False): raise ValueError(f'copy verification failed: {dst}')
                part.replace(dst)
            finally:
                part.unlink(missing_ok=True)


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
            with log.open('w') as stream:
                with subprocess.Popen(list(map(str,command)),cwd=t.root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True) as child:
                    for line in child.stdout:
                        stream.write(line); stream.flush(); print(line,end='',flush=True)
                    if child.wait(): raise subprocess.CalledProcessError(child.returncode,command)
            return 0
        if a.command=='render': t.render(a.stages)
        elif a.command=='publish': t.publish(a.stages[0] if a.stages else 'render')
        elif a.command=='banding': t.banding(a.stages[0] if a.stages else 'film')
        else: getattr(t,a.command)()
    except (ValueError,KeyError,OSError,subprocess.CalledProcessError) as e:
        print(f'tw: {e}',file=sys.stderr); return 1
    return 0

if __name__=='__main__': sys.exit(main())
