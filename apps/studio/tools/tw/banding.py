#!/usr/bin/env python3
"""Measure smooth-background error in films and Shorts. No pass without usable samples.

A JSON manifest supplies movie, background, gradient, samples [{frame, source}],
rate [num,den], exclude [[x,y,w,h]], and limits {rms_detrended,p99,blk16}.
Pixels must match the undithered background before masking. Exclusions include
engine overlays/captions. Measurements use BT.709 limited-range 8-bit code units.
"""
import argparse
import json
import math
import html
import re
import pathlib
import subprocess
import sys

import numpy as np
from PIL import Image, ImageOps, ImageDraw

from process_control import Runner
from release import sha256
from timeline import Timeline, frame_at, rate, snap


def y_of_rgb(rgb):
    return 16 + 219 * np.dot(rgb, [0.2126, 0.7152, 0.0722]) / 255


def ideal_rgb(w, h, gradient):
    cx, cy, radius, mid = (gradient[k] for k in ('cx', 'cy', 'r', 'mid'))
    if radius <= 0 or not 0 < mid < 1:
        raise ValueError('gradient requires r > 0 and 0 < mid < 1')
    y, x = np.mgrid[:h, :w]
    t = np.minimum(np.hypot((x + .5 - cx*w)/(radius*w), (y + .5 - cy*h)/(radius*h)), 1)
    c0, c1, c2 = np.asarray(gradient.get('colors', [[19,27,44], [9,13,21], [4,6,10]]), float)
    a = np.clip(t/mid, 0, 1)[...,None]
    b = np.clip((t-mid)/(1-mid), 0, 1)[...,None]
    return np.where((t <= mid)[...,None], c0 + (c1-c0)*a, c1 + (c2-c1)*b)


def blur(a, sigma=2):
    r = int(math.ceil(3*sigma))
    kernel = np.exp(-.5*(np.arange(-r, r+1)/sigma)**2)
    kernel /= kernel.sum()
    for axis in (1, 0):
        pads = [(0,0)] * 2
        pads[axis] = (r,r)
        a = np.apply_along_axis(lambda v: np.convolve(v, kernel, mode='valid'), axis, np.pad(a, pads, mode='edge'))
    return a


def background_mask(source, background, excludes=(), margin=8, border=20):
    if source.shape != background.shape:
        raise ValueError('source and background dimensions differ')
    e = np.any(source != background, axis=2)
    h, w = e.shape
    # Mask overlays before dilation so the blur never leaks caption edges in.
    for x,y,rw,rh in excludes:
        if rw <= 0 or rh <= 0:
            raise ValueError('exclusion rectangles require positive dimensions')
        e[max(0,y):min(h,y+rh), max(0,x):min(w,x+rw)] = True
    for _ in range(margin):
        old = e.copy()
        e[1:] |= old[:-1]; e[:-1] |= old[1:]
        e[:,1:] |= old[:,:-1]; e[:,:-1] |= old[:,1:]
        e[1:,1:] |= old[:-1,:-1]; e[1:,:-1] |= old[:-1,1:]
        e[:-1,1:] |= old[1:,:-1]; e[:-1,:-1] |= old[1:,1:]
    m = ~e
    if border:
        m[:border] = m[-border:] = False
        m[:,:border] = m[:,-border:] = False
    return m


def metrics(decoded, source, ideal, mask):
    if mask.mean() < .01:
        raise ValueError('less than 1% usable background after masks')
    error = blur(y_of_rgb(decoded)) - blur(y_of_rgb(ideal))
    original = blur(y_of_rgb(source)) - blur(y_of_rgb(ideal))
    measured = error[mask]
    deltas = []
    interiors = []
    # Check both orientations; horizontal-only checking misses row banding.
    for axis in (0,1):
        diff = np.abs(np.diff(error, axis=axis))
        valid = (mask[1:] & mask[:-1]) if axis == 0 else (mask[:,1:] & mask[:,:-1])
        pos = np.arange(diff.shape[axis]) % 16 == 15
        edge = pos[:,None] if axis == 0 else pos[None,:]
        if (valid & edge).any(): deltas.append(diff[valid & edge])
        if (valid & ~edge).any(): interiors.append(diff[valid & ~edge])
    if not deltas or not interiors:
        raise ValueError('insufficient block boundaries after masks')
    return dict(bg_frac=float(mask.mean()), rms=float(np.sqrt(np.mean(measured**2))),
                rms_detrended=float(measured.std()), mean_err=float(measured.mean()),
                p99=float(np.percentile(np.abs(measured),99)),
                rms_8bit_source=float(np.sqrt(np.mean(original[mask]**2))),
                rms_detrended_8bit_source=float(original[mask].std()),
                blk16=float(np.mean(np.concatenate(deltas))/max(np.mean(np.concatenate(interiors)),1e-9)))


