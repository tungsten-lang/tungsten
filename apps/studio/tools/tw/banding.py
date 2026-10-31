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
import pathlib
import subprocess
import sys

import numpy as np
from PIL import Image


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


def decode_frame(movie, frame, w, h, rate):
    num,den=rate
    if num <= 0 or den <= 0: raise ValueError('rate must be positive')
    # Seek near the target, retain original PTS, select the first CFR picture
    # at the requested index. The quarter-frame tolerance avoids decimal tie errors.
    target=frame*den/num
    raw = subprocess.check_output(['ffmpeg','-nostdin','-v','error','-ss',f'{max(0,target-2):.12f}',
        '-copyts','-start_at_zero','-i',str(movie),'-vf',f'select=gte(t\\,{target-.25*den/num:.12f})',
        '-frames:v','1','-fps_mode','passthrough','-f','rawvideo','-pix_fmt','rgb48le','-'])
    if len(raw) != w*h*6:
        raise ValueError(f'frame {frame}: decoded {len(raw)} bytes, expected {w*h*6}')
    return np.frombuffer(raw, '<u2').reshape(h,w,3).astype(np.float32)/257


def run(manifest, root, output):
    root = pathlib.Path(root)
    bg = np.asarray(Image.open(root/manifest['background']).convert('RGB'))
    h,w = bg.shape[:2]
    ideal = ideal_rgb(w,h,manifest['gradient'])
    if not manifest.get('samples'):
        raise ValueError('banding check requires at least one sample')
    limits = manifest.get('limits')
    if not limits or any(k not in ('rms_detrended','p99','blk16') or not math.isfinite(v) or v <= 0 for k,v in limits.items()):
        raise ValueError('supply positive, finite banding limits (rms_detrended, p99, blk16)')
    rows = []
    for s in manifest['samples']:
        frame = s['frame']
        if not isinstance(frame,int) or frame < 0:
            raise ValueError('sample frame must be a nonnegative integer')
        src = np.asarray(Image.open(root/s['source']).convert('RGB'))
        mask = background_mask(src,bg,manifest.get('exclude',[])+s.get('exclude',[]))
        dec = decode_frame(root/manifest['movie'],frame,w,h,manifest['rate'])
        row = metrics(dec,src,ideal,mask)
        row.update(frame=frame,source=s['source'])
        row['ok'] = all(row[k] <= v for k,v in limits.items())
        rows.append(row)
    summary = dict(movie=manifest['movie'],limits=limits,frames=rows,
                   ok=all(r['ok'] for r in rows),
                   **{'mean_'+k:float(np.mean([r[k] for r in rows])) for k in ('rms','rms_detrended','p99','blk16')})
    output = pathlib.Path(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    part = output.with_suffix(output.suffix+'.part')
    part.write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n')
    part.replace(output)
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



def film_manifest(root, config, short=False):
    """Derive sample locations from the current resolved cut, never stale seconds."""
    root=pathlib.Path(root)
    cfg=config.copy()
    limits=cfg.get('limits',{'rms_detrended':.75,'p99':2.0,'blk16':2.0})
    samples=[]
    if short:
        timeline=json.loads((root/'short/timeline.json').read_text())
        for beat in timeline['beats']:
            nf=round(beat['dur']*24)
            for frac in (.3,.7):
                fi=round((nf-1)*frac)
                samples.append(dict(frame=round(beat['start']*24)+fi,source=f"short/frames/{beat['id']}/{fi:05d}.png"))
        return dict(movie=cfg.get('movie','studio/build/full/short.master.mp4'),rate=[24,1],
                    background='short/bg_rsvg.png',gradient=dict(cx=.5,cy=.4,r=.8,mid=.6),
                    exclude=cfg.get('exclude',[[0,0,1080,760],[0,1370,1080,160]]),samples=samples,limits=limits)
    r=json.loads((root/'studio/build/full/timeline.resolved.json').read_text())
    shots=[s for s in r['tracks'][0]['items'] if s['kind']=='frames' and str(s['params'].get('src','')).startswith('anim:')]
    count=cfg.get('shots',6)
    if len(shots)>count:
        shots=[shots[round(i*(len(shots)-1)/(count-1))] for i in range(count)]
    for shot in shots:
        aid=shot['params']['src'].split(':',1)[1]
        n=min(shot['f1']-shot['f0'],shot['params'].get('count',shot['f1']-shot['f0']))
        for frac in (.3,.7):
            fi=round((n-1)*frac)
            samples.append(dict(frame=shot['f0']+fi,source=f'anim_frames/{aid}/{fi:05d}.png'))
    return dict(movie=cfg.get('movie','studio/build/full/master.mp4'),rate=r['rate'],
                background='anim/bg_rsvg.png',gradient=dict(cx=.5,cy=.46,r=.78,mid=.64),
                exclude=cfg.get('exclude',[]),samples=samples,limits=limits)

if __name__ == '__main__':
    sys.exit(main())
