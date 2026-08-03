import * as THREE from 'three';

const SIM = JSON.parse(document.getElementById('sim-data').textContent);
let FRAMES = SIM.frames, NFRAMES = FRAMES.length;
let [NX, NY, NZ] = SIM.dims;
const KIND = SIM.kind;

function b64u8(s) {
  const bin = atob(s), u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u;
}
const cache = new Map();
function fieldData(fi, name) {
  const key = fi + ':' + name;
  let d = cache.get(key);
  if (!d) {
    const f = FRAMES[fi].fields[name];
    d = { u8: b64u8(f.b64), min: f.min, max: f.max };
    cache.set(key, d);
  }
  return d;
}
let MASK = SIM.mask ? b64u8(SIM.mask) : null;

const globalRange = {};
function computeRanges() {
  for (const k of Object.keys(globalRange)) delete globalRange[k];
  for (const name of SIM.fields) {
    let lo = Infinity, hi = -Infinity;
    for (const fr of FRAMES) { lo = Math.min(lo, fr.fields[name].min); hi = Math.max(hi, fr.fields[name].max); }
    if (!(hi > lo)) hi = lo + 1e-12;
    globalRange[name] = { lo, hi };
  }
}
computeRanges();

// ---- colormaps -------------------------------------------------------
const STOPS = {
  viridis: [[68,1,84],[71,44,122],[59,81,139],[44,113,142],[33,144,141],[39,173,129],[92,200,99],[170,220,50],[253,231,37]],
  magma:   [[0,0,4],[28,16,68],[79,18,123],[129,37,129],[181,54,122],[229,80,100],[251,135,97],[254,194,135],[252,253,191]],
  coolwarm:[[59,76,192],[98,130,234],[141,176,254],[184,208,249],[221,221,221],[245,196,173],[244,154,123],[222,96,77],[180,4,38]]
};
function buildLUT(name) {
  const stops = STOPS[name], lut = new Uint8Array(256 * 3);
  for (let i = 0; i < 256; i++) {
    const x = i / 255 * (stops.length - 1), k = Math.min(stops.length - 2, Math.floor(x)), t = x - k;
    for (let c = 0; c < 3; c++) lut[i*3+c] = Math.round(stops[k][c] * (1-t) + stops[k+1][c] * t);
  }
  return lut;
}
const LUTS = { viridis: buildLUT('viridis'), magma: buildLUT('magma'), coolwarm: buildLUT('coolwarm') };

// ---- state -----------------------------------------------------------
const state = {
  field: SIM.fields[0], cmap: 'viridis', frame: 0,
  playing: KIND !== 'spacetime' && NFRAMES > 1, speed: 1,
  autoscale: false, iso: 0.5, hscale: 0.35,
  slx: 0.5, sly: 0.5, slz: 0.5,
  showIso: true, showX: false, showY: false, showZ: true
};

// Range used for colors/iso at the current frame.
function scaleRange(fi, name) {
  if (state.autoscale) { const d = fieldData(fi, name); return { lo: d.min, hi: Math.max(d.max, d.min + 1e-12) }; }
  return globalRange[name];
}
// Normalized [0,1] value of sample s of frame data d under range r.
function norm01(d, r, s) {
  const v = d.min + (d.max - d.min) * (s / 255);
  return Math.max(0, Math.min(1, (v - r.lo) / (r.hi - r.lo)));
}

// ---- three.js scene ---------------------------------------------------
const app = document.getElementById('app');
let renderer = null;
try {
  renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  app.appendChild(renderer.domElement);
} catch (e) {
  console.warn('WebGL unavailable: ' + e.message);
  const msg = document.createElement('div');
  msg.style.cssText = 'position:absolute;top:45%;width:100%;text-align:center;color:#8a93a6;font-size:14px';
  msg.textContent = 'WebGL is unavailable in this browser context; data loaded (' + FRAMES.length + ' frames).';
  app.appendChild(msg);
}
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0b0e14);
const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 100);
scene.add(new THREE.AmbientLight(0xffffff, 0.55));
const keyLight = new THREE.DirectionalLight(0xffffff, 1.6);
keyLight.position.set(1.5, 2.2, 1.1);
scene.add(keyLight);
const rimLight = new THREE.DirectionalLight(0x88aaff, 0.5);
rimLight.position.set(-1.4, -0.6, -1.2);
scene.add(rimLight);

