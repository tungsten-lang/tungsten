import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

import numpy as np
from PIL import Image

import banding
from process_control import Runner, Cancelled, StageTimeout
from release import BundlePublisher, sha256
from timeline import Timeline, rate, frame_at, delivery
from tw import Toolkit


class TimelineTests(unittest.TestCase):
    def test_exact_rational_clock_and_sample_count(self):
        self.assertEqual(frame_at('1.001',[30000,1001]),30)
        self.assertEqual(frame_at('0.02085416666666667',[24000,1001]),1)
        self.assertEqual(rate([60000,2002]),(30000,1001))
        for invalid in ([0,1],[True,1],[24,0],'24/1'):
            with self.assertRaises(ValueError): rate(invalid)

    def test_nondefault_episode_cut_geometry_paths(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); studio=root/'custom'; studio.mkdir()
            settings=dict(w=640,h=360,rate=[30000,1001],sr=48000)
            (studio/'edit.json').write_text(json.dumps(dict(cuts={'preview':settings})))
            resolved=studio/'build/preview'; resolved.mkdir(parents=True)
            (resolved/'edit.timeline.resolved.json').write_text(json.dumps(dict(settings,frames=60)))
            project=Timeline.load(root,dict(episode='custom/edit.json',cut='preview'))
            self.assertEqual(project.output('master.mov'),(resolved/'edit.master.mov').resolve())
            self.assertEqual(project.samples(),96096)
            self.assertEqual((project.width,project.height),(640,360))
            settings['rate']=[24,1]
            (studio/'edit.json').write_text(json.dumps(dict(cuts={'preview':settings})))
            with self.assertRaisesRegex(ValueError,'stale'): Timeline.load(root,dict(episode='custom/edit.json',cut='preview'))
            # Resolve/render must be able to refresh a changed authoring clock.
            fresh=Timeline.load(root,dict(episode='custom/edit.json',cut='preview'),require_resolved=False)
            self.assertEqual(fresh.rate,(24,1))
            self.assertEqual(fresh.resolved,{})

    def test_short_qc_follows_resolved_program_in_point_and_cut(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); (root/'short').mkdir()
            (root/'short/timeline.json').write_text(json.dumps(dict(beats=[dict(id='b',start=0,dur=2)])))
            project=mock.Mock(rate=(30,1),frames=60,resolved={'tracks':[{'items':[
                dict(id='short',kind='program',f0=10,f1=50,params={'in':20})]}]})
            result=banding.film_manifest(root,dict(gradient=dict(cx=.5,cy=.4,r=.8,mid=.6)),True,project)
            self.assertEqual([s['frame'] for s in result['samples']],[31])
            self.assertEqual(result['samples'][0]['source'],'short/frames/b/00041.png')

    def test_strict_mov_pcm_contract(self):
        self.assertEqual(delivery({'delivery':{'master':{'format':'mov','edit_lists':False}}})['audio_codec'],'pcm')
        for value in (dict(format='mp4',edit_lists=False),dict(format='mov',edit_lists=False,audio_codec='aac')):
            with self.assertRaises(ValueError): delivery({'delivery':{'master':value}})

    def test_authored_gradient_not_fixed_palette(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); (root/'anim').mkdir()
            (root/'anim/core.w').write_text('<radialGradient cx="50%" cy="46%" r="78%"><stop offset="0" stop-color="#123456"/><stop offset=".64" stop-color="#102030"/><stop offset="1" stop-color="#000000"/></radialGradient>')
            gradient=banding.authored_gradient(root)
            self.assertEqual(gradient['colors'][0],[18,52,86]); self.assertEqual(gradient['mid'],.64)


