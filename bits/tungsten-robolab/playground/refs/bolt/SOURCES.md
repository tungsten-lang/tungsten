# Usain Bolt reference footage

The footage below is broadcast or spectator video. It is kept locally in
`clips/` (gitignored) for analysis only. It is not redistributed, and no clip,
frame, crop or traced-over frame appears in any output. Only numbers,
keypoints (`keypoints_*.npz`) and stick figures drawn from them leave this
directory.

The pipeline is `keyframes.py`, the results are in `bolt_keyframes.json`, and
the figure is `../../../out/bolt_keyframes.png`.

## Clips used

| file | source | section (s) | fps | slow motion | what it shows |
|---|---|---|---|---|---|
| `clips/nitro2017_blocks.mp4` | [y11ZM6389Hg](https://www.youtube.com/watch?v=y11ZM6389Hg), "Usain Bolt Rare Slow Motion Start Practice Nitro Athletics Feb 11th 2017" (Jay Stone) | 0-26 | 30 (1080p container) | **8x**: captured at 240 fps, measured | practice block starts before the 150 m, Nitro Athletics, Melbourne, 11 Feb 2017 |
| `clips/daegu2011_maxv.mp4` | [kKtn0EvRe4E](https://www.youtube.com/watch?v=kKtn0EvRe4E), "Usain Bolt Running Technique: Slow Motion Analysis of the Fastest Sprinter" (posetv) | 8-31 | 59.94 (1080p) | unknown, probably about 1.4x | upright sprinting on the home straight, 200 m preliminary round, World Championships Daegu 2011 |
| `clips/osaka2007_maxv.mp4` | [lRMWjOxVWEQ](https://www.youtube.com/watch?v=lRMWjOxVWEQ), "Tyson Gay & Usain Bolt sideview slo-mo (Osaka WC 2007 200m Final)" (SpeedEndurance) | 1-10 | 25 (720p) | unknown | home straight of the 200 m final, World Championships Osaka 2007 (Bolt 2nd, 19.91; bib 709) |

### nitro2017_blocks

**Camera.** A spectator phone in the stands shows Bolt's right side; he runs left to right, with the camera slightly elevated (about 13°) and slightly behind him. The phone is still during the block phase and then pans to follow him. The pan is measured by phase correlation of the background and removed.

**How the capture rate was measured.** The stadium lamps flicker at 100 Hz (50 Hz mains). In this video that flicker aliases to 0.416-0.417 cycles per frame in both reps, which gives 100 / 0.417 = 240 fps. So 1 video frame is 1/240 s (4.2 ms).

**Rep 1 (frames 0-211):**
- On your marks, then rising into set with almost no still hold (a "rolling" start).
- Rear-foot exit at frame 63 and block exit at frame 106.
- Step 1 touches down at frame 115 and leaves the ground at frame 169.
- Step 2 touches down at frame 173.
- The phone re-frames at frame 213.

**Rep 2 (about frames 255-430):** filmed at night past spectators. Not used.

**Rep 3 (frames 440-722):**
- A still set hold from about frame 466 to frame 512, with onset at frame 513.
- Rear-foot exit at frame 562 and block exit at frame 602.
- Step 1 from frame 610 to frame 665.
- Step 2 from frame 667 to frame 705.

**Bolt's block setup.** His right foot is in the rear block and his left foot in the front block. That makes the rear block leg the near (right) leg and the front block leg the far leg. Step 1 is the right leg.

**Other people in frame.** An official in red stands behind the blocks and is masked before pose estimation.

**Identity.** The uploader says this is Bolt. His build and his coach and officials match, but the face is not resolvable.

### daegu2011_maxv

**Camera.** A broadcast side tracking (rail) camera at steady height shows Bolt's right side; he runs left to right.

**Frames used.** Frames 56-240, about 5 strides. Frames 275-510 and 960-1170 of the file are replays of the same pass. Frames 0-50 show the start from the front and are not used.

**Which race.** Bolt wears hip number 4. The uncut version of this footage ([Y2kOoniBI7c](https://www.youtube.com/watch?v=Y2kOoniBI7c), Exercise Bioenergetics) starts on the bend, so this is a 200 m heat or semi-final, not a 100 m race. The exact round is not verified.

**Playback speed.** The posetv overlay says "Frame Rate 60 fps". Played at that rate, Bolt would take 2.7 m steps at only 3.2 Hz (8.6 m/s), which is implausible, so the footage is slowed. There is no light-flicker clock to measure by how much.

### osaka2007_maxv

**Camera.** A broadcast side tracking camera shows Bolt's right side; he runs left to right, with Tyson Gay in the next lane.

**Frames used.** Frames 20-186. Tracking of Bolt is lost at frames 31-40.

**Quality.** The video is 720p at 25 fps. Several frames have left/right leg-label errors, so this clip is used only as a cross-check.

## Clips reviewed and rejected

Low-resolution previews of these were downloaded to a scratch directory only, to choose clips.

| source | why rejected |
|---|---|
| [HFLuduKmnW0](https://www.youtube.com/watch?v=HFLuduKmnW0) "Usain Bolt 9.58 - 100m World Record [50 fps]" | The 50 fps copy has every frame doubled (25 distinct frames/s). The side rail-camera replay at source 68-84 s was downloaded and tried. Bolt is small, motion-blurred and overlapped by Powell and Gay, and pose was found in only about 60% of frames, often on the wrong runner. The clip was deleted. |
| [bx3Kd-iLUVI](https://www.youtube.com/watch?v=bx3Kd-iLUVI) "2008 2012 2016 Olympics Athletics Men's 100m Final Side View" | Oblique front-side camera. |
| [wgmof1BzuWE](https://www.youtube.com/watch?v=wgmof1BzuWE) "Usain Bolt Block Start Slow Motion" | Close front-oblique view, not sagittal. |
| [A-HKEZwwInQ](https://www.youtube.com/watch?v=A-HKEZwwInQ) "Usain Bolt and Yohan Blake 2011 40m Block start" | Distant 480p shot, oblique view once the athletes are large enough. |
| [Y2kOoniBI7c](https://www.youtube.com/watch?v=Y2kOoniBI7c) "Usain Bolt: Low Foot Clearance and Drive Phase ... (side view)" | Used only to identify the Daegu race. Steps 4-10 are on the bend and filmed obliquely, at 480p. |
| q8VAIIaJX7E, sTQThbbN5L8, TGh7SqVI_w8, 4fjC1Oim0UQ, eai1DZVqIRM, yhaxKsBzGfw, o_d4Q1fgPGE, hgRlrMDQHz4, 82zT2FzOMK0, 3CmhDNQw4n0, 7OwWS8aagiE, tN8wx2t7N7Q, Ct6ei_fa-gw, -4PNWuN5kdw, ga9M3gaLvIM, PdENecWfKas, yLWejYWjANM, jAcm2gudpzA, RD_TtokBUKc, HZcuab6oI_0 | Low resolution, front, overhead or oblique views, heavy overlays, or not Bolt. |

## Re-downloading

Run from `bits/tungsten-robolab`:

```bash
FF=.venv/lib/python3.12/site-packages/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1
Y=".venv-pose/bin/yt-dlp --ffmpeg-location $FF --force-keyframes-at-cuts"
$Y -f 137 --download-sections "*0-26" -o playground/refs/bolt/clips/nitro2017_blocks.mp4 -- y11ZM6389Hg
$Y -f 299 --download-sections "*8-31" -o playground/refs/bolt/clips/daegu2011_maxv.mp4  -- kKtn0EvRe4E
$Y -f "bv*[height=720][ext=mp4]" --download-sections "*1-10" -o playground/refs/bolt/clips/osaka2007_maxv.mp4 -- lRMWjOxVWEQ
```

The clip frame numbers in `keyframes.py` assume exactly these cuts. Check the
frame count if you re-download (780, 1379 and 225 frames).