// Domain box, normalized so the largest edge is 1.
let ext;
if (KIND === 'volume') ext = [SIM.domain[0], SIM.domain[2], SIM.domain[1]];
else if (KIND === 'surface') ext = [SIM.domain[0], 0.5, SIM.domain[1]];
else ext = [SIM.domain[0], 0.5, 0.75 * SIM.domain[0]];
const em = Math.max(ext[0], ext[2]);
const W = ext[0] / em, D = ext[2] / em, H = KIND === 'volume' ? ext[1] / em : 0.5;

const group = new THREE.Group();
scene.add(group);
const box = new THREE.LineSegments(
  new THREE.EdgesGeometry(new THREE.BoxGeometry(W, H, D)),
  new THREE.LineBasicMaterial({ color: 0x2a3140 }));
box.position.y = KIND === 'volume' ? 0 : H / 2 - 0.02;
group.add(box);

// ---- custom orbit controls --------------------------------------------
const ctl = { theta: -0.65, phi: 1.05, radius: 2.1, target: new THREE.Vector3(0, KIND === 'volume' ? 0 : 0.12, 0) };
function applyCamera() {
  const sp = Math.sin(ctl.phi), cp = Math.cos(ctl.phi);
  camera.position.set(
    ctl.target.x + ctl.radius * sp * Math.sin(ctl.theta),
    ctl.target.y + ctl.radius * cp,
    ctl.target.z + ctl.radius * sp * Math.cos(ctl.theta));
  camera.lookAt(ctl.target);
}
let drag = null;
if (renderer) {
  renderer.domElement.addEventListener('contextmenu', e => e.preventDefault());
  renderer.domElement.addEventListener('pointerdown', e => {
    drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey };
    renderer.domElement.setPointerCapture(e.pointerId);
  });
  renderer.domElement.addEventListener('pointermove', e => {
    if (!drag) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag.x = e.clientX; drag.y = e.clientY;
    if (drag.pan) {
      const s = ctl.radius * 0.0011;
      const fwd = new THREE.Vector3(); camera.getWorldDirection(fwd);
      const right = new THREE.Vector3().crossVectors(fwd, camera.up).normalize();
      const up = new THREE.Vector3().crossVectors(right, fwd).normalize();
      ctl.target.addScaledVector(right, -dx * s).addScaledVector(up, dy * s);
    } else {
      ctl.theta -= dx * 0.0055;
      ctl.phi = Math.max(0.05, Math.min(Math.PI - 0.05, ctl.phi - dy * 0.0055));
    }
  });
  renderer.domElement.addEventListener('pointerup', () => { drag = null; });
  renderer.domElement.addEventListener('wheel', e => {
    e.preventDefault();
    ctl.radius = Math.max(0.3, Math.min(8, ctl.radius * Math.exp(e.deltaY * 0.0011)));
  }, { passive: false });
}

