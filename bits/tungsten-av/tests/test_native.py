"""Opt-in real native AV/Bitfile integration, independent FFmpeg replay."""
import json
import os
import pathlib
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path[:0]=[str(ROOT/'bits/tungsten-av/lib/av'),str(ROOT/'apps/studio/tools/tw')]
from process_control import Runner
from native import Native
from config import Project
from pipeline import render
import qc
import numpy as np

@unittest.skipUnless(sys.platform=='darwin' and os.environ.get('RUN_AV_NATIVE')=='1','set RUN_AV_NATIVE=1 on macOS')
class NativeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='bit-av-native-');self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name).resolve();self.runner=Runner(timeout=120);self.native=Native(ROOT,ROOT/'bits/tungsten-av',self.runner)
    def source(self):
        path=self.root/'source.mov'
        self.runner.run(['ffmpeg','-nostdin','-v','error','-y','-f','lavfi','-i','testsrc2=size=160x90:rate=24:duration=2','-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=2','-c:v','prores_ks','-profile:v','3','-pix_fmt','yuv422p10le','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-movflags','+write_colr','-c:a','pcm_s24le','-ac','2',path],capture=True)
        return path
    def manifest(self,extra='',source='source.mov'):
        text='name "fixture"\nversion "0.1.0"\nav.project "fixture", source: '+json.dumps(source)+', toolchain: '+json.dumps(str(ROOT))+'\nav.colour "all", untagged: :bt709\nav.resources memory_mb: 1024, jobs: 1, disk_reserve_mb: 0\n'+extra
        (self.root/'Bitfile').write_text(text);return Project.load(self.root)
    def test_prores_vertical_chroma_and_queue_caps(self):
        width,height=160,90
        y=np.full((height,width),512,dtype='<u2');u=np.repeat(np.where(np.arange(height)%2,768,256).astype('<u2')[:,None],width//2,axis=1);v=np.full_like(u,512)
        raw=self.root/'chroma.yuv';raw.write_bytes((y.tobytes()+u.tobytes()+v.tobytes())*8);source=self.root/'chroma.mov'
        self.runner.run(['ffmpeg','-nostdin','-v','error','-y','-f','rawvideo','-pix_fmt','yuv422p10le','-s','160x90','-r','24','-i',raw,'-c:v','prores_ks','-profile:v','3','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-movflags','+write_colr',source],capture=True)
        for backend in ('cpu','metal'):
            output=self.root/(backend+'.mov');result=self.native.request('transcode',source,dict(codec='prores422hq',audio=False,edit_lists=False,decode_ahead=1,segments_ahead=1,scale_backend=backend),self.root,output)
            self.assertEqual(result['decode_chroma'],'422');self.assertLessEqual(result['decoder_queue_peak'],1);self.assertLessEqual(result['segment_queue_peak'],1)
            data=qc.ffmpeg(self.runner,['-v','error','-i',output,'-frames:v','1','-pix_fmt','yuv422p10le','-f','rawvideo','-']).stdout
            decoded=np.frombuffer(data,dtype='<u2')[width*height:width*height+width*height//2].reshape(height,width//2)
            self.assertGreater(abs(float(decoded[1::2,4:-4].mean()-decoded[::2,4:-4].mean())),450)
    def test_profile_audio_formats_and_sample_rates(self):
        self.source()
        declarations=''
        for fmt in ('s16le','s24le','s32le','f32le'):
            declarations+=f'av.output "{fmt}"\nav.video "{fmt}", codec: :prores422lt\nav.audio "{fmt}", codec: :pcm, sample_format: :{fmt}, sample_rate: 44100, channels: 1\n'
        state=render(self.manifest(declarations),self.native)
        self.assertEqual(state['status'],'complete')
        for fmt in ('s16le','s24le','s32le','f32le'):
            path=self.root/'render'/(fmt+'.mov');self.assertTrue(path.is_symlink());probe=self.native.probe(path);a=next(s for s in probe['streams'] if s['codec_type']=='audio')
            self.assertEqual((a['codec_name'],int(a['sample_rate']),a['channels']),('pcm_'+fmt,44100,1))
    def test_final_audio_qc_and_failed_gate_preserve_release(self):
        self.source();project=self.manifest('av.video "all", codec: :prores422hq\n')
        first=render(project,self.native);path=self.root/'render/master.mov';old=path.read_bytes();report=qc.audio(path,dict(target=-22,tolerance=100,true_peak=0,max_silence=3),self.runner,self.root/'meter')
        self.assertTrue(report['ok']);self.assertEqual(report['decoded_frames'],96000)
        with (self.root/'Bitfile').open('a') as out:out.write('av.loudness "all", enabled: true, target: -1, tolerance: 0.01\n')
        with self.assertRaises(ValueError):render(Project.load(self.root),self.native)
        self.assertEqual(path.read_bytes(),old);self.assertTrue(path.is_symlink())
    def test_quality_search_uses_reference_metrics_then_final_verification(self):
        self.source();project=self.manifest('av.output "share", format: :mp4\nav.video "share", codec: :h264\nav.audio "share", codec: :none\nav.quality "share", mode: :search, minimum_bitrate: "400k", maximum_bitrate: "1500k", max_probes: 3, probe_frames: 12, sample_frames: [0,24,36], minimum_ssim: 0.90\n')
        probes=render(project,self.native,['share'],quality_only=True)
        self.assertNotIn('release',probes);self.assertEqual(probes['quality']['share']['bitrate'],400000)
        self.assertGreater(probes['quality']['share']['trials'][0]['samples'][0]['ssim'],.9)
        state=render(project,self.native,['share']);self.assertTrue(state['outputs']['share']['verification']['ok'])

    def test_native_disk_reserve_preserves_delivery(self):
        source=self.source();output=self.root/'previous.mov';output.write_bytes(b'previous')
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            self.native.request('transcode',source,dict(codec='prores422hq',audio=False,disk_reserve_bytes=10**18,retries=0),self.root,output)
        self.assertIn(b'free-disk reserve',raised.exception.stderr);self.assertEqual(output.read_bytes(),b'previous')

    def test_timeline_caption_burning_anomalies_and_alternate_short(self):
        import wave
        root=self.root
        with wave.open(str(root/'mix.wav'),'wb') as stream:
            stream.setnchannels(2);stream.setsampwidth(2);stream.setframerate(48000);stream.writeframes(b'\0'*96000*4)
        cut=dict(w=160,h=90,rate=[24,1],sr=48000,tc_start='01:00:00:00',colour='bt709',end=dict(ref='start',ms=2000),picture=dict(active=[0,0,160,90]))
        document=dict(schema='studio.episode/2',id='caption-test',root='.',cuts={'preview':cut},assets={},styles={},lines=[],shots=[dict(id='black',kind='black',at=dict(ref='start',ms=0),trans_in=dict(kind='cut',frames=0))],cues=[],captions=[],markers=[])
        (root/'scene.w').write_text('a = argv()\nraise "wrong program clock" if env("TW_RATE_NUM") != "24" || env("TW_RATE_DEN") != "1"\nraise "wrong program size" if env("TW_WIDTH") != "160" || env("TW_HEIGHT") != "90"\nc = Canvas.new(160, 90)\nc.clear("#000000")\ni = a[0].to_i\nwhile i <= a[1].to_i\n  c.write_png(a[2] + "/" + Motion.pad(i, 5) + ".png")\n  i += 1\nc.close\n')
        document['shots']=[dict(id='program',kind='program',at=dict(ref='start',ms=0),trans_in=dict(kind='cut',frames=0),program=dict(source='scene.w',data=[],run=['{first}','{last}','{dir}'],frames='{dir}/%05d.png',count='dur')),
                           dict(id='black',kind='black',at=dict(ref='start',ms=1000),trans_in=dict(kind='cut',frames=0))]
        for name in ('edit.json','short.json'):(root/name).write_text(json.dumps(document))
        (root/'captions.srt').write_text('1\n00:00:00,250 --> 00:00:01,750\nHello\n')
        (root/'Bitfile').write_text('name "caption-test"\nav.project "caption-test", timeline: "edit.json", cut: "preview", mix: "mix.wav", toolchain: '+json.dumps(str(ROOT))+'\nav.output "master"\nav.output "short", timeline: "short.json", cut: "preview", mix: "mix.wav"\nav.video "all", codec: :prores422hq\nav.audio "all", codec: :pcm\nav.subtitles "captions.srt", mode: :timeline, language: "en"\nav.text "all", enabled: true, burned: true, font: "/System/Library/Fonts/Supplemental/Arial.ttf", size: 12, minimum_size: 10, box: [0.05,0.6,0.9,0.35]\nav.anomalies "all", enabled: true, black_min: 0.5, freeze_min: 0.5, allow_black: [[0,1]], allow_freeze: [[0,1]]\nav.resources memory_mb: 1024, jobs: 1, disk_reserve_mb: 0\n')
        project=Project.load(root);state=render(project,self.native)
        for name in ('master','short'):
            checks=state['outputs'][name]['verification']['checks'];self.assertTrue(checks['encoded_text']['ok']);self.assertTrue(checks['anomalies']['ok'])
            self.assertTrue((root/'render'/(name+'.en.srt')).is_symlink())
        # Re-activation must leave the immutable previous release byte-identical.
        from inputs import sha256
        release=pathlib.Path(state['release']);before={str(p):sha256(p) for p in release.iterdir() if p.is_file()}
        repeat=render(Project.load(root),self.native);self.assertNotEqual(repeat['release'],state['release'])
        self.assertEqual(before,{str(p):sha256(p) for p in release.iterdir() if p.is_file()})
        self.assertTrue(all(p['result']['resumed_frames']==48 for p in repeat['outputs'].values()))
        env=dict(os.environ,TW_PYTHON=sys.executable)
        checked=self.runner.run([ROOT/'bin/bit','av','verify','--project',root,'--json'],env=env,capture=True)
        self.assertTrue(json.loads(checked.stdout)['ok'])
        with (root/'Bitfile').open('a') as file:file.write('av.publish "upload", root: "upload", profiles: ["master", "short"]\n')
        staged=self.runner.run([ROOT/'bin/bit','av','stage','--project',root,'--json'],env=env,capture=True)
        self.assertTrue(json.loads(staged.stdout)['ok']);self.assertTrue((root/'upload/master.en.srt').is_symlink())


    def test_public_cli_doctor_plan_render_and_status(self):
        self.source();self.manifest('av.video "all", codec: :prores422hq\n')
        env=dict(os.environ,TW_PYTHON=sys.executable)
        def run(command):
            p=self.runner.run([ROOT/'bin/bit','av',command,'--project',self.root,'--json'],env=env,capture=True);return json.loads(p.stdout)
        self.assertTrue(run('doctor')['ok']);self.assertEqual(run('plan')['profiles']['master']['frames'],48);self.assertFalse((self.root/'.av').exists())
        self.assertTrue(run('render')['ok']);self.assertEqual(run('status')['status'],'complete')

if __name__=='__main__':unittest.main()