def decode_frame(movie, frame, w, h, fps, runner=None):
    num,den=rate(fps)
    target=frame*den/num
    raw = (runner or Runner()).run(['ffmpeg','-nostdin','-v','error','-ss',f'{max(0,target-2):.12f}',
        '-copyts','-start_at_zero','-i',str(movie),'-vf',f'select=gte(t\\,{target-.25*den/num:.12f})',
        '-frames:v','1','-fps_mode','passthrough','-f','rawvideo','-pix_fmt','rgb48le','-'],capture=True).stdout
    if len(raw) != w*h*6:
        raise ValueError(f'frame {frame}: decoded {len(raw)} bytes, expected {w*h*6}')
    return np.frombuffer(raw, '<u2').reshape(h,w,3).astype(np.float32)/257


def temporal_metrics(first, second, ideal, mask):
    if mask.mean() < .01:
        raise ValueError('less than 1% usable temporal background')
    delta = (blur(y_of_rgb(second)) - blur(y_of_rgb(ideal))) - (blur(y_of_rgb(first)) - blur(y_of_rgb(ideal)))
    return dict(temporal_rms=float(np.sqrt(np.mean(delta[mask]**2))),
                temporal_p99=float(np.percentile(np.abs(delta[mask]),99)))


def rectangles(manifest, w, h):
    result = list(manifest.get('exclude', []))
    for rect in manifest.get('exclude_normalized', []):
        if len(rect) != 4 or any(not math.isfinite(v) for v in rect):
            raise ValueError('invalid normalized exclusion')
        x,y,rw,rh=rect
        result.append([snap(x*w),snap(y*h),snap(rw*w),snap(rh*h)])
    return result