// ---- surface / spacetime ----------------------------------------------
let surf = null;
function buildSurface() {
  const gy = KIND === 'spacetime' ? NFRAMES : NY;
  const geo = new THREE.BufferGeometry();
  const nv = NX * gy;
  const pos = new Float32Array(nv * 3), col = new Float32Array(nv * 3);
  const idx = [];
  for (let j = 0; j < gy; j++)
    for (let i = 0; i < NX; i++) {
      const v = j * NX + i;
      pos[v*3]   = (i / (NX - 1) - 0.5) * W;
      pos[v*3+2] = (j / (gy - 1) - 0.5) * D;
    }
  for (let j = 0; j + 1 < gy; j++)
    for (let i = 0; i + 1 < NX; i++) {
      const a = j * NX + i, b = a + 1, c = a + NX, d = c + 1;
      idx.push(a, c, b, b, c, d);
    }
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.setIndex(idx);
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85, metalness: 0.0, side: THREE.DoubleSide });
  surf = new THREE.Mesh(geo, mat);
  group.add(surf);
}
function updateSurface() {
  const gy = KIND === 'spacetime' ? NFRAMES : NY;
  const pos = surf.geometry.attributes.position.array;
  const col = surf.geometry.attributes.color.array;
  const lut = LUTS[state.cmap];
  const name = state.field;
  const r = KIND === 'spacetime' ? globalRange[name] : scaleRange(state.frame, name);
  for (let j = 0; j < gy; j++) {
    const d = fieldData(KIND === 'spacetime' ? j : state.frame, name);
    for (let i = 0; i < NX; i++) {
      const v = j * NX + i;
      const solid = MASK && MASK[KIND === 'spacetime' ? i : v];
      if (solid) {
        pos[v*3+1] = 0;
        col[v*3] = 0.09; col[v*3+1] = 0.10; col[v*3+2] = 0.13;
        continue;
      }
      const s = d.u8[KIND === 'spacetime' ? i : v];
      const t = norm01(d, r, s);
      pos[v*3+1] = t * state.hscale;
      const ci = Math.round(t * 255) * 3;
      col[v*3] = lut[ci] / 255; col[v*3+1] = lut[ci+1] / 255; col[v*3+2] = lut[ci+2] / 255;
    }
  }
  surf.geometry.attributes.position.needsUpdate = true;
  surf.geometry.attributes.color.needsUpdate = true;
  surf.geometry.computeVertexNormals();
}


// ---- volume: surface-nets isosurface ----------------------------------
const CUBE = [[0,0,0],[1,0,0],[0,1,0],[1,1,0],[0,0,1],[1,0,1],[0,1,1],[1,1,1]];
const EDGES = [[0,1],[2,3],[4,5],[6,7],[0,2],[1,3],[4,6],[5,7],[0,4],[1,5],[2,6],[3,7]];
function surfaceNets(data, level) {
  const cx = NX - 1, cy = NY - 1, cz = NZ - 1;
  const cellV = new Int32Array(cx * cy * cz).fill(-1);
  const verts = [];
  const at = (i,j,k) => data[i + NX * (j + NY * k)];
  let nvert = 0;
  for (let k = 0; k < cz; k++)
    for (let j = 0; j < cy; j++)
      for (let i = 0; i < cx; i++) {
        let bits = 0;
        const c = new Array(8);
        for (let m = 0; m < 8; m++) {
          c[m] = at(i + CUBE[m][0], j + CUBE[m][1], k + CUBE[m][2]);
          if (c[m] < level) bits |= 1 << m;
        }
        if (bits === 0 || bits === 255) continue;
        let px = 0, py = 0, pz = 0, cnt = 0;
        for (const [a, b] of EDGES) {
          const va = c[a], vb = c[b];
          if ((va < level) === (vb < level)) continue;
          const t = (level - va) / (vb - va);
          px += CUBE[a][0] + t * (CUBE[b][0] - CUBE[a][0]);
          py += CUBE[a][1] + t * (CUBE[b][1] - CUBE[a][1]);
          pz += CUBE[a][2] + t * (CUBE[b][2] - CUBE[a][2]);
          cnt++;
        }
        verts.push(
          ((i + px / cnt + 0.5) / NX - 0.5) * W,
          ((k + pz / cnt + 0.5) / NZ - 0.5) * H,
          ((j + py / cnt + 0.5) / NY - 0.5) * D);
        cellV[i + cx * (j + cy * k)] = nvert++;
      }
  const tris = [];
  const cid = (i,j,k) => cellV[i + cx * (j + cy * k)];
  function quad(a, b, c, d, flip) {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) tris.push(a, c, b, a, d, c); else tris.push(a, b, c, a, c, d);
  }
  for (let k = 0; k < NZ; k++)
    for (let j = 0; j < NY; j++)
      for (let i = 0; i < NX; i++) {
        const v0 = at(i, j, k);
        if (i + 1 < NX && j > 0 && j < NY - 1 + 1 && k > 0) {
          if (j >= 1 && k >= 1 && j <= cy && k <= cz) {
            const v1 = at(i + 1, j, k);
            if ((v0 < level) !== (v1 < level))
              quad(cid(i, j-1, k-1), cid(i, j, k-1), cid(i, j, k), cid(i, j-1, k), v0 < level);
          }
        }
        if (j + 1 < NY && i >= 1 && k >= 1 && i <= cx && k <= cz) {
          const v1 = at(i, j + 1, k);
          if ((v0 < level) !== (v1 < level))
            quad(cid(i-1, j, k-1), cid(i-1, j, k), cid(i, j, k), cid(i, j, k-1), v0 < level);
        }
        if (k + 1 < NZ && i >= 1 && j >= 1 && i <= cx && j <= cy) {
          const v1 = at(i, j, k + 1);
          if ((v0 < level) !== (v1 < level))
            quad(cid(i-1, j-1, k), cid(i, j-1, k), cid(i, j, k), cid(i-1, j, k), !(v0 < level));
        }
      }
  return { verts: new Float32Array(verts), tris };
}

