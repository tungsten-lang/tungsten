"""Abrupt SIGKILL recovery at actual fsync/digest/pointer boundaries."""
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path[:0]=[str(ROOT/'bits/tungsten-av/lib/av'),str(ROOT/'apps/studio/tools/tw')]
from release import BundlePublisher
from inputs import write_json
from process_control import Runner
from native import Native


def wait_marker(process,path):
    end=time.monotonic()+120
    while not path.exists() and process.poll() is None and time.monotonic()<end:time.sleep(.02)
    if not path.exists():
        process.kill();stdout,stderr=process.communicate();raise AssertionError('barrier not reached: '+str(stdout)+str(stderr))

class PublicationCrashTests(unittest.TestCase):
    def test_kill_before_and_after_pointer_switch_is_coherent(self):
        for boundary in ('before','after'):
            with self.subTest(boundary=boundary),tempfile.TemporaryDirectory() as d:
                root=pathlib.Path(d).resolve();published=root/'published';published.mkdir();store=root/'releases';entries=[]
                for name in ('master.mov','share.mp4'):
                    source=root/name;source.write_bytes(b'old '+name.encode());entries.append(dict(source=source,destination=published/name,role=name))
                first=BundlePublisher(store,lambda *args:dict(ok=True)).publish(entries,{})
                for entry in entries:entry['source'].write_bytes(b'new '+entry['role'].encode())
                marker=root/'barrier'
                code='''import json,pathlib,sys,time
sys.path.insert(0,sys.argv[1]);import release
root=pathlib.Path(sys.argv[2]);marker=root/'barrier';boundary=sys.argv[3];original=release.link_atomic
def linked(target,path):
 if path.name=='current':
  if boundary=='after': original(target,path)
  marker.write_text(boundary)
  while marker.exists():time.sleep(.01)
  if boundary=='before':return original(target,path)
  return
 return original(target,path)
release.link_atomic=linked
entries=[dict(source=root/name,destination=root/'published'/name,role=name) for name in ('master.mov','share.mp4')]
release.BundlePublisher(root/'releases',lambda *args:dict(ok=True)).publish(entries,{})
'''
                process=subprocess.Popen([sys.executable,'-c',code,str(ROOT/'apps/studio/tools/tw'),str(root),boundary],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                try:wait_marker(process,marker);process.kill();process.wait(timeout=10)
                finally:
                    if process.poll() is None:process.kill();process.wait()
                    process.stdout.close();process.stderr.close()
                values=[(published/name).read_bytes().split()[0] for name in ('master.mov','share.mp4')]
                self.assertEqual(values,[b'old',b'old'] if boundary=='before' else [b'new',b'new'])
                # The killed process released its lock; another publication completes.
                BundlePublisher(store,lambda *args:dict(ok=True)).publish(entries,{})
                self.assertTrue(all((published/name).read_bytes().startswith(b'new') for name in ('master.mov','share.mp4')))

@unittest.skipUnless(sys.platform=='darwin' and os.environ.get('RUN_AV_NATIVE')=='1','set RUN_AV_NATIVE=1 on macOS')
class NativeCrashTests(unittest.TestCase):
    def test_kill_and_mutation_at_checkpoint_boundaries(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d).resolve();runner=Runner(timeout=120);native=Native(ROOT,ROOT/'bits/tungsten-av',runner)
            source=root/'source.mov'
            runner.run(['ffmpeg','-nostdin','-v','error','-y','-f','lavfi','-i','testsrc2=size=160x90:rate=24:duration=2','-c:v','prores_ks','-profile:v','3',source],capture=True)
            for boundary in ('segment-synced','digest-committed','mux-finished'):
                output=root/(boundary+'.mov');output.write_bytes(b'previous');marker=root/'barrier';marker.unlink(missing_ok=True)
                options=dict(codec='prores422hq',audio=False,tc=False,edit_lists=False,gop=8,resume_dir=str(root/boundary),retries=0)
                request=root/'request.json';write_json(request,dict(source=str(source),destination=str(output),options=options))
                env=dict(os.environ,TUNGSTEN_MEDIA_TEST_BARRIER=boundary,TUNGSTEN_MEDIA_TEST_MARKER=str(marker),BASH_ENV='')
                process=subprocess.Popen([ROOT/'bin/tungsten',ROOT/'bits/tungsten-av/lib/av/native.w','--','transcode',request],env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                try:wait_marker(process,marker);os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=10)
                finally:
                    if process.poll() is None:os.killpg(process.pid,signal.SIGKILL);process.wait()
                    process.stdout.close();process.stderr.close()
                self.assertEqual(output.read_bytes(),b'previous')
                result=native.request('transcode',source,options,root,output)
                self.assertEqual(result['frames'],48)
                if boundary!='segment-synced':self.assertGreaterEqual(result['resumed_frames'],8)
            # A live source mutation invalidates all digests under the old key.
            marker.unlink(missing_ok=True);options['resume_dir']=str(root/'mutation');env=dict(os.environ,TUNGSTEN_MEDIA_TEST_BARRIER='digest-committed',TUNGSTEN_MEDIA_TEST_MARKER=str(marker),BASH_ENV='')
            write_json(request,dict(source=str(source),destination=str(root/'mutation.mov'),options=options))
            process=subprocess.Popen([ROOT/'bin/tungsten',ROOT/'bits/tungsten-av/lib/av/native.w','--','transcode',request],env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:
                wait_marker(process,marker);os.utime(source,None);marker.unlink();stdout,stderr=process.communicate(timeout=15)
                self.assertNotEqual(process.returncode,0);self.assertIn(b'source changed',stderr)
                self.assertFalse(list((root/'mutation').glob('*/*.sha256')))
            finally:
                if process.poll() is None:os.killpg(process.pid,signal.SIGKILL);process.wait()

if __name__=='__main__':unittest.main()
