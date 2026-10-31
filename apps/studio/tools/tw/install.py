#!/usr/bin/env python3
"""Install this toolkit and migrate common film automation, with reversible backups.

Only the supported traditional tw_* layout is accepted. Film content generators
and compositors remain authored sources; shared orchestration/settings are moved.
Default is a dry run. --apply creates ~/videos/tools/tw and migrates named films.
"""
import argparse
import datetime
import json
import pathlib
import re
import shutil

HERE=pathlib.Path(__file__).resolve().parent


def config_for(root,tungsten):
    root=pathlib.Path(root).resolve()
    render=(root/'tools/tw_render.sh').read_text()
    if 'videos/tools/tw/tw.py' in render and (root/'tools/tw.json').exists():
        cfg=json.loads((root/'tools/tw.json').read_text())
        cfg['tungsten']=str(pathlib.Path(tungsten).expanduser().resolve())
        return cfg
    short=(root/'tools/tw_short.sh').read_text()
    publish=(root/'tools/tw_publish.sh').read_text()
    scene=re.search(r'^cat (.+) > render/short_scenes.w$',short,re.M)
    name=re.search(r'put \$B/master.mp4 render/(.+)\.mp4',publish)
    if not scene or not name: raise ValueError(f'{root}: unsupported short/publish layout; leave originals intact')
    checks=[]
    for line in render.splitlines():
        if ('python3 tools/' in line or 'tools/venv/bin/python -I tools/' in line) and 't=$(now)' not in line and 'tw_plates' not in line:
            for python,script in re.findall(r'(python3|tools/venv/bin/python -I) (tools/[a-z_]+\.py)',line):
                checks.append(['tools/venv/bin/python','-I',script] if python != 'python3' else ['{python}',script])
    stem=name.group(1)
    cfg=dict(tungsten=str(pathlib.Path(tungsten).expanduser().resolve()),before_anims=checks,
             short_sources=scene.group(1).split(),banding={'film':{'auto':True},'short':{'auto':True}},
             thumbnails=[dict(kind=k,intermediate='youtube/'+src,output='youtube/'+dst,size=size) for k,src,dst,size in
             [('n','thumb_2x.png','thumb.jpg',[1280,720]),('a','alt_2x.png','thumb_alt.jpg',[1280,720]),('v','cover_2x.png','cover.jpg',[1080,1920])]],
             publish={'render':[[f'studio/build/full/{src}',f'render/{dst}'] for src,dst in
                 [('master.mp4',stem+'.mp4'),('share.mp4',stem+'_share.mp4'),('short.master.mp4',stem+'_short.mp4')]],
                 'stage':[[f'render/{stem}{s}.mp4',f'~/math/openai/videos-to-upload/{stem}{s}.youtube.mp4'] for s in ('','_short')]})
    anim=(root/'tools/tw_anims.py').read_text()
    if 'def checks_gate():' in anim:
        cfg['gates']=[dict(file='data/checks_output.txt',pattern=r'^checks: (\d+)\s+failures=(0)$'),
                      dict(file='data/checks_output.txt',pattern=r'^controls: (\d+)\s+failed as expected: (\d+)$',equal=[1,2]),
                      dict(file='data/satori_raw.txt',pattern='egypt_identities.sat: OK')]
    return cfg


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('films',nargs='+',type=pathlib.Path)
    p.add_argument('--tungsten',type=pathlib.Path,default=HERE.parents[3])
    p.add_argument('--videos',type=pathlib.Path,default=pathlib.Path.home()/'videos')
    p.add_argument('--apply',action='store_true')
    a=p.parse_args()
    plans=[(f.resolve(),config_for(f,a.tungsten)) for f in a.films]
    for f,cfg in plans: print(json.dumps(dict(film=str(f),config=cfg),indent=2))
    if not a.apply: return
    install=a.videos/'tools/tw'
    if install.exists() and install.resolve()!=HERE:
        raise ValueError(f'{install} already exists; refusing to replace a different toolkit')
    install.parent.mkdir(parents=True,exist_ok=True)
    if not install.exists(): install.symlink_to(HERE,target_is_directory=True)
    stamp=datetime.datetime.now().strftime('%Y%m%dT%H%M%S%f')
    backup=a.videos/'tools/tw-migration-backups'/stamp
    for root,cfg in plans:
        saved=backup/root.relative_to(a.videos)
        saved.mkdir(parents=True,exist_ok=True)
        files=['tw_render.sh','tw_short.sh','tw_thumbs.sh','tw_publish.sh','tw_plates.py','tw_bg.w','tw_mix.w','tw_jpeg.w','tw_anims.py']
        if (root/'tools/glyphs.py').exists(): files.append('glyphs.py')
        # Save every replaced byte before touching any film.
        for name in [*files,'tw.json']:
            old=root/'tools'/name
            if old.exists(): shutil.copy2(old,saved/name)
        (root/'tools/tw.json').write_text(json.dumps(cfg,indent=2)+'\n')
        for name in files:
            dst=root/'tools'/name
            dst.unlink(missing_ok=True)
            if name.endswith('.sh'):
                cmd={'tw_render.sh':'render','tw_short.sh':'short','tw_thumbs.sh':'thumbs','tw_publish.sh':'publish'}[name]
                dst.write_text('#!/bin/sh\nset -eu\nTW_FILM_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)\nexport TW_FILM_ROOT\nexec "${TW_PYTHON:-python3}" "$HOME/videos/tools/tw/tw.py" '+cmd+' "$@"\n')
                dst.chmod(0o755)
            elif name=='tw_anims.py':
                dst.write_text('#!/usr/bin/env python3\nimport os, pathlib, runpy\nos.environ.setdefault("TW_FILM_ROOT", str(pathlib.Path(__file__).absolute().parent.parent))\nrunpy.run_path(str(pathlib.Path.home()/"videos/tools/tw/tw_anims.py"), run_name="__main__")\n')
            elif name=='tw_mix.w':
                # Tungsten resolves use relative to the caller's symlink path.
                # A use wrapper keeps nested imports relative to the shared source.
                dst.write_text('use "'+str(HERE/'tw_mix')+'"\n')
            else: dst.symlink_to(install/name)
    print('Backups:',backup)

if __name__=='__main__': main()