let isoMesh = null, maskMesh = null;
const slices = {};
function buildVolume() {
  const mat = new THREE.MeshStandardMaterial({ roughness: 0.55, metalness: 0.05 });
  isoMesh = new THREE.Mesh(new THREE.BufferGeometry(), mat);
  group.add(isoMesh);
  if (MASK) {
    const inv = new Uint8Array(MASK.length);
    for (let i = 0; i < MASK.length; i++) inv[i] = MASK[i] ? 255 : 0;
    const sn = surfaceNets(inv, 128);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(sn.verts, 3));
    g.setIndex(sn.tris);
    g.computeVertexNormals();
    maskMesh = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color: 0x3a4152, roughness: 0.9 }));
    group.add(maskMesh);
  }
  for (const ax of ['x', 'y', 'z']) {
    const geo = new THREE.PlaneGeometry(1, 1);
    const mt = new THREE.MeshBasicMaterial({ side: THREE.DoubleSide, transparent: true, opacity: 0.96 });
    slices[ax] = new THREE.Mesh(geo, mt);
    group.add(slices[ax]);
  }
  slices.x.scale.set(D, H, 1); slices.x.rotation.y = Math.PI / 2;
  slices.y.scale.set(W, H, 1);
  slices.z.scale.set(W, D, 1); slices.z.rotation.x = -Math.PI / 2;
}
function isoLevelU8(d, r) {
  const val = r.lo + state.iso * (r.hi - r.lo);
  const span = d.max > d.min ? d.max - d.min : 1e-12;
  return Math.max(1, Math.min(254, (val - d.min) / span * 255));
}
function updateIso() {
  const d = fieldData(state.frame, state.field);
  const r = scaleRange(state.frame, state.field);
  isoMesh.visible = state.showIso;
  if (!state.showIso) return;
  const level = isoLevelU8(d, r);
  const sn = surfaceNets(d.u8, level);
  isoMesh.geometry.dispose();
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(sn.verts, 3));
  g.setIndex(sn.tris);
  g.computeVertexNormals();
  isoMesh.geometry = g;
  const lut = LUTS[state.cmap], ci = Math.round(state.iso * 255) * 3;
  isoMesh.material.color.setRGB(lut[ci]/255, lut[ci+1]/255, lut[ci+2]/255);
  document.getElementById('iso-val').textContent = (r.lo + state.iso * (r.hi - r.lo)).toPrecision(3);
}
function sliceTexture(ax) {
  const d = fieldData(state.frame, state.field);
  const r = scaleRange(state.frame, state.field);
  const lut = LUTS[state.cmap];
  let wpx, hpx, get;
  const ix = Math.min(NX-1, Math.round(state.slx * (NX-1)));
  const iy = Math.min(NY-1, Math.round(state.sly * (NY-1)));
  const iz = Math.min(NZ-1, Math.round(state.slz * (NZ-1)));
  if (ax === 'x') { wpx = NY; hpx = NZ; get = (a,b) => d.u8[ix + NX*(a + NY*b)]; }
  else if (ax === 'y') { wpx = NX; hpx = NZ; get = (a,b) => d.u8[a + NX*(iy + NY*b)]; }
  else { wpx = NX; hpx = NY; get = (a,b) => d.u8[a + NX*(b + NY*iz)]; }
  const rgba = new Uint8Array(wpx * hpx * 4);
  for (let b = 0; b < hpx; b++)
    for (let a = 0; a < wpx; a++) {
      const t = norm01(d, r, get(a, b));
      const ci = Math.round(t * 255) * 3, o = (b * wpx + a) * 4;
      rgba[o] = lut[ci]; rgba[o+1] = lut[ci+1]; rgba[o+2] = lut[ci+2]; rgba[o+3] = 245;
    }
  const tex = new THREE.DataTexture(rgba, wpx, hpx, THREE.RGBAFormat);
  tex.needsUpdate = true;
  tex.magFilter = THREE.NearestFilter;
  return tex;
}
function updateSlices() {
  slices.x.visible = state.showX; slices.y.visible = state.showY; slices.z.visible = state.showZ;
  if (state.showX) {
    if (slices.x.material.map) slices.x.material.map.dispose();
    slices.x.material.map = sliceTexture('x');
    slices.x.material.needsUpdate = true;
    slices.x.position.x = (state.slx - 0.5) * W;
  }
  if (state.showY) {
    if (slices.y.material.map) slices.y.material.map.dispose();
    slices.y.material.map = sliceTexture('y');
    slices.y.material.needsUpdate = true;
    slices.y.position.z = (state.sly - 0.5) * D;
  }
  if (state.showZ) {
    if (slices.z.material.map) slices.z.material.map.dispose();
    slices.z.material.map = sliceTexture('z');
    slices.z.material.needsUpdate = true;
    slices.z.position.y = (state.slz - 0.5) * H;
  }
}