def run(manifest, root, output, runner=None):
    root,output=pathlib.Path(root),pathlib.Path(output)
    runner=runner or Runner()
    movie=root/manifest['movie']
    movie_hash=sha256(movie)
    facts=json.loads(runner.run(['ffprobe','-v','error','-select_streams','v:0',
                    '-show_entries','stream=width,height','-of','json',movie],capture=True).stdout)
    w,h=(facts['streams'][0][k] for k in ('width','height'))
    references={}
    def reference(name):
        path=root/name
        digest=sha256(path)
        if str(path) in references and references[str(path)] != digest:
            raise ValueError('QC reference changed during verification')
        references[str(path)]=digest
        with Image.open(path) as image:
            return np.asarray(image.convert('RGB').resize((w,h), Image.Resampling.LANCZOS))
    bg=reference(manifest['background'])
    ideal=ideal_rgb(w,h,manifest['gradient'])
    if not manifest.get('samples'):
        raise ValueError('banding check requires at least one sample')
    limits=manifest.get('limits')
    allowed=('rms_detrended','p99','blk16','temporal_rms','temporal_p99')
    if not limits or any(k not in allowed or not isinstance(v,(int,float)) or isinstance(v,bool) or not math.isfinite(v) or v <= 0 for k,v in limits.items()):
        raise ValueError('supply positive, finite banding limits')
    output.parent.mkdir(parents=True,exist_ok=True)
    visuals=output.with_suffix('')
    visuals.mkdir(exist_ok=True)
    rows=[]; tiles=[]
    for index,sample in enumerate(manifest['samples']):
        frame=sample['frame']
        if type(frame) is not int or frame < 0:
            raise ValueError('sample frame must be a nonnegative integer')
        src=reference(sample['source'])
        excludes=rectangles(manifest,w,h)+sample.get('exclude',[])
        mask=background_mask(src,bg,excludes,margin=manifest.get('margin',8),border=manifest.get('border',20))
        dec=decode_frame(movie,frame,w,h,manifest['rate'],runner)
        row=metrics(dec,src,ideal,mask)
        if sample.get('next_source'):
            nxt=reference(sample['next_source'])
            nm=background_mask(nxt,bg,excludes,margin=manifest.get('margin',8),border=manifest.get('border',20))
            next_dec=decode_frame(movie,frame+1,w,h,manifest['rate'],runner)
            row.update(temporal_metrics(dec,next_dec,ideal,mask & nm))
        if any(k.startswith('temporal_') and k not in row for k in limits):
            raise ValueError('temporal thresholds require adjacent reference frames')
        row.update(frame=frame,source=sample['source'])
        row['ok']=all(row[k]<=v for k,v in limits.items())
        # Sevenfold luma residual; neutral grey is zero. Masked overlays are grey.
        residual=blur(y_of_rgb(dec))-blur(y_of_rgb(ideal))
        heat=np.clip(128+7*residual,0,255).astype('uint8')
        heat[~mask]=128
        thumb_size=(320,240)
        strip=Image.new('RGB',(960,264),'#171b22')
        draw=ImageDraw.Draw(strip)
        for j,(label,im) in enumerate((('Source',Image.fromarray(src)),('Decoded',Image.fromarray(np.uint8(np.clip(dec,0,255)))),('Residual x7',Image.fromarray(heat).convert('RGB')))):
            tile=ImageOps.contain(im,thumb_size)
            strip.paste(tile,(320*j,24)); draw.text((320*j+4,4),f'{frame}: {label}',fill='white')
        name=f'frame-{frame:08d}-{index}.png'
        strip.save(visuals/name)
        row['diagnostic']=str(visuals.name+'/'+name)
        tiles.append(strip); rows.append(row)
    # Bind results to exact movie and all source/background bytes, including temporal references.
    if sha256(movie)!=movie_hash or any(sha256(p)!=h for p,h in references.items()):
        raise ValueError('QC input changed during verification')
    sheet=Image.new('RGB',(960,264*len(tiles)),'#171b22')
    for i,tile in enumerate(tiles): sheet.paste(tile,(0,264*i))
    sheet.save(visuals/'contact-sheet.jpg')
    keys=[k for k in ('rms','rms_detrended','p99','blk16','temporal_rms','temporal_p99') if all(k in r for r in rows)]
    summary=dict(movie=str(movie),sha256=movie_hash,geometry=[w,h],rate=list(rate(manifest['rate'])),
                 references=references,limits=limits,frames=rows,ok=all(r['ok'] for r in rows),
                 worst_frames=[r['frame'] for r in sorted(rows,key=lambda r:r['p99'],reverse=True)[:5]],
                 contact_sheet=str(visuals.name+'/contact-sheet.jpg'),
                 **{'mean_'+k:float(np.mean([r[k] for r in rows])) for k in keys},
                 **{'max_'+k:max(r[k] for r in rows) for k in keys})
    part=output.with_suffix(output.suffix+'.part')
    part.write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n'); part.replace(output)
    output.with_suffix('.html').write_text('<!doctype html><meta charset="utf-8"><title>AV QC</title><h1>AV QC: '+('PASS' if summary['ok'] else 'FAIL')+'</h1><p>'+html.escape(str(movie))+'<br>SHA256 '+movie_hash+'</p><p>Worst frames: '+html.escape(str(summary['worst_frames']))+'</p><img style="max-width:100%" src="'+html.escape(summary['contact_sheet'],quote=True)+'">')
    return summary


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest',type=pathlib.Path)
    p.add_argument('--root',type=pathlib.Path,default=pathlib.Path.cwd())
    p.add_argument('--out',type=pathlib.Path,required=True)
    a = p.parse_args()
    try:
        result = run(json.loads(a.manifest.read_text()),a.root,a.out)
    except (ValueError,KeyError,OSError,subprocess.CalledProcessError) as e:
        print(f'banding: {e}',file=sys.stderr)
        return 2
    print(json.dumps({k:v for k,v in result.items() if k != 'frames'}))
    return 0 if result['ok'] else 1



