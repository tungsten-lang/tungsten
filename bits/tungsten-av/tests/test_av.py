import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock
ROOT=pathlib.Path(__file__).resolve().parents[3]
sys.path[:0]=[str(ROOT/'bits/tungsten-av/lib/av'),str(ROOT/'apps/studio/tools/tw')]
from config import Project,ConfigError,Literals
from inputs import Snapshots,sha256,implementation
from process_control import Runner
from resources import Budget
from planner import colour_guard,chapters
import qc

class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name)
    def project(self,extra='',source='source.mov'):
        (self.root/'Bitfile').write_text('name "demo"\nversion "1.0.0"\nav.project "demo", source: '+json.dumps(source)+'\n'+extra)
        return Project.load(self.root)
    def test_profiles_inherit_and_sort(self):
        p=self.project('av.output "share", from: "master", format: :mp4\nav.output "master"\nav.video "all", codec: :hevc10\nav.video "share", bitrate: "1.8M"\nav.audio "master", codec: :pcm, sample_format: :f32le\n')
        self.assertEqual(list(p.profiles()),['master','share']); self.assertEqual(p.profiles()['share']['video']['bitrate'],1800000)
    def test_parent_discovery_and_package_directives(self):
        p=self.project();nested=self.root/'a/b';nested.mkdir(parents=True);self.assertEqual(Project.load(nested).file,p.file)
    def test_no_eval_or_shell_expansion(self):
        for text in ('av.output "master", width: OS.system("touch /tmp/bad")','av.video "all", quality: 1/2','av.resources jobs: $(id)','av.nonesuch "x"','av.output("x")'):
            with self.subTest(text=text),self.assertRaises(ConfigError):self.project(text)
    def test_bad_config_fails_before_execution(self):
        cases=['av.output "a", from: "b"\nav.output "b", from: "a"','av.output "master", width: 3',
          'av.video "all", codec: :hevc10, depth: 8','av.video "all", codec: :prores422, bitrate: "8M"',
          'av.video "all", quality: true','av.resources jobs: 1.5','av.resources decode_ahead: 33',
          'av.colour "all", transfer: :smpte2084','av.text "all", enabled: true','av.text "all", box: [0,0,2,1]',
          'av.quality "all", max_probes: 100','av.anomalies "all", allow_freeze: [[4,2]]',
          'av.audio "all", codec: :aac, bitrate: "192.5k"','av.output "master", path: "source.mov"']
        for text in cases:
            with self.subTest(text=text),self.assertRaises(ConfigError):self.project(text)
    def test_workspace_cannot_target_project_or_git(self):
        for value in ('.','..','.git/cache'):
            (self.root/'Bitfile').write_text(f'av.project "demo", source: "in.mov", workspace: {json.dumps(value)}')
            with self.assertRaises(ConfigError):Project.load(self.root)
    def test_multiline_lists_comments_unicode(self):
        p=self.project('av.audio \"all\", codec: :pcm,\n sample_rate: 48000\nav.input "data", path: "Hebrew # א"\nav.quality "all", sample_frames: [\n 0, 12, # comment\n 24\n]\n')
        self.assertEqual(p.declarations['input'][0]['path'],'Hebrew # א');self.assertEqual(p.profiles()['master']['quality']['sample_frames'],[0,12,24])
    def test_numeric_huge_and_depth_bounded(self):
        self.assertEqual(Literals('9'*400).arguments()[0][0],int('9'*400))
        with self.assertRaises(ConfigError):Literals('['*20+'0'+']'*20).arguments()
        with self.assertRaises(ConfigError):Literals('1e999').arguments()
    def test_source_gate_equality_and_failures(self):
        path=self.root/'checks.txt';path.write_text('controls: 7 rejected: 7\n')
        declaration=dict(path=str(path),pattern=r'controls: (\d+) rejected: (\d+)',equal=[1,2])
        self.assertTrue(qc.source_gates([declaration])['ok'])
        path.write_text('controls: 7 rejected: 6\n');self.assertFalse(qc.source_gates([declaration])['ok'])

    def test_preflight_rejects_missing_required_audio(self):
        from planner import build
        p=self.project();(self.root/'source.mov').write_bytes(b'fixture');p.settings['toolchain']=str(ROOT)
        native=mock.Mock();native.capabilities.return_value=dict(available=True,codecs=['hevc10'],backends=['cpu'])
        native.facts.return_value=dict(width=160,height=90,frames=48,rate=[24,1])
        native.probe.return_value={'streams':[dict(codec_type='video',pix_fmt='yuv420p10le',color_primaries='bt709',color_transfer='bt709',color_space='bt709',color_range='tv')]}
        with mock.patch('planner.shutil.which',return_value='/usr/bin/tool'),self.assertRaisesRegex(ConfigError,'no audio track'):build(p,native)
        self.assertEqual(Literals("{'key': 1}").arguments()[0],[{'key':1}])

    def test_chapters_exact_clock(self):
        p=self.project('av.chapters "chapters.json"');(self.root/'chapters.json').write_text(json.dumps([['First',0],dict(title='Second',seconds=1.001)]))
        self.assertEqual(chapters(p,'master',[30000,1001],60),[['First',0],['Second',30]])
    def test_colour_requires_explicit_assumption_rejects_hdr(self):
        probe={'streams':[dict(codec_type='video',pix_fmt='yuv422p10le')]}
        with self.assertRaises(ConfigError):colour_guard(probe,{'untagged':'reject'})
        self.assertEqual(len(colour_guard(probe,{'untagged':'bt709'})['assumed']),4)
        probe['streams'][0]['color_transfer']='smpte2084'
        with self.assertRaises(ConfigError):colour_guard(probe,{'untagged':'bt709'})