// ---- legend / labels ---------------------------------------------------
function updateLegend() {
  const cv = document.getElementById('cbar'), cx2 = cv.getContext('2d');
  const lut = LUTS[state.cmap];
  const img = cx2.createImageData(256, 1);
  for (let i = 0; i < 256; i++) {
    img.data[i*4] = lut[i*3]; img.data[i*4+1] = lut[i*3+1]; img.data[i*4+2] = lut[i*3+2]; img.data[i*4+3] = 255;
  }
  cv.width = 256;
  cx2.putImageData(img, 0, 0);
  const r = KIND === 'spacetime' ? globalRange[state.field] : scaleRange(state.frame, state.field);
  document.getElementById('lg-min').textContent = r.lo.toPrecision(3);
  document.getElementById('lg-max').textContent = r.hi.toPrecision(3);
  document.getElementById('lg-name').textContent = state.field;
}
function updateTimeLabel() {
  const t = FRAMES[state.frame].t;
  document.getElementById('tlabel').textContent =
    KIND === 'spacetime' ? 'spacetime: x across, t into depth'
    : 't = ' + t.toPrecision(4) + ' s  (frame ' + (state.frame + 1) + '/' + NFRAMES + ')';
}

// ---- refresh dispatch ---------------------------------------------------
function refresh(full) {
  if (KIND === 'volume') { updateIso(); updateSlices(); }
  else updateSurface();
  updateLegend();
  updateTimeLabel();
}