def authored_gradient(root, short=False):
    path=pathlib.Path(root)/('short/short.w' if short else 'anim/core.w')
    text=path.read_text().replace('\\"','"')
    gradients=re.findall(r'<radialGradient\b[^>]*>(.*?)</radialGradient>',text,re.S)
    tags=re.findall(r'<radialGradient\b([^>]*)>',text)
    if not tags:
        raise ValueError(f'configure an analytical gradient; no radial gradient in {path}')
    attrs=dict(re.findall(r'(cx|cy|r)="([0-9.]+)%"',tags[0]))
    stops=re.findall(r'<stop[^>]*offset="([0-9.]+%?)"[^>]*stop-color="(#[0-9a-fA-F]{6})"',gradients[0])
    if len(stops)!=3 or set(attrs)!= {'cx','cy','r'}:
        raise ValueError(f'configure an analytical gradient for {path}')
    colors=[[int(color[i:i+2],16) for i in (1,3,5)] for _,color in stops]
    return dict(cx=float(attrs['cx'])/100,cy=float(attrs['cy'])/100,r=float(attrs['r'])/100,
                mid=float(stops[1][0].rstrip('%'))/(100 if stops[1][0].endswith('%') else 1),colors=colors)


def film_manifest(root, config, short=False, project=None):
    """Derive samples from the selected cut, exact rate, and authored assets."""
    root=pathlib.Path(root); cfg=config.copy()
    project=project or Timeline.load(root,json.loads((root/'tools/tw.json').read_text()),short)
    limits=cfg.get('limits',dict(rms_detrended=.75,p99=2.0,blk16=2.0,temporal_rms=.5))
    samples=[]
    def add(frame, index, count, directory, pattern='%05d.png',first=0):
        if count<2: raise ValueError('QC requires two adjacent source frames')
        index=min(index,count-2)
        samples.append(dict(frame=frame+index,source=str(directory/(pattern%(index+first))),
                            next_source=str(directory/(pattern%(index+first+1)))))
    if short:
        timeline=json.loads((root/cfg.get('timeline','short/timeline.json')).read_text())
        programs=[s for s in project.resolved['tracks'][0]['items'] if s['kind']=='program' and
                  (not cfg.get('program_id') or s['id']==cfg['program_id'])]
        if len(programs)!=1: raise ValueError('Short auto QC needs one program item; configure explicit samples otherwise')
        program=programs[0]
        origin=program['f0']-program['params'].get('in',0)
        for beat in timeline['beats']:
            nf=frame_at(beat['dur'],project.rate)
            for frac in (.3,.7):
                fi=min(snap((nf-1)*frac),nf-2)
                at=origin+frame_at(beat['start'],project.rate)
                frame=at+fi
                if program['f0']<=frame and frame+1<min(program['f1'],project.frames):
                    add(at,fi,nf,pathlib.Path('short/frames')/beat['id'])
    else:
        document=json.loads(project.episode.read_text())
        asset_root=(project.episode.parent/document.get('root','.')).resolve()
        shots=[s for s in project.resolved['tracks'][0]['items'] if s['kind']=='frames' and s['params']['src'].startswith(cfg.get('asset_prefix','anim:'))]
        count=cfg.get('shots',6)
        if type(count) is not int or count<1: raise ValueError('shots must be positive')
        if len(shots)>count:
            shots=[shots[0]] if count==1 else [shots[snap(i*(len(shots)-1)/(count-1))] for i in range(count)]
        for shot in shots:
            params=shot['params']; key=params['src']; asset=document['assets'][key]
            directory=asset_root/asset['path']
            n=min(shot['f1']-shot['f0'],params.get('count',shot['f1']-shot['f0']))
            offset=params.get('in',0)
            for frac in (.3,.7):
                fi=min(snap((n-1)*frac),n-2)
                add(shot['f0']-offset,fi+offset,n+offset,directory,asset.get('pattern','%05d.png'),asset.get('first',0))
    result=dict(movie=cfg.get('movie',str(project.output('master.mp4'))),rate=list(project.rate),
                background=cfg.get('background','short/bg_rsvg.png' if short else 'anim/bg_rsvg.png'),
                gradient=cfg.get('gradient') or authored_gradient(root,short),
                exclude=cfg.get('exclude',[]),exclude_normalized=cfg.get('exclude_normalized',
                    [[0,0,1,760/1920],[0,1370/1920,1,160/1920]] if short else []),
                samples=samples,limits=limits)
    if 'max_samples' in cfg:
        limit=cfg['max_samples']
        if type(limit) is not int or limit<1: raise ValueError('max_samples must be positive')
        result['samples']=samples[:limit]
    return result

if __name__ == '__main__':
    sys.exit(main())
