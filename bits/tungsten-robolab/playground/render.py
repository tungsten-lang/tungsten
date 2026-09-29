"""Offscreen rendering for robolab runs: activation-tinted bodies plus a HUD.

Each body segment is tinted toward red by the activation of the muscles that
move it (the muscles on its parent joint), so simultaneous contractions are
visible. The HUD draws, per muscle, the commanded contraction (outline) and
the measured contraction (fill), with the active chunk's label.
"""

import numpy as np
import mujoco
from PIL import Image, ImageDraw, ImageFont

try:
    FONT = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
    FONT_BIG = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 22)
except OSError:
    FONT = FONT_BIG = ImageFont.load_default()


class Recorder:
    def __init__(self, sim, width=960, height=544, fps=60, hud=True, scene_option=None):
        self.sim = sim
        self.fps = fps
        self.width, self.height = width, height
        self.renderer = mujoco.Renderer(sim.m, height, width)
        self.scene_option = scene_option
        self.cam = mujoco.MjvCamera()
        self.cam.type = mujoco.mjtCamera.mjCAMERA_FREE
        self.frames = []
        self.next_t = 0.0
        self.hud = hud
        m = sim.m
        self.base_rgba = m.geom_rgba.copy()
        # geoms tinted by the muscles whose joint moves the geom's body
        self.tint = []
        for gi in range(m.ngeom):
            body = m.geom_bodyid[gi]
            if body == 0:
                continue
            idx = [k for k, mu in enumerate(sim.muscles) if m.jnt_bodyid[m.joint(mu.joint).id] == body]
            if idx:
                self.tint.append((gi, idx))

    def maybe_capture(self, sim):
        if sim.d.time + 1e-9 < self.next_t:
            return
        self.next_t += 1.0 / self.fps
        self.capture(sim)

    def capture(self, sim):
        m, d = sim.m, sim.d
        act = d.act[:] if m.na else d.ctrl
        acts = np.zeros(sim.n)
        for k, aid in enumerate(sim.act_ids):
            acts[k] = d.act[m.actuator_actadr[aid]] if m.actuator_actadr[aid] >= 0 else d.ctrl[aid]
        del act
        red = np.array([0.95, 0.25, 0.2, 1.0])
        for gi, idx in self.tint:
            a = float(np.clip(max(acts[k] for k in idx), 0, 1))
            m.geom_rgba[gi] = self.base_rgba[gi] * (1 - a) + red * a
        sim.task.camera(m, d, self.cam)
        if self.scene_option is not None:
            self.renderer.update_scene(d, self.cam, scene_option=self.scene_option)
        else:
            self.renderer.update_scene(d, self.cam)
        ghost = sim.task.ghost_pose(sim) if hasattr(sim.task, "ghost_pose") else None
        if ghost is not None:
            self.add_ghost(sim, *ghost)
        img = self.renderer.render()
        m.geom_rgba[:] = self.base_rgba
        if self.hud:
            img = self.draw_hud(img, sim, acts)
        self.frames.append(img)

    def add_ghost(self, sim, qpos, rgba):
        """Optional overlay: a translucent copy of the body posed at `qpos` (e.g. a
        target keyframe), added to the scene after the body. A task opts in with
        ghost_pose(sim) -> (qpos, rgba) or None; tasks without it render as before."""
        if not hasattr(self, "_ghost_d"):
            self._ghost_d = mujoco.MjData(sim.m)
            self._ghost_opt = mujoco.MjvOption()
            self._ghost_pert = mujoco.MjvPerturb()
        gd = self._ghost_d
        gd.qpos[:] = qpos
        mujoco.mj_kinematics(sim.m, gd)
        scn = self.renderer.scene
        n0 = scn.ngeom
        mujoco.mjv_addGeoms(sim.m, gd, self._ghost_opt, self._ghost_pert, int(mujoco.mjtCatBit.mjCAT_DYNAMIC), scn)
        for i in range(n0, scn.ngeom):
            scn.geoms[i].rgba[:] = rgba

    def draw_hud(self, img, sim, acts):
        im = Image.fromarray(img)
        dr = ImageDraw.Draw(im, "RGBA")
        n = sim.n
        c, _, _ = sim.contraction()
        tgt = sim.targets
        panel_h = 118
        dr.rectangle([0, self.height - panel_h, self.width, self.height], fill=(15, 18, 24, 170))
        bw = max(3, min(14, (self.width - 40) // max(n, 1) - 3))
        x0 = 20
        top = self.height - panel_h + 30
        h = 70
        for k in range(n):
            x = x0 + k * (bw + 3)
            cv = float(np.clip(c[k], 0, 1))
            tv = float(np.clip(tgt[k], 0, 1.3))
            a = float(np.clip(acts[k], 0, 1))
            dr.rectangle([x, top, x + bw, top + h], outline=(80, 85, 95, 255))
            dr.rectangle([x, top + h - cv * h, x + bw, top + h],
                         fill=(int(90 + 160 * a), int(170 - 120 * a), int(230 - 190 * a), 230))
            ty = top + h - min(tv, 1.0) * h
            dr.line([x - 1, ty, x + bw + 1, ty], fill=(255, 255, 255, 255), width=2)
        dr.text((20, self.height - panel_h + 6),
                "muscle contraction: fill = measured, white tick = commanded, colour = activation",
                font=FONT, fill=(220, 225, 235, 255))
        # Light text on a translucent panel reads on any scene (MyoSuite's
        # backgrounds are black, robolab's are pale sky).
        extra_text = sim.task.hud_text(sim.m, sim.d) if hasattr(sim.task, "hud_text") else ""
        panel_bottom = 88 if extra_text else 66
        dr.rectangle([8, 6, self.width - 8, panel_bottom], fill=(15, 18, 24, 150))
        dr.text((20, 14), f"{sim.task.title()}", font=FONT_BIG, fill=(236, 240, 245, 255))
        dr.text((20, 44), f"t = {sim.d.time:5.2f} s   chunk: {sim.label}", font=FONT, fill=(214, 220, 228, 255))
        extra = sim.task.hud_text(sim.m, sim.d) if hasattr(sim.task, "hud_text") else ""
        if extra:
            dr.text((20, 66), extra, font=FONT, fill=(214, 220, 228, 255))
        return np.asarray(im)

    def write_mp4(self, path):
        import imageio.v2 as imageio
        with imageio.get_writer(path, fps=self.fps, codec="libx264", quality=8,
                                macro_block_size=8) as w:
            for f in self.frames:
                w.append_data(f)
        print("wrote", path, len(self.frames), "frames")

    def write_sheet(self, path, count=12, cols=4, scale=0.4):
        if not self.frames:
            return
        idx = [round(i * (len(self.frames) - 1) / max(count - 1, 1)) for i in range(count)]
        w, h = int(self.width * scale), int(self.height * scale)
        rows = (count + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * h), (255, 255, 255))
        for k, i in enumerate(idx):
            sheet.paste(Image.fromarray(self.frames[i]).resize((w, h)), ((k % cols) * w, (k // cols) * h))
        sheet.save(path)
        print("wrote", path)

    def write_gif(self, path, scale=0.5, every=2):
        frames = [Image.fromarray(f).resize((int(self.width * scale), int(self.height * scale)))
                  for f in self.frames[::every]]
        if frames:
            frames[0].save(path, save_all=True, append_images=frames[1:], loop=0,
                           duration=int(1000 * every / self.fps), optimize=True)
            print("wrote", path, len(frames), "frames")