// ---- UI wiring -----------------------------------------------------------
const $ = id => document.getElementById(id);
$('ptitle').textContent = SIM.title;
for (const name of SIM.fields) {
  const o = document.createElement('option');
  o.value = o.textContent = name;
  $('sel-field').appendChild(o);
}
$('sel-field').onchange = e => { state.field = e.target.value; refresh(); };
$('sel-cmap').onchange = e => { state.cmap = e.target.value; refresh(); };
$('chk-auto').onchange = e => { state.autoscale = e.target.checked; refresh(); };
$('rng-height').oninput = e => { state.hscale = e.target.value / 100; refresh(); };
$('rng-iso').oninput = e => { state.iso = e.target.value / 100; refresh(); };
$('chk-iso').onchange = e => { state.showIso = e.target.checked; refresh(); };
$('chk-sx').onchange = e => { state.showX = e.target.checked; refresh(); };
$('chk-sy').onchange = e => { state.showY = e.target.checked; refresh(); };
$('chk-sz').onchange = e => { state.showZ = e.target.checked; refresh(); };
$('rng-slx').oninput = e => { state.slx = e.target.value / 100; refresh(); };
$('rng-sly').oninput = e => { state.sly = e.target.value / 100; refresh(); };
$('rng-slz').oninput = e => { state.slz = e.target.value / 100; refresh(); };
$('rng-frame').max = NFRAMES - 1;
$('rng-frame').oninput = e => { state.frame = +e.target.value; state.playing = false; syncPlay(); refresh(); };
$('sel-speed').onchange = e => { state.speed = +e.target.value; };
function syncPlay() { $('btn-play').textContent = state.playing ? 'pause' : 'play'; }
$('btn-play').onclick = () => { state.playing = !state.playing; syncPlay(); };
window.addEventListener('keydown', e => {
  if (e.code === 'Space') { e.preventDefault(); state.playing = !state.playing; syncPlay(); }
  if (e.code === 'ArrowRight') { state.frame = (state.frame + 1) % NFRAMES; refresh(); }
  if (e.code === 'ArrowLeft') { state.frame = (state.frame + NFRAMES - 1) % NFRAMES; refresh(); }
});
const mt = $('meta-table');
for (const k of Object.keys(SIM.meta)) {
  const tr = document.createElement('tr');
  const a = document.createElement('td'), b = document.createElement('td');
  a.textContent = k; b.textContent = SIM.meta[k];
  tr.appendChild(a); tr.appendChild(b);
  mt.appendChild(tr);
}

// Kind-specific panel visibility.
function hide(id) { $(id).style.display = 'none'; }
if (KIND !== 'volume') { ['row-iso','row-showiso','row-slx','row-sly','row-slz'].forEach(hide); }
if (KIND === 'volume') hide('row-height');
if (KIND === 'spacetime') { hide('playbar'); hide('row-scale'); }
if (SIM.fields.length < 2) hide('row-field');

// ---- build + main loop -----------------------------------------------------
if (KIND === 'volume') buildVolume(); else buildSurface();
syncPlay();
refresh();

function resize() {
  const w = app.clientWidth, h = app.clientHeight;
  if (renderer) renderer.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);
resize();

let acc = 0, last = performance.now();
function tick(now) {
  requestAnimationFrame(tick);
  const dt = (now - last) / 1000; last = now;
  if (state.playing && NFRAMES > 1) {
    acc += dt * 12 * state.speed;
    if (acc >= 1) {
      state.frame = (state.frame + Math.floor(acc)) % NFRAMES;
      acc -= Math.floor(acc);
      $('rng-frame').value = state.frame;
      refresh();
    }
  }
  applyCamera();
  if (renderer) renderer.render(scene, camera);
}
requestAnimationFrame(tick);