class SnapshotTests(unittest.TestCase):
    def test_sealed_bytes_survive_source_changes_and_corruption_rejects(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d).resolve(); source=root/'input.mov';source.write_bytes(b'old');snap=Snapshots(root/'store',Runner(timeout=10))
            record=snap.seal(source);source.write_bytes(b'new');self.assertEqual(pathlib.Path(record['path']).read_bytes(),b'old');self.assertEqual(pathlib.Path(record['path']).suffix,'.mov')
            source.write_bytes(b'old');pathlib.Path(record['path']).chmod(0o644);pathlib.Path(record['path']).write_bytes(b'corrupt')
            with self.assertRaises(ValueError):snap.seal(source)
    def test_tree_follows_and_rewrites_local_use_from_sealed_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d).resolve();(root/'main.w').write_text('use helper\n<< helper()\n');(root/'helper.w').write_text('-> helper\n  1\n')
            snap=Snapshots(root/'store',Runner());records,mapping=snap.tree([root/'main.w'],root,root/'trees')
            self.assertEqual(len(records),2);self.assertIn(mapping[str(root/'helper.w')][:-2],pathlib.Path(mapping[str(root/'main.w')]).read_text())
            self.assertEqual(snap.tree([root/'main.w'],root,root/'trees')[1],mapping)
            self.assertEqual((root/'main.w').read_text(),'use helper\n<< helper()\n')
    def test_gc_preserves_jobs_referenced_by_retained_releases(self):
        from cli import collect
        import time
        import types
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d).resolve();workspace=root/'.av';job=workspace/'jobs/killed-after-activation';job.mkdir(parents=True)
            (job/'job.json').write_text(json.dumps(dict(status='running',pid=99999999)))
            manifest=workspace/'releases/group/retained/manifest.json';manifest.parent.mkdir(parents=True);manifest.write_text(json.dumps(dict(provenance=dict(job=str(job)))))
            os.utime(job,(time.time()-3*86400,)*2)
            project=types.SimpleNamespace(workspace=workspace,resources=lambda:dict(cache_days=1))
            self.assertNotIn(str(job),collect(project)['paths']);self.assertTrue(job.exists())
            manifest.unlink();self.assertIn(str(job),collect(project)['paths']);self.assertTrue(job.exists())

    def test_change_during_snapshot_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d).resolve();source=root/'a';source.write_bytes(b'a');snap=Snapshots(root/'store',Runner())
            import inputs
            original=inputs.sha256
            def changed(path):
                value=original(path)
                if pathlib.Path(path)==source:source.write_bytes(b'b')
                return value
            with mock.patch.object(inputs,'sha256',changed),self.assertRaises(ValueError):snap.seal(source)

class BudgetAndQCTests(unittest.TestCase):
    def test_memory_budget_caps_jobs_and_queue(self):
        p=Budget(dict(memory_mb=512,jobs=64,animation_jobs=32,decode_ahead=32),available_bytes=512*1024**2,cpus=16).choose(1920,1080)
        self.assertLessEqual(p['jobs'],2);self.assertLessEqual(p['animation_jobs'],p['jobs']);self.assertLessEqual(p['decode_ahead'],32)
        with self.assertRaises(ValueError):Budget(dict(memory_mb=1)).choose(1920,1080)
    def test_covered_anomalies_leave_only_unexpected_ranges(self):
        self.assertEqual(qc.uncovered(0,10,[[0,2],[4,8],[7,10]]),[(2,4)])
    def test_subtitle_timestamp_and_language_layout(self):
        with tempfile.TemporaryDirectory() as d:
            path=pathlib.Path(d)/'a.srt';path.write_text('1\n00:00:00,000 --> 00:00:01,000\nHello\n')
            self.assertEqual(qc.captions(path)[0]['text'],'Hello')
            path.write_text('1\n00:00:02,000 --> 00:00:01,000\nHello\n')
            with self.assertRaises(ValueError):qc.captions(path)
    def test_contrast_is_measured(self):
        self.assertAlmostEqual((qc.luminance('#ffffff')+.05)/(qc.luminance('#000000')+.05),21)

if __name__=='__main__':unittest.main()
