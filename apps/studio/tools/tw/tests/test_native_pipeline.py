"""Opt-in end-to-end fixture: real native media, toolkit checks and publication."""
import json
import os
import pathlib
import tempfile
import unittest
import wave
import sys
import time
import shlex
from process_control import Runner, StageTimeout

import numpy as np
from PIL import Image

import banding
from tw import Toolkit
from release import sha256


@unittest.skipUnless(os.environ.get('RUN_AV_NATIVE')=='1','set RUN_AV_NATIVE=1 on macOS for native pipeline integration')
class NativePipelineTests(unittest.TestCase):
    def test_deadline_reaches_native_spawn_and_system_workers(self):
        tw=pathlib.Path(__file__).resolve().parents[5]
        with tempfile.TemporaryDirectory(prefix='av-workers-') as d:
            root=pathlib.Path(d)
            binary=root/'worker'
            Runner(timeout=120).run([tw/'bin/tungsten','-o',binary,pathlib.Path(__file__).with_name('worker.w')])
            for mode in ('spawn','system'):
                marker=root/(mode+'.survived')
                code=f'import signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(1); pathlib.Path({str(marker)!r}).touch()'
                args=[sys.executable,'-c',code]
                command=[binary,mode,*([shlex.join(args)] if mode=='system' else args)]
                with self.assertRaises(StageTimeout): Runner(timeout=.3,grace=.05).run(command,capture=True)
                time.sleep(1)
                self.assertFalse(marker.exists(),mode+' worker escaped cancellation')

    def test_ntsc_cut_mov_pcm_share_qc_and_exact_bundle_publication(self):
        with tempfile.TemporaryDirectory(prefix='av-native-') as d:
            root=pathlib.Path(d).resolve(); (root/'tools').mkdir(); (root/'custom/frames').mkdir(parents=True)
            gradient=dict(cx=.5,cy=.46,r=.78,mid=.64)
            pixels=np.rint(banding.ideal_rgb(160,90,gradient)).astype('uint8')
            for i in range(60): Image.fromarray(pixels).save(root/f'custom/frames/{i:05d}.png')
            Image.fromarray(pixels).save(root/'bg.png')
            assets={'anim:test':dict(kind='frames',path='frames',pattern='%05d.png',first=0,count=60,sha256='fixture')}
            episode=dict(schema='studio.episode/2',id='fixture',title='Fixture',root='.',seed=1,
                         cuts={'preview':dict(w=160,h=90,rate=[30000,1001],sr=48000,tc_start='00:00:00;00',colour='bt709',end=dict(ref='start',ms=2002),encoder=dict(codec='hevc10',quality=.8))},
                         assets=assets,styles={},lines=[],cues=[],captions=[],
                         shots=[dict(id='frame',kind='frames',src='anim:test',at=dict(ref='start',ms=0),trans_in=dict(kind='cut',frames=0))],
                         markers=[dict(id='intro',kind='chapter',title='Intro',at=dict(ref='start',ms=0))])
            # A real program consumes the rational clock and geometry supplied
            # through studio to native worker pools, rather than fixed constants.
            (root/'custom/scene.w').write_text('a = argv()\nraise "program clock missing" if env("TW_RATE_NUM") != "30000" || env("TW_RATE_DEN") != "1001"\nraise "program geometry missing" if env("TW_WIDTH") != "160" || env("TW_HEIGHT") != "90"\ni = a[1].to_i\nwhile i <= a[2].to_i\n  cmd = "cp " + a[0] + "/frames/00000.png " + a[3] + "/" + Motion.pad(i, 5) + ".png"\n  raise "fixture frame copy failed" if !OS.system(cmd)\n  i += 1\n')
            episode['shots']=[dict(id='scene',kind='program',at=dict(ref='start',ms=0),trans_in=dict(kind='cut',frames=0),
                                   program=dict(source='scene.w',data=['frames/00000.png'],run=['{root}','{first}','{last}','{dir}'],frames='{dir}/%05d.png',count='dur'))]
            for name in ('edit','short'):
                (root/f'custom/{name}.json').write_text(json.dumps(episode))
            samples=96096
            audio=bytearray(samples*6)
            for sample in range(24024,24264):
                value=1000000 if sample%24<12 else -1000000
                for ch in (0,1): audio[(sample*2+ch)*3:(sample*2+ch+1)*3]=value.to_bytes(3,'little',signed=True)
            with wave.open(str(root/'mix.wav'),'wb') as stream:
                stream.setnchannels(2); stream.setsampwidth(3); stream.setframerate(48000); stream.writeframes(audio)
            tw=pathlib.Path(__file__).resolve().parents[5]
            qc=dict(movie='unused',background='bg.png',rate=[30000,1001],gradient=gradient,
                    samples=[dict(frame=20,source='custom/frames/00020.png',next_source='custom/frames/00021.png')],
                    limits=dict(rms_detrended=1,p99=3,blk16=3,temporal_rms=1))
            cfg=dict(tungsten=str(tw),episode='custom/edit.json',cut='preview',short_episode='custom/short.json',short_cut='preview',
                     generator_clock='env-v1',import_command=[],auto_plates=False,mix_source='mix.wav',
                     delivery={'master':dict(format='mov',edit_lists=False,audio_codec='pcm'),
                               'share':dict(format='mov',edit_lists=False,audio_codec='pcm',codec='hevc10',width=128,height=72,kbps=1000)},
                     banding={'film':qc,'short':qc,'share':qc},
                     publish={'render':[dict(source='custom/build/preview/'+name,destination='published/'+role+'.mov',role=role)
                                        for name,role in [('edit.master.mov','film'),('short.master.mov','short'),('edit.share.mov','share')]]})
            cfg['publish']['stage']=[dict(source='published/'+role+'.mov',destination='staged/'+role+'.mov',role=role) for role in ('film','short','share')]
            (root/'tools/tw.json').write_text(json.dumps(cfg))
            t=Toolkit(root)
            with t.runner.signals():
                t.render(['picture','mix','master','share','verify','banding'])
                short=t.project(True,False)
                for command in ('resolve','render'): t.studio_call(command,short)
                t.call([t.out/'tw_mix',root/'mix.wav',short.output('mix.wav'),60,'--rate','30000/1001'])
                t.studio_call('mux',short,'--out',t.master(short),'--no-edit-lists','--audio-codec','pcm')
                # mix with no narration still has exact duration; production gates require audio presence.
                release=t.publish('render')
                staged=t.publish('stage')
                staged_manifest=json.loads((staged/'manifest.json').read_text())
                self.assertTrue(all(item['source_release']==str(release) for item in staged_manifest['files']))
            manifest=json.loads((release/'manifest.json').read_text())
            self.assertEqual(len(manifest['files']),3)
            self.assertEqual(t.project().samples(),96096)
            for item in manifest['files']:
                self.assertEqual(item['sha256'],sha256(root/'published'/f'{item["role"]}.mov'))
                self.assertTrue(item['verification']['ok'])
                self.assertEqual(json.loads((release/(item['name']+'.checks')/'native.json').read_text())['ok'],True)
            # Wrong bytes at the share source are rejected without moving the release pointer.
            share=t.project().output('share.mov'); share.write_bytes(b'incomplete')
            with self.assertRaises(Exception): t.publish('render')
            self.assertEqual((release.parent/'current').resolve(),release)