// ---- live mode: re-run the simulation with new parameters -----------
function disposeMesh(m) {
  if (!m) return;
  group.remove(m);
  if (m.geometry) m.geometry.dispose();
  if (m.material) {
    if (m.material.map) m.material.map.dispose();
    m.material.dispose();
  }
}
function loadSpec(spec) {
  SIM.frames = spec.frames; SIM.fields = spec.fields;
  SIM.dims = spec.dims; SIM.mask = spec.mask; SIM.meta = spec.meta;
  FRAMES = SIM.frames; NFRAMES = FRAMES.length;
  [NX, NY, NZ] = SIM.dims;
  cache.clear();
  MASK = SIM.mask ? b64u8(SIM.mask) : null;
  computeRanges();
  if (!SIM.fields.includes(state.field)) state.field = SIM.fields[0];
  state.frame = 0;
  if (KIND === 'volume') {
    disposeMesh(isoMesh); disposeMesh(maskMesh);
    for (const ax of ['x','y','z']) disposeMesh(slices[ax]);
    buildVolume();
  } else {
    disposeMesh(surf);
    buildSurface();
  }
  const sel = $('sel-field');
  sel.innerHTML = '';
  for (const name of SIM.fields) {
    const o = document.createElement('option');
    o.value = o.textContent = name;
    sel.appendChild(o);
  }
  sel.value = state.field;
  $('rng-frame').max = NFRAMES - 1;
  $('rng-frame').value = 0;
  const mt2 = $('meta-table');
  mt2.innerHTML = '';
  for (const k of Object.keys(SIM.meta)) {
    const tr = document.createElement('tr');
    const a = document.createElement('td'), b = document.createElement('td');
    a.textContent = k; b.textContent = SIM.meta[k];
    tr.appendChild(a); tr.appendChild(b);
    mt2.appendChild(tr);
  }
  state.playing = NFRAMES > 1; syncPlay();
  refresh();
}
if (SIM.live && Array.isArray(SIM.params) && SIM.params.length) {
  const panel = document.getElementById('panel');
  const box = document.createElement('div');
  box.id = 'liveparams';
  box.innerHTML = '<div class="mtitle">simulation parameters</div>';
  const inputs = {};
  for (const prm of SIM.params) {
    const row = document.createElement('div');
    row.className = 'row';
    const lab = document.createElement('label');
    lab.textContent = prm.label || prm.key;
    const inp = document.createElement('input');
    inp.type = 'number';
    inp.value = prm.value;
    if (prm.min !== undefined) inp.min = prm.min;
    if (prm.max !== undefined) inp.max = prm.max;
    if (prm.step !== undefined) inp.step = prm.step;
    inp.style.cssText = 'flex:1;min-width:0;background:#1a2030;color:#c8ceda;border:1px solid #2a3140;border-radius:5px;padding:2px 6px';
    inputs[prm.key] = inp;
    row.appendChild(lab); row.appendChild(inp);
    box.appendChild(row);
  }
  const btn = document.createElement('button');
  btn.textContent = 're-run simulation';
  btn.style.cssText = 'width:100%;margin-top:6px;background:#24406e;color:#dce6f8;border:1px solid #3a5a94;border-radius:6px;padding:5px 0;cursor:pointer';
  const status = document.createElement('div');
  status.style.cssText = 'color:#8a93a6;text-align:center;margin-top:4px;min-height:14px';
  btn.onclick = async () => {
    const qs = Object.keys(inputs).map(k => k + '=' + encodeURIComponent(inputs[k].value)).join('&');
    btn.disabled = true;
    status.textContent = 'running…';
    const t0 = performance.now();
    try {
      const res = await fetch(SIM.live + '?' + qs);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const spec = await res.json();
      loadSpec(spec);
      status.textContent = 'done in ' + ((performance.now() - t0) / 1000).toFixed(1) + ' s';
    } catch (e) {
      status.textContent = 'failed: ' + e.message;
    }
    btn.disabled = false;
  };
  box.appendChild(btn);
  box.appendChild(status);
  const meta = document.getElementById('meta');
  panel.insertBefore(box, meta);
  box.style.cssText = 'margin-top:10px;border-top:1px solid #2a3140;padding-top:8px';
}

// Headless test hook.
window.__viewer = { SIM, state, fieldData, surfaceNets, refresh, globalRange, loadSpec };
