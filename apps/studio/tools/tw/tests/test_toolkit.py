import importlib.util
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import numpy as np

import banding
import glyphs
import install
from tw import Toolkit


class BandingTests(unittest.TestCase):
    def setUp(self):
        self.ideal=banding.ideal_rgb(256,192,dict(cx=.5,cy=.46,r=.78,mid=.64))
        self.src=np.rint(self.ideal).astype('uint8')
        self.mask=banding.background_mask(self.src,self.src)

    def test_steps_fail_and_fine_dither_passes(self):
        rng=np.random.default_rng(1)
        dither=np.floor(self.ideal+rng.random(self.ideal.shape))
        smooth=banding.metrics(dither,self.src,self.ideal,self.mask)
        steps=np.floor(self.ideal/4)*4
        banded=banding.metrics(steps,self.src,self.ideal,self.mask)
        self.assertLess(smooth['rms_detrended'],.1)
        self.assertGreater(banded['rms_detrended'],.4)
        self.assertGreater(banded['p99'],smooth['p99']+1)

    def test_caption_masks_remove_overlay_and_blur_margin(self):
        decoded=self.ideal.copy(); decoded[80:100,50:200]=255
        m=banding.background_mask(self.src,self.src,[[50,80,150,20]])
        self.assertFalse(m[75:105,45:205].any())
        result=banding.metrics(decoded,self.src,self.ideal,m)
        self.assertLess(result['rms_detrended'],.001)
        self.assertGreater(banding.metrics(decoded,self.src,self.ideal,self.mask)['rms_detrended'],5)

    def test_no_background_is_failure(self):
        with self.assertRaisesRegex(ValueError,'usable background'):
            banding.metrics(self.src,self.src,self.ideal,np.zeros(self.mask.shape,bool))

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is needed for frame-selection verification")
    def test_seek_selects_actual_ntsc_frame(self):
        with tempfile.TemporaryDirectory() as tmp:
            movie=pathlib.Path(tmp)/'frames.mkv'
            frames=np.zeros((90,64,96,3),np.uint8)
            for i in range(90): frames[i]=i*2
            subprocess.run(['ffmpeg','-nostdin','-v','error','-f','rawvideo','-pixel_format','rgb24',
                '-video_size','96x64','-framerate','30000/1001','-i','-','-c:v','ffv1','-pix_fmt','bgr0',str(movie)],
                input=frames.tobytes(),check=True)
            dec=banding.decode_frame(movie,80,96,64,[30000,1001])
            self.assertLess(float(np.abs(dec-160).max()),.8)


@unittest.skipUnless(pathlib.Path(glyphs.FONTS["cuneiform"]).exists(), "Noto script fonts are needed for glyph verification")
class GlyphTests(unittest.TestCase):
    def test_all_four_ancient_scripts_have_actual_outlines(self):
        root=pathlib.Path.home()/'videos/profiles-in-philosophy/zoroaster/fonts'
        cases=[('𒀀',glyphs.FONTS['cuneiform']),('𓀀',glyphs.FONTS['hieroglyphs']),
               ('𐬀𐬁',root/'NotoSansAvestan-Regular.ttf'),('𐎠𐎡',root/'NotoSansOldPersian-Regular.ttf')]
        for text,font in cases:
            if not pathlib.Path(font).exists(): self.skipTest(f'font not available: {font}')
            with self.subTest(text=text):
                svg=glyphs.text_svg(text,font)
                self.assertIn('<path d="M',svg)
                self.assertNotIn('<text',svg)

    def test_missing_glyph_fails_instead_of_tofu(self):
        with self.assertRaisesRegex(ValueError,'missing'):
            glyphs.text_svg('\U0010ffff',glyphs.FONTS['cuneiform'])

    def test_legacy_single_glyph_api(self):
        path,advance=glyphs.glyph_path('𒀀')
        self.assertTrue(path.startswith('M'))
        self.assertGreater(advance,0)


class MigrationTests(unittest.TestCase):
    def test_ordered_biblical_preparation_is_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); tools=root/'tools'; tools.mkdir()
            (tools/'tw_render.sh').write_text("""python3 tools/timeline.py > /dev/null && python3 tools/cues.py > /dev/null
tools/venv/bin/python -I tools/wb_text.py > /dev/null && python3 tools/cues.py > /dev/null
python3 tools/script_glyphs.py > /dev/null && tools/venv/bin/python -I tools/wb_text.py > /dev/null
tools/venv/bin/python -I tools/prep_photos.py > /dev/null
""")
            (tools/'tw_short.sh').write_text('cat anim/core.w short/short.w > render/short_scenes.w\n')
            (tools/'tw_publish.sh').write_text('put $B/master.mp4 render/Test.mp4\n')
            (tools/'tw_anims.py').write_text('')
            cfg=install.config_for(root,pathlib.Path('/tmp/isolated-tw'))
        steps=[s[-1] for s in cfg['before_anims']]
        self.assertEqual(steps,['tools/timeline.py','tools/cues.py','tools/wb_text.py','tools/cues.py',
                                'tools/script_glyphs.py','tools/wb_text.py','tools/prep_photos.py'])

    def test_refuses_shared_main_checkout(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); (root/'tools').mkdir()
            (root/'tools/tw.json').write_text(json.dumps({'tungsten':str(pathlib.Path.home()/'tungsten')}))
            with mock.patch.dict('os.environ',{},clear=True):
                with self.assertRaisesRegex(ValueError,'isolated'): Toolkit(root)

    def test_publish_failure_preserves_existing_file(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); (root/'tools').mkdir()
            (root/'source.mp4').write_bytes(b'complete output')
            (root/'dest.mp4').write_bytes(b'previous output')
            cfg={'tungsten':'/tmp/isolated-tw','publish':{'render':[['source.mp4','dest.mp4']]}}
            (root/'tools/tw.json').write_text(json.dumps(cfg))
            t=Toolkit(root)
            with mock.patch.object(t,'banding',side_effect=ValueError('failed check')):
                with self.assertRaisesRegex(ValueError,'failed check'): t.publish('render')
            self.assertEqual((root/'dest.mp4').read_bytes(),b'previous output')

if __name__=='__main__': unittest.main()