class ProcessTests(unittest.TestCase):
    def test_capture_and_nonzero(self):
        r=Runner(timeout=5).run([sys.executable,'-c','print("ok")'],capture=True)
        self.assertEqual(r.stdout,b'ok\n')
        with self.assertRaises(subprocess.CalledProcessError): Runner().run([sys.executable,'-c','raise SystemExit(7)'],capture=True)

    def test_timeout_kills_grandchild_even_after_parent_exits(self):
        with tempfile.TemporaryDirectory() as d:
            marker=pathlib.Path(d)/'survived'
            grandchild=f'import signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(1); pathlib.Path({str(marker)!r}).touch()'
            parent=f'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",{grandchild!r}]); time.sleep(10)'
            started=time.monotonic()
            with self.assertRaises(StageTimeout): Runner(timeout=.3,grace=.05).run([sys.executable,'-c',parent],capture=True)
            self.assertLess(time.monotonic()-started,2)
            time.sleep(1)
            self.assertFalse(marker.exists())

    def test_outer_timeout_owns_nested_supervisor_children(self):
        with tempfile.TemporaryDirectory() as d:
            marker=pathlib.Path(d)/'survived'
            module=pathlib.Path(__file__).resolve().parents[1]
            child=f'import signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(1); pathlib.Path({str(marker)!r}).touch()'
            parent=f'from process_control import Runner; import sys; r=Runner(timeout=10,grace=2)\nwith r.signals(): r.run([sys.executable,"-c",{child!r}],capture=True)'
            with self.assertRaises(StageTimeout):
                Runner(timeout=.3,grace=.05).run([sys.executable,'-c',parent],env=dict(os.environ,PYTHONPATH=str(module)),capture=True)
            time.sleep(1)
            self.assertFalse(marker.exists())

    def test_cancel_and_no_new_stage(self):
        runner=Runner(timeout=5,grace=.05)
        timer=threading.Timer(.2,runner.cancel); timer.start()
        try:
            with self.assertRaises(Cancelled): runner.run([sys.executable,'-c','import time; time.sleep(5)'],capture=True)
            with self.assertRaises(Cancelled): runner.run([sys.executable,'-c','print(1)'])
        finally: timer.join()

    def test_signal_handler_cancels_active_stage(self):
        module=pathlib.Path(__file__).resolve().parents[1]
        script='import os,signal,threading,sys; from process_control import Runner,Cancelled; r=Runner(grace=.05); t=threading.Timer(.2,lambda:os.kill(os.getpid(),signal.SIGINT)); t.start()\ntry:\n with r.signals(): r.run([sys.executable,"-c","import time;time.sleep(9)"],capture=True)\nexcept Cancelled: print("cancelled")\nt.join()'
        result=subprocess.run([sys.executable,'-c',script],env=dict(os.environ,PYTHONPATH=str(module)),capture_output=True,timeout=5,check=True)
        self.assertIn(b'cancelled',result.stdout)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.root=pathlib.Path(self.tmp.name)
        self.entries=[]
        for role in ('film','short','share'):
            src=self.root/(role+'.src'); dest=self.root/(role+'.mp4')
            src.write_bytes(('new '+role).encode()); dest.write_bytes(('old '+role).encode())
            self.entries.append(dict(source=src,destination=dest,role=role))
        self.seen=[]
        def verify(path,entry,reports):
            self.seen.append(path.read_bytes())
            (reports/'check.json').write_text(json.dumps(dict(sha256=sha256(path),ok=True)))
            return dict(ok=True)
        self.publisher=BundlePublisher(self.root/'releases',verify)

    def tearDown(self): self.tmp.cleanup()

    def test_coherent_bundle_hashes_and_following_aliases(self):
        final=self.publisher.publish(self.entries,{'tool':'v1'})
        self.assertEqual((self.root/'releases/current').resolve(),final)
        manifest=json.loads((final/'manifest.json').read_text())
        self.assertEqual(len(self.seen),3)
        for entry,item in zip(self.entries,manifest['files']):
            self.assertEqual(entry['destination'].read_bytes(),entry['source'].read_bytes())
            self.assertEqual(item['sha256'],sha256(entry['destination']))
        for name,digest in manifest['reports'].items(): self.assertEqual(sha256(final/name),digest)
        for entry in self.entries: entry['source'].write_bytes(b'second release')
        second=self.publisher.publish(self.entries,{'tool':'v2'})
        self.assertNotEqual(final,second)
        self.assertTrue(all(e['destination'].read_bytes()==b'second release' for e in self.entries))
        self.assertEqual((final/manifest['files'][0]['name']).read_bytes(),b'new film')

    def test_stage_pins_one_source_release_across_pointer_switch(self):
        import release
        first=self.publisher.publish(self.entries,{})
        for entry in self.entries: entry['source'].write_bytes(b'second release')
        second=self.publisher.publish(self.entries,{})
        release.link_atomic(first,self.root/'releases/current')
        stage_entries=[dict(source=e['destination'],destination=self.root/('stage-'+e['role']),role=e['role']) for e in self.entries]
        stage=BundlePublisher(self.root/'stage',lambda *args:dict(ok=True))
        copy=release.shutil.copyfile
        def switch(src,dest):
            copy(src,dest)
            release.link_atomic(second,self.root/'releases/current')
        with mock.patch.object(release.shutil,'copyfile',side_effect=switch): stage.publish(stage_entries,{})
        self.assertEqual([e['destination'].read_bytes() for e in stage_entries],[b'new film',b'new short',b'new share'])

    def test_failed_candidate_preserves_complete_previous_bundle(self):
        final=self.publisher.publish(self.entries,{})
        self.publisher.verify=lambda *args:dict(ok=False)
        with self.assertRaisesRegex(ValueError,'verification failed'): self.publisher.publish(self.entries,{})
        self.assertEqual((self.root/'releases/current').resolve(),final)
        self.assertEqual([e['destination'].read_bytes() for e in self.entries],[b'new film',b'new short',b'new share'])

    def test_candidate_mutation_cannot_publish(self):
        def mutate(path,entry,reports): path.write_bytes(b'corrupted'); return dict(ok=True)
        self.publisher.verify=mutate
        with self.assertRaisesRegex(ValueError,'changed'): self.publisher.publish(self.entries,{})
        self.assertEqual(self.entries[0]['destination'].read_bytes(),b'old film')

    def test_first_install_failure_rolls_back_legacy_filenames(self):
        import release
        original=release.link_atomic
        def fail(target,path):
            if path==self.entries[1]['destination'].parent.resolve()/self.entries[1]['destination'].name: raise OSError('disk failure')
            return original(target,path)
        with mock.patch.object(release,'link_atomic',side_effect=fail):
            with self.assertRaisesRegex(OSError,'disk failure'): self.publisher.publish(self.entries,{})
        self.assertEqual([e['destination'].read_bytes() for e in self.entries],[b'old film',b'old short',b'old share'])

    def test_cancellation_after_checks_does_not_activate(self):
        runner=Runner()
        self.publisher.check_cancelled=runner.check_cancelled
        verify=self.publisher.verify
        def cancel(path,entry,reports):
            result=verify(path,entry,reports)
            if entry['role']=='share': runner.cancel()
            return result
        self.publisher.verify=cancel
        with self.assertRaises(Cancelled): self.publisher.publish(self.entries,{})
        self.assertEqual([e['destination'].read_bytes() for e in self.entries],[b'old film',b'old short',b'old share'])

    def test_duplicate_or_missing_files_do_not_publish(self):
        with self.assertRaisesRegex(ValueError,'duplicate'): self.publisher.publish([self.entries[0]]*2,{})
        self.entries[0]['source'].unlink()
        with self.assertRaisesRegex(ValueError,'missing'): self.publisher.publish(self.entries,{})


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'ffmpeg/ffprobe required')
class QCDiagnosticsTests(unittest.TestCase):
    def test_share_geometry_temporal_failure_and_content_bound_diagnostics(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d)
            gradient=dict(cx=.5,cy=.46,r=.78,mid=.64)
            reference=np.rint(banding.ideal_rgb(256,192,gradient)).astype('uint8')
            Image.fromarray(reference).save(root/'bg.png')
            resized=np.asarray(Image.fromarray(reference).resize((128,96),Image.Resampling.LANCZOS))
            frames=np.stack([resized,np.clip(resized.astype(int)+8,0,255).astype('uint8')])
            subprocess.run(['ffmpeg','-nostdin','-v','error','-f','rawvideo','-pixel_format','rgb24','-video_size','128x96','-framerate','30000/1001','-i','-','-c:v','ffv1','-pix_fmt','bgr0',str(root/'share.mkv')],input=frames.tobytes(),check=True)
            manifest=dict(movie='share.mkv',background='bg.png',rate=[30000,1001],gradient=gradient,
                          samples=[dict(frame=0,source='bg.png',next_source='bg.png')],
                          limits=dict(rms_detrended=1,p99=3,blk16=3,temporal_rms=1))
            result=banding.run(manifest,root,root/'qc/report.json')
            self.assertFalse(result['ok']); self.assertGreater(result['frames'][0]['temporal_rms'],6)
            self.assertEqual(result['geometry'],[128,96]); self.assertEqual(result['sha256'],sha256(root/'share.mkv'))
            self.assertTrue((root/'qc/report/contact-sheet.jpg').is_file())
            self.assertTrue((root/'qc/report.html').is_file())
            self.assertEqual(result['references'][str(root/'bg.png')],sha256(root/'bg.png'))
            manifest['limits'].pop('temporal_rms'); manifest['samples']=[]
            with self.assertRaisesRegex(ValueError,'at least one'): banding.run(manifest,root,root/'empty.json')

if __name__=='__main__': unittest.main()
