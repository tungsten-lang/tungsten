// Tungsten core docs — single-file app. Data: ./docs.json (built by extract.py from core/*.w).
import { hl, renderDoc, esc, setClassIndex } from './hl.js?v=7'
import { mountRepl } from './repl.js?v=7'

const $ = (s, r = document) => r.querySelector(s)
const $$ = (s, r = document) => [...r.querySelectorAll(s)]
const view = $('#view')
let D, C = new Map(), entries = [], RAW = '', GH = ''
// core/ directories ("areas"), grouped into a handful of sections. An area
// missing here still shows up, under "More".
const SECTIONS = [
  { id: 'foundations', t: 'Foundations', d: 'The everyday surface: text, collections, numbers, time, files, concurrency and errors.', areas: ['core', 'traits', 'errors', 'io'] },
  { id: 'algebra', t: 'Algebra & number theory', d: 'Exact arithmetic, from the numeric tower to number fields, codes and cryptography.', areas: ['numeric', 'algebra', 'combinatorics', 'coding_theory', 'crypto'] },
  { id: 'analysis', t: 'Analysis & geometry', d: 'Series, certified reals, optimization, sparse solvers, dynamical systems and shape.', areas: ['calculus', 'optimization', 'sparse', 'tensor', 'dynamics', 'geometry'] },
  { id: 'data', t: 'Data & science', d: 'Probability, statistical inference and measured physics.', areas: ['probability', 'statistics', 'physics'] },
  { id: 'media', t: 'Graphics & publishing', d: 'Plots, animation, video and LaTeX.', areas: ['plot', 'animation', 'media', 'latex'] },
]
const AREA_ALIAS = { byte_array: 'core' } // two stream codecs: not worth an area of their own
const AREA_BLURB = {
  core: 'Strings, collections, numbers, tables, time, files and concurrency.',
  traits: 'Comparable, Enumerable, Printable…: shared behaviour a class mixes in.',
  errors: 'The exception hierarchy behind every raise and rescue.',
  io: 'Scientific data formats: HDF5, Parquet, Arrow, FlatBuffers, deflate.',
  numeric: 'The numeric tower: Int, BigInt, Decimal, Rational, Complex, quaternions and beyond.',
  algebra: 'Fields, polynomials, Gröbner bases, Galois groups, number fields, curves, certified computation.',
  combinatorics: 'Partitions, graphs, exact cover, polyominoes and counting.',
  coding_theory: 'Reed–Solomon and interleaved codes over finite fields, with bounds and metrics.',
  crypto: 'Hashes, MACs, ciphers and key derivation.',
  calculus: 'Formal power series, Taylor jets, certified transcendentals and quadrature.',
  optimization: 'L-BFGS, least squares and root finding, with explicit criteria and results.',
  sparse: 'Iterative sparse solvers, preconditioners and diagnostics.',
  tensor: 'CP and Tucker tensor decompositions.',
  dynamics: 'Flows, maps, Hamiltonian systems and chaos diagnostics.',
  geometry: 'Polygons, meshes, tilings, wallpaper groups, metrics and curvature.',
  probability: 'Distributions, samplers, random streams and stochastic processes.',
  statistics: 'Summaries, regression, robust estimation, resampling and sequential inference.',
  physics: 'Finite-volume PDE solvers, gas dynamics and measurements with uncertainty.',
  plot: 'Plot scenes: axes, curves, vector fields, layout and style.',
  animation: 'Timelines, keyframes, cameras and verified animation tracks.',
  media: 'Video encode, decode, scale, mux and timecode.',
  latex: 'LaTeX math and document profiles for arXiv, IEEE, ACM and theses.',
}
const MORE = { id: 'more', t: 'More', d: 'Areas not yet filed under a section.', areas: [] }
const secOf = (area) => SECTIONS.find((s) => s.areas.includes(area)) || MORE
const secIdx = (sec) => { const i = SECTIONS.indexOf(sec); return i < 0 ? 6 : i + 1 }
const areasOf = (sec) => sec === MORE ? [...new Set(D.classes.map((c) => c.area))].filter((a) => secOf(a) === MORE) : sec.areas.filter((a) => D.classes.some((c) => c.area === a))
const allSections = () => [...SECTIONS, MORE].filter((s) => areasOf(s).length)
const AREA_NAME = { io: 'IO', latex: 'LaTeX' }
const nice = (a) => AREA_NAME[a] || a.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase())
const STARTERS = ['String', 'Array', 'Hash', 'Int', 'Float', 'Range', 'Rational', 'Complex', 'Duration', 'Date', 'Quantity', 'Matrix', 'Tensor', 'Channel', 'File', 'JSON', 'Regex', 'Polynomial', 'Enumerable', 'Comparable']

// ---------- boot ----------
boot()
async function boot() {
  try {
    D = await (await fetch('./docs.json?v=7')).json()
  } catch (e) {
    view.innerHTML = `<div class="wrap"><div class="empty">Could not load docs.json — ${esc(e.message)}</div></div>`
    return
  }
  RAW = './src/' // the site hosts its own copy of the sources it documents
  GH = 'https://github.com/tungsten-lang/tungsten/blob/main/'
  for (const c of D.classes) { c.methods ||= []; c.area = AREA_ALIAS[c.area] || c.area; C.set(c.name, c) }
  setClassIndex(C)
  buildEntries()
  buildSidebar()
  wire()
  route()
}

const isErr = (c) => /Error$|Exception$/.test(c.name) || /Error$|Exception$/.test(c.parent || '')
const base = (n) => (n || '').replace(/<.*/, '')
const mkey = (m) => (m.c ? '.' : '') + m.n
const chref = (n) => `#/c/${encodeURIComponent(n)}`
const src = (f, l) => `#/src/${f}${l ? '/L' + l : ''}`
const mhref = (cn, m) => `#/c/${encodeURIComponent(cn)}/m/${encodeURIComponent(mkey(m))}`
const firstLine = (d, name = '') => {
  if (!d) return ''
  const paras = d.split(/\n\s*\n/).map((p) => p.replace(/\s+/g, ' ').trim()).filter((p) => p && !/^([-=─@]|https?:)/i.test(p))
  let p = paras.find((x) => x.toLowerCase().replace(/ (trait|class)$/, '') !== name.toLowerCase() && x.length > 12) || ''
  if (name) p = p.replace(new RegExp('^' + name + '\\s*(?:—|–|-|:)\\s*', 'i'), '')
  const s = p.match(/^.{20,}?[.!?](?=\s|$)/)
  return (s ? s[0] : p).slice(0, 200).replace(/^./, (c) => c.toUpperCase())
}

function buildEntries() {
  for (const c of D.classes) {
    entries.push({ k: isErr(c) ? 'error' : c.kind, name: c.name, l: c.name.toLowerCase(), cl: '', doc: (c.doc || '').toLowerCase(), raw: c.doc || '', href: chref(c.name), area: c.area, w: 18 + Math.min(12, c.methods.length / 8) })
    for (const m of c.methods) {
      if (m.n.startsWith('__')) continue
      entries.push({ k: 'method', name: m.n, cls: c.name, sep: m.c ? '.' : '#', sig: m.p, l: m.n.toLowerCase(), cl: c.name.toLowerCase(), doc: (m.d || '').toLowerCase(), raw: m.d || '', href: mhref(c.name, m), area: c.area, w: (m.d ? 6 : 0) + (m.x ? 3 : 0) - (m.a ? 1 : 0) })
    }
  }
  D.functions.forEach((m, i) => entries.push({ k: 'fn', name: m.n, sig: m.p, l: m.n.toLowerCase(), cl: '', doc: (m.d || '').toLowerCase(), raw: m.d || '', href: `#/functions/${encodeURIComponent(m.n)}`, area: m.f.replace(/^core\//, ''), w: m.d ? 4 : 0 }))
  for (const [p, t] of D.gallery) entries.push({ k: 'example', name: p.replace(/^doc\/examples\//, ''), l: p.toLowerCase(), cl: '', doc: (t || '').toLowerCase(), raw: t || '', href: `#/examples/${encodeURIComponent(p)}`, area: 'examples', w: 0 })
}

// ---------- search ----------
function search(q, limit = 60, kind = '') {
  q = q.trim()
  let area = ''
  q = q.replace(/\bkind:(\w+)/i, (_, k) => { kind = k.toLowerCase(); return '' }).replace(/\bin:([\w/]+)/i, (_, a) => { area = a.toLowerCase(); return '' }).trim()
  if (kind === 'class') kind = 'class'; if (kind === 'function') kind = 'fn'
  let qual = null
  const qm = q.match(/^([A-Za-z_]\w*)\s*(?:#|\.|::)\s*([^\s]*)$/)
  if (qm && /^[A-Z]/.test(qm[1])) qual = [qm[1].toLowerCase(), qm[2].toLowerCase()]
  const toks = q.toLowerCase().split(/\s+/).filter(Boolean)
  if (!toks.length && !kind && !area) return []
  const out = []
  for (const e of entries) {
    if (kind && e.k !== kind && !(kind === 'class' && e.k === 'error')) continue
    if (area && !(e.area || '').startsWith(area)) continue
    let s = 0
    if (qual) {
      if (e.k !== 'method' || !e.cl.startsWith(qual[0]) || !e.l.includes(qual[1])) continue
      s = 60 + (e.cl === qual[0] ? 40 : 0) + (e.l === qual[1] ? 40 : e.l.startsWith(qual[1]) ? 20 : 0)
    } else {
      let ok = true
      for (const t of toks) {
        let ts = 0
        if (e.l === t) ts = 100
        else if (e.l.startsWith(t)) ts = 72 - Math.min(22, e.l.length - t.length)
        else if (e.l.includes(t)) ts = 42
        else if (e.cl && e.cl === t) ts = 46
        else if (e.cl && e.cl.includes(t)) ts = 24
        else if (e.doc.includes(t)) ts = 10 + (e.doc.startsWith(t) ? 3 : 0)
        else { ok = false; break }
        s += ts
      }
      if (!ok) continue
      if (toks.length > 1 && e.doc.includes(toks.join(' '))) s += 25
    }
    out.push([s + e.w, e])
  }
  if (!out.length && toks.length === 1 && toks[0].length > 2) { // fuzzy subsequence on names
    const t = toks[0]
    for (const e of entries) {
      if (kind && e.k !== kind) continue
      let i = 0; for (const ch of e.l) if (ch === t[i]) i++
      if (i === t.length) out.push([30 - e.l.length / 4 + e.w, e])
    }
  }
  out.sort((a, b) => b[0] - a[0] || a[1].l.length - b[1].l.length)
  return out.slice(0, limit).map((x) => x[1])
}
function mark(text, toks) {
  let h = esc(text)
  for (const t of toks) if (t.length > 1) h = h.replace(new RegExp(`(${t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})(?![^<]*>)`, 'ig'), '<mark>$1</mark>')
  return h
}
function snippetFor(e, toks) {
  if (!e.raw) return ''
  const flat = e.raw.replace(/\s+/g, ' ')
  let at = -1
  for (const t of toks) { at = flat.toLowerCase().indexOf(t); if (at >= 0) break }
  const start = Math.max(0, at < 0 ? 0 : at - 50)
  return (start ? '…' : '') + flat.slice(start, start + 170)
}
function resHTML(e, toks, sel) {
  const nm = e.k === 'method' ? `<i>${esc(e.cls)}${e.sep}</i>${mark(e.name, toks)}<i>${esc((e.sig || '').slice(0, 40))}</i>` : mark(e.name, toks) + (e.k === 'fn' ? `<i>${esc((e.sig || '').slice(0, 40))}</i>` : '')
  const sn = snippetFor(e, toks)
  return `<a class="res${sel ? ' sel' : ''}" href="${e.href}"><span class="kind ${e.k}">${e.k}</span><span><span class="nm">${nm}</span>${sn ? `<span class="sn">${mark(sn, toks)}</span>` : ''}</span><span class="ar">${esc(e.area || '')}</span></a>`
}
const qtoks = (q) => q.replace(/\b(kind|in):\S+/gi, '').toLowerCase().split(/[\s#.:]+/).filter(Boolean)

// palette
let palSel = 0, palItems = []
function openPal(q = '') {
  $('#pal').classList.add('on'); const i = $('#palq'); i.value = q; i.focus(); runPal()
}
function closePal() { $('#pal').classList.remove('on') }
function runPal() {
  const q = $('#palq').value
  palItems = search(q, 14); palSel = 0
  const box = $('#palres')
  if (!q.trim()) {
    const picks = STARTERS.filter((n) => C.has(n)).slice(0, 8)
    box.innerHTML = `<div class="empty" style="padding:18px 14px;text-align:left"><div class="group" style="margin-top:0">Jump to</div><div class="chips" style="margin:0">${picks.map((n) => `<a class="chip" href="${chref(n)}">${n}</a>`).join('')}<a class="chip" href="#/random">🎲 <em>random method</em></a><a class="chip" href="#/repl">▶ <em>REPL</em></a></div></div>`
    return
  }
  box.innerHTML = palItems.length ? palItems.map((e, i) => resHTML(e, qtoks(q), i === 0)).join('') : `<div class="empty">Nothing matches <b>${esc(q)}</b>. Full-text covers every doc comment in <code>core/</code>.</div>`
}
function movePal(d) {
  const els = $$('#palres .res'); if (!els.length) return
  els[palSel]?.classList.remove('sel'); palSel = (palSel + d + els.length) % els.length
  els[palSel].classList.add('sel'); els[palSel].scrollIntoView({ block: 'nearest' })
}

// ---------- sidebar ----------
function buildSidebar() {
  const by = {}
  for (const c of D.classes) (by[c.area] ||= []).push(c)
  const link = (c) => `<a href="${chref(c.name)}" data-n="${esc(c.name.toLowerCase())}" title="${esc(c.name)}"><span class="dot ${c.kind === 'trait' ? 'trait' : isErr(c) ? 'err' : ''}"></span>${esc(c.name)}<b>${c.methods.length || ''}</b></a>`
  $('#classlist').innerHTML = allSections().map((sec) => `<div class="sg" style="--sc:var(--s${secIdx(sec)})"><div class="sgh">${esc(sec.t)}</div>${areasOf(sec).map((a) =>
    `<details data-area="${a}"><summary><span>${esc(nice(a))}</span><i>${by[a].length}</i></summary>${by[a].map(link).join('')}</details>`).join('')}</div>`).join('')
  $('#sidefilter').placeholder = `Filter ${D.classes.length.toLocaleString()} classes…`
  $('#sidefilter').addEventListener('input', (ev) => {
    const q = ev.target.value.trim().toLowerCase()
    for (const d of $$('#classlist details')) {
      let n = 0
      for (const a of $$('a', d)) { const on = !q || a.dataset.n.includes(q); a.style.display = on ? '' : 'none'; n += on }
      d.style.display = n ? '' : 'none'
      d.open = q ? n > 0 && n < 60 : !!$('a.on', d)
    }
    for (const g of $$('#classlist .sg')) g.style.display = $$('details', g).some((d) => d.style.display !== 'none') ? '' : 'none'
  })
}
function markSide(name) {
  $$('#classlist a.on').forEach((a) => a.classList.remove('on'))
  if (!name) return
  const a = $(`#classlist a[href="${chref(name)}"]`)
  if (a) { a.closest('details').open = true; a.classList.add('on'); a.scrollIntoView({ block: 'nearest' }) }
}

// ---------- routing ----------
function route() {
  const parts = location.hash.replace(/^#\/?/, '').split('/').map(decodeURIComponent)
  const [r, a, b, c] = parts
  document.body.classList.remove('menu')
  document.body.classList.toggle('noside', r === 'repl' || r === 'tree')
  $$('#top nav a').forEach((n) => n.classList.toggle('on', n.dataset.nav === (r === 'c' ? 'browse' : r || 'home')))
  markSide(r === 'c' ? a : null)
  cancelAnimationFrame(heroRaf)
  if (!r) home()
  else if (r === 'c' && C.has(a)) classView(C.get(a), b === 'm' ? c : null)
  else if (r === 'browse') browse(a)
  else if (r === 'tree') tree()
  else if (r === 'functions') functionsView(a)
  else if (r === 'examples') examples(parts.slice(1).join('/'))
  else if (r === 'repl') { view.innerHTML = ''; mountRepl(view, parts.slice(1).join('/')); document.title = 'REPL · Tungsten' }
  else if (r === 'search') searchView(parts.slice(1).join('/'))
  else if (r === 'src') sourceView(parts.slice(1))
  else if (r === 'random') { const ms = entries.filter((e) => e.k === 'method' && e.raw); location.replace(ms[Math.random() * ms.length | 0].href); return }
  else view.innerHTML = `<div class="wrap"><div class="empty"><h1>Nothing here</h1><p>No class named <code>${esc(a || r)}</code>. Try the <a href="#/browse">class index</a> or press <kbd>/</kbd>.</p></div></div>`
  if (!(r === 'c' && b === 'm') && r !== 'src') scrollTo(0, 0)
}
const footer = () => `<footer><span>Generated from <a href="https://github.com/tungsten-lang/tungsten/tree/main/core">core/</a> @ <code>${esc(D.meta.sha.slice(0, 9))}</code>${D.meta.note ? ' · ' + esc(D.meta.note) : ''}</span><span>${D.meta.files} files · ${D.meta.lines.toLocaleString()} lines</span><span class="r"><kbd>/</kbd> search · <kbd>r</kbd> random · <kbd>t</kbd> theme</span></footer>`

// ---------- home ----------
let heroRaf = 0
function home() {
  document.title = 'Tungsten core docs · The Native Language of Agents'
  const m = D.meta
  const documented = D.classes.reduce((n, c) => n + c.methods.filter((x) => x.d).length, 0)
  view.innerHTML = `
  <div class="hero"><canvas id="fil"></canvas><div class="in">
    <div class="eyebrow">Tungsten · standard library reference</div>
    <h1>The Native Language of <em>Agents</em></h1>
    <p class="lede">Models write pseudocode. Tungsten runs it.</p>
    <p>Every class, trait and method in <code>core/</code>: searchable down to the doc comments, with the real source one click away, usage pulled from the spec suite, and a REPL that runs Tungsten as WebAssembly.</p>
    <div class="cta"><button class="btn hot" id="herosearch">Search the library <kbd style="background:rgba(0,0,0,.12);border-color:rgba(0,0,0,.25);color:inherit">⌘K</kbd></button><a class="btn" href="#/repl">▶ Open the REPL</a><a class="btn" href="#/browse">Browse by section</a></div>
    <div class="stats">${[[m.classes - m.traits, 'classes'], [m.methods, 'methods'], [documented, 'doc comments'], [m.examples, 'spec examples'], [m.lines, 'lines of .w']].map(([n, l]) => `<div class="stat"><b data-n="${n}">0</b><span>${l}</span></div>`).join('')}</div>
  </div></div>
  <div class="wide">
  <section><div class="sh"><h2>Map of <code class="h">core/</code></h2><p>every class, sized by method count. Click a section or area to zoom in.</p></div>
    <div id="tmbar"></div><div id="tmap" class="tmap"></div><div id="tmtip" class="tmtip"></div></section>
  <section><div class="sh"><h2>Start here</h2><p>the classes you'll touch in the first hour</p></div>
    <div class="grid">${STARTERS.filter((n) => C.has(n)).map((n) => cardFor(C.get(n))).join('')}</div></section>
  <section><div class="sh"><h2>Sections</h2><p>${D.classes.length.toLocaleString()} classes in ${allSections().length} sections</p></div>${sectionsHTML()}</section>
  <section><div class="sh"><h2>Method roulette</h2><p class="r"><button class="btn sm" id="reroll">🎲 another</button></p></div><div id="roulette"></div></section>
  ${footer()}</div>`
  $('#herosearch').onclick = () => openPal()
  $('#reroll').onclick = roulette; roulette()
  countUp(); filament($('#fil')); treemap()
}
function sectionsHTML() {
  return `<div class="secs">${allSections().map((sec) => {
    const as = areasOf(sec), cs = D.classes.filter((c) => as.includes(c.area))
    return `<div class="sec" style="--sc:var(--s${secIdx(sec)})"><div class="sech"><h3>${esc(sec.t)}</h3><span>${cs.length} classes · ${cs.reduce((n, c) => n + c.methods.length, 0).toLocaleString()} methods</span></div><p>${esc(sec.d)}</p>
      <div class="arealist">${as.map((a) => { const n = D.classes.filter((c) => c.area === a).length; return `<a href="#/browse/${a}"><b>${esc(nice(a))}</b><span>${esc(AREA_BLURB[a] || '')}</span><i>${n}</i></a>` }).join('')}</div></div>`
  }).join('')}</div>`
}

// Squarified treemap (Bruls, Huizing & van Wijk 2000) of sections > areas > classes.
let tmFocus = null
function squarify(items, x, y, w, h) {
  const out = [], total = items.reduce((s, i) => s + i.v, 0)
  if (!total || w <= 0 || h <= 0) return out
  const k = w * h / total
  let rest = items.map((i) => ({ i, a: i.v * k }))
  const worst = (row, side) => { let sum = 0, mx = 0, mn = Infinity; for (const r of row) { sum += r.a; mx = Math.max(mx, r.a); mn = Math.min(mn, r.a) } return Math.max(side * side * mx / (sum * sum), sum * sum / (side * side * mn)) }
  while (rest.length) {
    const side = Math.min(w, h)
    let row = [rest[0]], best = worst(row, side)
    for (let j = 1; j < rest.length; j++) { const cand = row.concat(rest[j]), ws = worst(cand, side); if (ws > best) break; row = cand; best = ws }
    const sum = row.reduce((s, r) => s + r.a, 0)
    if (w >= h) { const cw = sum / h; let yy = y; for (const r of row) { const rh = r.a / cw; out.push({ ...r.i, x, y: yy, w: cw, h: rh }); yy += rh } x += cw; w -= cw }
    else { const rh = sum / w; let xx = x; for (const r of row) { const rw = r.a / rh; out.push({ ...r.i, x: xx, y, w: rw, h: rh }); xx += rw } y += rh; h -= rh }
    rest = rest.slice(row.length)
  }
  return out
}
function treemap() {
  const box = $('#tmap'); if (!box) return
  const W = box.clientWidth, H = box.clientHeight
  const secs = allSections().filter((s) => !tmFocus || tmFocus.sec === s)
  const tree = secs.map((sec) => {
    const areas = areasOf(sec).filter((a) => !tmFocus?.area || tmFocus.area === a).map((a) => {
      const cs = D.classes.filter((c) => c.area === a).map((c) => ({ c, v: Math.max(1, c.methods.length) })).sort((p, q) => q.v - p.v)
      return { a, cs, v: cs.reduce((n, x) => n + x.v, 0) }
    }).sort((p, q) => q.v - p.v)
    return { sec, areas, v: areas.reduce((n, x) => n + x.v, 0) }
  }).sort((p, q) => q.v - p.v)
  let html = ''
  const one = tree.length === 1
  for (const S of squarify(tree, 0, 0, W, H)) {
    const n = secIdx(S.sec), hs = one ? 0 : S.h > 40 && S.w > 70 ? 20 : 0
    if (!one) html += `<button class="tm-s" data-sec="${S.sec.id}" style="--sc:var(--s${n});left:${S.x}px;top:${S.y}px;width:${S.w}px;height:${S.h}px">${hs ? `<span>${esc(S.sec.t)}</span>` : ''}</button>`
    const oneA = S.areas.length === 1
    for (const A of squarify(S.areas, S.x + 2, S.y + hs + 2, S.w - 4, S.h - hs - 4)) {
      const ha = !oneA && A.h > 34 && A.w > 56 ? 16 : 0
      if (!oneA) html += `<button class="tm-a" data-area="${A.a}" style="--sc:var(--s${n});left:${A.x}px;top:${A.y}px;width:${A.w}px;height:${A.h}px">${ha ? `<span>${esc(nice(A.a))}</span>` : ''}</button>`
      const max = A.cs[0]?.v || 1
      for (const K of squarify(A.cs, A.x + 1, A.y + ha + 1, A.w - 2, A.h - ha - 2)) {
        const t = Math.log(K.v + 1) / Math.log(max + 1), lab = K.w > 46 && K.h > 15
        html += `<a class="tm-c" href="${chref(K.c.name)}" data-n="${esc(K.c.name)}" style="left:${K.x}px;top:${K.y}px;width:${Math.max(0, K.w - 1)}px;height:${Math.max(0, K.h - 1)}px;background:color-mix(in srgb, var(--s${n}) ${Math.round(16 + t * 50)}%, var(--panel))">${lab ? `<span style="font-size:${Math.min(13, Math.max(9.5, Math.sqrt(K.w * K.h) / 7))}px">${esc(K.c.name)}</span>` : ''}</a>`
      }
    }
  }
  box.innerHTML = html
  const crumbs = [['', 'core/'], ...(tmFocus ? [[tmFocus.sec.id, tmFocus.sec.t]] : []), ...(tmFocus?.area ? [['@' + tmFocus.area, nice(tmFocus.area)]] : [])]
  $('#tmbar').innerHTML = `<div class="tmcrumbs">${crumbs.map(([k, l], i) => i < crumbs.length - 1 ? `<button data-go="${k}">${esc(l)}</button><span>›</span>` : `<b>${esc(l)}</b>`).join('')}</div>
    <div class="tmlegend">${allSections().map((s) => `<button data-go="${s.id}" style="--sc:var(--s${secIdx(s)})"><i></i>${esc(s.t)}</button>`).join('')}</div>`
  if (box.dataset.wired) return
  box.dataset.wired = 1
  const go = (k) => { $('#tmtip').classList.remove('on'); tmFocus = !k ? null : k[0] === '@' ? { sec: secOf(k.slice(1)), area: k.slice(1) } : { sec: allSections().find((s) => s.id === k) }; treemap() }
  $('#tmbar').onclick = (e) => { const b = e.target.closest('[data-go]'); if (b) go(b.dataset.go) }
  box.onclick = (e) => { const b = e.target.closest('.tm-s, .tm-a'); if (b) go(b.dataset.sec || '@' + b.dataset.area) }
  const tip = $('#tmtip')
  box.onpointermove = (e) => {
    const el = e.target.closest('.tm-c, .tm-a, .tm-s'); if (!el) { tip.classList.remove('on'); return }
    let h
    if (el.dataset.n) { const c = C.get(el.dataset.n); h = `<b>${esc(c.name)}</b><span>${esc(nice(c.area))} · ${c.methods.length} methods</span>${c.doc ? `<p>${esc(firstLine(c.doc, c.name))}</p>` : ''}` }
    else if (el.dataset.area) { const a = el.dataset.area; h = `<b>${esc(nice(a))}</b><span>${D.classes.filter((c) => c.area === a).length} classes · click to zoom</span><p>${esc(AREA_BLURB[a] || '')}</p>` }
    else { const s = allSections().find((x) => x.id === el.dataset.sec); h = `<b>${esc(s.t)}</b><span>click to zoom</span><p>${esc(s.d)}</p>` }
    tip.innerHTML = h; tip.classList.add('on')
    const r = box.parentNode.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top
    tip.style.left = Math.min(x + 14, r.width - tip.offsetWidth - 4) + 'px'; tip.style.top = (y + 18) + 'px'
  }
  box.onpointerleave = () => tip.classList.remove('on')
  let t; new ResizeObserver(() => { clearTimeout(t); t = setTimeout(() => box.isConnected && treemap(), 120) }).observe(box)
}
function cardFor(c) {
  return `<a class="card" href="${chref(c.name)}"><span class="n">${c.methods.length}</span><h3>${esc(c.name)}</h3><p>${esc(firstLine(c.doc, c.name) || (c.parent ? 'Subclass of ' + c.parent + '.' : c.files[0][0]))}</p></a>`
}
function roulette() {
  const ms = entries.filter((e) => e.k === 'method' && e.raw.length > 60)
  const e = ms[Math.random() * ms.length | 0]
  $('#roulette').innerHTML = `<a class="card" href="${e.href}" style="padding:20px"><h3 style="font-size:17px"><span style="color:var(--mute)">${esc(e.cls)}${e.sep}</span>${esc(e.name)}<span style="color:var(--mute);font-weight:400">${esc(e.sig || '')}</span></h3><p style="-webkit-line-clamp:7;font-size:14px;margin-top:8px">${esc(e.raw.replace(/\s+/g, ' '))}</p></a>`
}
function countUp() {
  const t0 = performance.now()
  const tick = (t) => {
    const p = Math.min(1, (t - t0) / 1100), ease = 1 - Math.pow(1 - p, 4)
    $$('.stat b').forEach((b) => b.textContent = Math.round(b.dataset.n * ease).toLocaleString())
    if (p < 1) requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
}
// A glowing coiled filament; heats up as the pointer approaches.
function filament(cv) {
  const ctx = cv.getContext('2d'), still = matchMedia('(prefers-reduced-motion: reduce)').matches
  let w, h, heat = .35, target = .35, sparks = []
  const fit = () => { const r = cv.getBoundingClientRect(), d = Math.min(2, devicePixelRatio || 1); w = r.width; h = r.height; cv.width = w * d; cv.height = h * d; ctx.setTransform(d, 0, 0, d, 0, 0) }
  fit(); addEventListener('resize', fit)
  cv.parentNode.addEventListener('pointermove', (e) => { const r = cv.getBoundingClientRect(); const dx = (e.clientX - r.left) / w - .72, dy = (e.clientY - r.top) / h - .5; target = Math.max(.3, 1.15 - Math.hypot(dx * 1.6, dy) * 1.6) })
  cv.parentNode.addEventListener('pointerleave', () => target = .35)
  const light = () => document.documentElement.dataset.theme === 'light'
  const draw = (t) => {
    heat += (target - heat) * .04
    document.documentElement.style.setProperty('--heat', heat.toFixed(3))
    ctx.clearRect(0, 0, w, h)
    const x0 = w * .58, x1 = w * .98, cy = h * .5, turns = 15, amp = Math.min(h * .2, 70)
    const flick = .88 + .12 * Math.sin(t / 90) * Math.sin(t / 37)
    const pts = []
    for (let i = 0; i <= 420; i++) { const u = i / 420, a = u * turns * Math.PI * 2 + t / 2600; pts.push([x0 + (x1 - x0) * u + Math.cos(a) * 9, cy + Math.sin(a) * amp * Math.sin(u * Math.PI) ** .6, Math.cos(a)]) }
    for (const pass of [0, 1]) { // back half, then front half
      for (const [lw, al, col] of [[16, .07, '232,140,20'], [7, .16, '245,180,70'], [2.4, .95, light() ? '168,101,10' : '255,236,200']]) {
        ctx.beginPath(); let pen = false
        for (const [x, y, z] of pts) { if ((z > 0) === !!pass) { pen ? ctx.lineTo(x, y) : ctx.moveTo(x, y); pen = true } else pen = false }
        ctx.lineWidth = lw * (pass ? 1 : .7); ctx.strokeStyle = `rgba(${col},${al * heat * flick * (pass ? 1 : .45)})`; ctx.lineCap = 'round'; ctx.stroke()
      }
    }
    if (!still && Math.random() < heat * .5) { const p = pts[Math.random() * pts.length | 0]; sparks.push({ x: p[0], y: p[1], vx: (Math.random() - .5) * .5, vy: -.3 - Math.random() * .9, a: 1 }) }
    sparks = sparks.filter((s) => s.a > .02)
    for (const s of sparks) { s.x += s.vx; s.y += s.vy; s.a *= .975; ctx.fillStyle = `rgba(245,${170 + s.a * 70 | 0},80,${s.a * .8})`; ctx.fillRect(s.x, s.y, 1.6, 1.6) }
    if (!still && cv.isConnected) heroRaf = requestAnimationFrame(draw)
  }
  heroRaf = requestAnimationFrame(draw)
}

// ---------- class page ----------
function ancestors(c) { const out = []; let p = base(c.parent), g = 0; while (p && g++ < 20) { out.push(p); p = base(C.get(p)?.parent) } return out }
function classView(c, focus) {
  document.title = `${c.name} · Tungsten`
  const anc = ancestors(c)
  const use = c.auto ? null : c.files[0][0].replace(/\.w$/, '')
  const cls = c.methods.filter((m) => m.c).length, inst = c.methods.length - cls
  view.innerHTML = `<div class="wrap">
    <div class="crumbs"><a href="#/browse">library</a><span class="sep">›</span><a href="#/browse/${c.area}">${esc(nice(c.area))}</a>${anc.slice().reverse().map((a) => `<span class="sep">›</span>${C.has(a) ? `<a href="${chref(a)}">${esc(a)}</a>` : esc(a)}`).join('')}<span class="sep">›</span><span style="color:var(--ink)">${esc(c.name)}</span></div>
    <div class="title"><h1>${esc(c.name)}<span class="g">${esc(c.generic || '')}</span></h1><span class="kind ${isErr(c) ? 'error' : c.kind}">${isErr(c) ? 'error' : c.kind}</span></div>
    <div class="chips">
      ${c.parent ? `<span class="chip"><em>&lt;</em> ${linkType(c.parent)}</span>` : ''}
      ${(c.traits || []).map((t) => `<a class="chip" href="${chref(t)}"><em>is</em> ${esc(t)}</a>`).join('')}
      ${c.outer ? `<a class="chip" href="${chref(c.outer)}"><em>nested in</em> ${esc(c.outer)}</a>` : ''}
      ${c.auto ? `<span class="chip" title="Registered in core/tungsten.w — available with no use line">⚡ autoloaded</span>` : `<span class="chip copy" data-copy="use ${esc(use)}" title="Click to copy"><em>use</em> ${esc(use.replace(/^core\//, 'core/'))} ⧉</span>`}
      ${c.files.map(([f, l]) => `<a class="chip" href="${src(f, l)}">${esc(f)}<em>:${l}</em></a>`).join('')}
    </div>
    <div class="doc">${renderDoc(c.doc)}</div>
    ${c.layout ? `<div class="doc"><h4>Memory layout</h4><pre>${hl(c.layout)}</pre></div>` : ''}
    ${c.consts ? `<div class="doc"><h4>Constants</h4><dl class="kv">${c.consts.map(([k, v]) => `<dt>${esc(k)}</dt><dd title="${esc(v)}">${hl(v)}</dd>`).join('')}</dl></div>` : ''}
    ${c.fields ? `<div class="doc"><h4>Fields</h4><dl class="kv">${c.fields.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${hl(v)}</dd>`).join('')}</dl></div>` : ''}
    ${c.children ? `<div class="doc"><h4>Subclasses</h4><div class="chips" style="margin:0">${c.children.map((n) => `<a class="chip" href="${chref(n)}">${esc(n)}</a>`).join('')}</div></div>` : ''}
    ${c.kind === 'trait' ? conformers(c) : ''}
    ${c.methods.length ? `<div class="toolbar"><h2>Methods</h2><input id="mfilter" placeholder="Filter ${c.methods.length} methods…" spellcheck="false" autocomplete="off">
      <div class="seg" id="mseg"><button class="on" data-f="all">all ${c.methods.length}</button>${cls ? `<button data-f="cls">.class ${cls}</button><button data-f="inst">#instance ${inst}</button>` : ''}${c.methods.some((m) => m.acc) ? `<button data-f="acc">ro/rw ${c.methods.filter((m) => m.acc).length}</button>` : ''}<button data-f="doc">documented</button></div>
      <button class="btn sm" id="expall">expand all</button></div><div id="mlist"></div>` : ''}
    ${inherited(c, anc)}
    ${c.specs ? `<div class="doc"><h4>Exercised by</h4><div class="chips" style="margin:0">${c.specs.map((s) => `<a class="chip" href="${src(s)}">${esc(s.replace(/^spec\//, ''))}</a>`).join('')}</div></div>` : ''}
    ${footer()}</div>`
  if (c.methods.length) {
    let f = 'all'
    const draw = () => drawMethods(c, $('#mfilter').value.trim().toLowerCase(), f)
    $('#mfilter').oninput = draw
    $('#mseg').onclick = (ev) => { const b = ev.target.closest('button'); if (!b) return; f = b.dataset.f; $$('#mseg button').forEach((x) => x.classList.toggle('on', x === b)); draw() }
    $('#expall').onclick = () => { const all = $$('.m'); const open = all.some((m) => !m.classList.contains('open')); all.slice(0, 80).forEach((m) => toggleMethod(m, c, open)) }
    draw()
    if (focus) focusMethod(c, focus)
  }
}
const linkType = (t) => { const b = base(t); return C.has(b) ? `<a href="${chref(b)}">${esc(t)}</a>` : esc(t) }
function conformers(t) {
  const list = D.classes.filter((c) => (c.traits || []).includes(t.name))
  return list.length ? `<div class="doc"><h4>Implemented by ${list.length}</h4><div class="chips" style="margin:0">${list.map((c) => `<a class="chip" href="${chref(c.name)}">${esc(c.name)}</a>`).join('')}</div></div>` : ''
}
function inherited(c, anc) {
  const own = new Set(c.methods.map(mkey)), seen = new Set(), blocks = []
  const srcs = [...(c.traits || []).map((t) => ['is', t]), ...anc.flatMap((a) => [['<', a], ...((C.get(a)?.traits) || []).map((t) => ['is', t])])]
  for (const [rel, n] of srcs) {
    const p = C.get(n); if (!p || seen.has(n)) continue; seen.add(n)
    const ms = p.methods.filter((m) => !own.has(mkey(m)) && !m.n.startsWith('__'))
    if (ms.length) blocks.push(`<details><summary>${rel === 'is' ? 'from trait' : 'inherited from'} <a href="${chref(n)}">${esc(n)}</a> <span style="color:var(--mute)">· ${ms.length}</span></summary><div class="ml">${ms.map((m) => `<a href="${mhref(n, m)}">${m.c ? '.' : ''}${esc(m.n)}</a>`).join('')}</div></details>`)
  }
  return blocks.length ? `<div class="inh"><div class="group">Inherited</div>${blocks.join('')}</div>` : ''
}
function drawMethods(c, q, f) {
  let last = null, html = '', n = 0
  c.methods.forEach((m, i) => {
    if (q && !(m.n.toLowerCase().includes(q) || (m.d || '').toLowerCase().includes(q))) return
    if ((f === 'cls' && !m.c) || (f === 'inst' && m.c) || (f === 'doc' && !m.d) || (f === 'acc' && !m.acc)) return
    if ((m.s || '') !== last && (m.s || last !== null)) { html += `<div class="group">${esc(m.s || 'more')}</div>` }
    last = m.s || ''
    n++
    html += `<div class="m" id="m-${i}" data-i="${i}"><button class="mh"><span class="sig">${m.c ? '<span class="cm">.</span>' : ''}${esc(m.n)}<span class="p">${esc(m.p)}</span></span><span class="sum">${esc(firstLine(m.d))}</span><span class="badges">${m.t ? `<span class="bd gpu">@${m.t}</span>` : ''}${m.fn ? '<span class="bd">fn</span>' : ''}${m.b ? '<span class="bd" title="No body needed: @-parameters bind straight to fields">binds fields</span>' : ''}${m.acc ? `<span class="bd acc" title="${m.acc === 'rw' ? 'Declared with rw — reader and ' + esc(m.n) + '=(value) writer' : 'Declared with ro — read-only accessor'}">${m.acc}</span>` : ''}${m.rt ? '<span class="bd abs" title="Implemented natively by the C runtime">runtime</span>' : m.a ? '<span class="bd abs" title="No body — supplied by an intrinsic or subclass">abstract</span>' : ''}${m.x ? `<span class="bd ex">${m.x.length} ex</span>` : ''}</span></button><div class="mb"></div></div>`
  })
  $('#mlist').innerHTML = html || `<div class="empty">No methods match.</div>`
  $('#mlist').onclick = (ev) => { const h = ev.target.closest('.mh'); if (h) toggleMethod(h.parentNode, c) }
}
async function toggleMethod(el, c, force) {
  const open = force ?? !el.classList.contains('open')
  el.classList.toggle('open', open)
  if (!open || el.dataset.done) return
  el.dataset.done = 1
  const m = c.methods[el.dataset.i], body = $('.mb', el)
  body.innerHTML = `${m.d ? `<div class="mdoc">${renderDoc(m.d)}</div>` : ''}
    ${m.x ? `<div class="wild"><div class="srcbar">seen in the spec suite</div>${m.x.map(([f, l, t]) => `<div class="w"><code>${hl(t)}</code><a href="${src(f, l)}">${esc(f.split('/').pop())}:${l}</a></div>`).join('')}</div>` : ''}
    <div class="srcbar"><span>${esc(m.f)} · lines ${m.l}–${m.e}</span><span class="r"><a href="#" data-copylink="${mhref(c.name, m)}">permalink ⧉</a><a href="${src(m.f, m.l)}">whole file</a></span></div>
    <div class="srcslot"><div class="skel"></div></div>`
  $('.srcslot', body).innerHTML = await sourceHTML(m.f, m.l, m.e)
}
const files = new Map()
function loadFile(f) {
  if (!files.has(f)) files.set(f, fetch(RAW + f).then((r) => { if (!r.ok) throw new Error(r.status); return r.text() }).then((t) => t.split('\n')))
  return files.get(f)
}
async function sourceHTML(f, l, e, max = 400) {
  try {
    const lines = (await loadFile(f)).slice(l - 1, Math.min(e, l - 1 + max))
    const ind = Math.min(...lines.filter((x) => x.trim()).map((x) => x.match(/^ */)[0].length))
    return `<pre class="src" style="counter-reset: ln ${l - 1}">${hl(lines.map((x) => x.slice(ind)).join('\n')).split('\n').map((x) => `<span class="ln">${x || ' '}</span>`).join('')}</pre>`
  } catch (err) {
    files.delete(f)
    return `<div class="empty" style="padding:14px">The source for <code>${esc(f)}</code> didn't arrive (${esc(err.message)}). <a href="${GH}${f}" target="_blank" rel="noopener">Try GitHub ↗</a></div>`
  }
}
function focusMethod(c, key) {
  const i = c.methods.findIndex((m) => mkey(m) === key)
  const el = i >= 0 && $(`#m-${i}`); if (!el) return
  toggleMethod(el, c, true); el.classList.add('flash')
  setTimeout(() => el.scrollIntoView({ block: 'start', behavior: 'instant' }), 80)
}

// ---------- browse / functions / search ----------
function browse(area) {
  if (!area || !D.classes.some((c) => c.area === area)) {
    document.title = 'Library · Tungsten'
    view.innerHTML = `<div class="wide"><div class="title"><h1>Library</h1><span class="kind">${D.classes.length.toLocaleString()} classes</span></div>
      <p class="doc">The directories of <code>core/</code>, grouped into sections. Each area lists its classes; search (<kbd>/</kbd>) covers every method and doc comment.</p>
      <section style="margin-top:28px">${sectionsHTML()}</section>${footer()}</div>`
    return
  }
  const sec = secOf(area), list = D.classes.filter((c) => c.area === area)
  document.title = `${nice(area)} · Tungsten`
  view.innerHTML = `<div class="wide"><div class="crumbs"><a href="#/browse">library</a><span class="sep">›</span><span>${esc(sec.t)}</span></div>
    <div class="title"><h1>${esc(nice(area))}</h1><span class="kind">${list.length} classes</span></div>
    <p class="doc">${esc(AREA_BLURB[area] || '')}</p>
    <div class="chips">${areasOf(sec).map((a) => `<a class="chip${a === area ? ' on' : ''}" href="#/browse/${a}">${esc(nice(a))}</a>`).join('')}</div>
    <section style="margin-top:26px"><div class="grid">${list.map(cardFor).join('')}</div></section>${footer()}</div>`
}
function functionsView(focus) {
  document.title = 'Top-level functions · Tungsten'
  const by = {}
  D.functions.forEach((m, i) => (by[m.f] ||= []).push([m, i]))
  const fake = { name: 'Functions', methods: D.functions }
  view.innerHTML = `<div class="wrap"><div class="title"><h1>Functions</h1><span class="kind fn">${D.functions.length} top-level</span></div>
    <p class="doc">Free functions defined at the top level of <code>core/</code> files with <code>-&gt;</code> or the memoized <code>fn</code> — typed kernels, helpers and constructors that live outside any class.</p>
    <div id="mlist">${Object.entries(by).map(([f, ms]) => `<div class="group">${esc(f)}</div>${ms.map(([m, i]) => `<div class="m" id="m-${i}" data-i="${i}"><button class="mh"><span class="sig">${esc(m.n)}<span class="p">${esc(m.p)}</span></span><span class="sum">${esc(firstLine(m.d))}</span><span class="badges">${m.fn ? '<span class="bd">fn</span>' : ''}${m.t ? `<span class="bd gpu">@${m.t}</span>` : ''}</span></button><div class="mb"></div></div>`).join('')}`).join('')}</div>${footer()}</div>`
  $('#mlist').onclick = (ev) => { const h = ev.target.closest('.mh'); if (h) toggleMethod(h.parentNode, fake) }
  if (focus) { const i = D.functions.findIndex((m) => m.n === focus); const el = $(`#m-${i}`); if (el) { toggleMethod(el, fake, true); el.classList.add('flash'); requestAnimationFrame(() => el.scrollIntoView()) } }
}
function searchView(q) {
  document.title = `${q} · search · Tungsten`
  let kind = ''
  const kinds = [['', 'everything'], ['class', 'classes'], ['trait', 'traits'], ['method', 'methods'], ['fn', 'functions'], ['example', 'examples']]
  view.innerHTML = `<div class="wrap"><div class="title"><h1>“${esc(q)}”</h1></div><div class="toolbar" style="margin-top:18px"><div class="seg" id="kseg">${kinds.map(([k, l]) => `<button data-k="${k}" class="${k ? '' : 'on'}">${l}</button>`).join('')}</div><span id="scount" style="color:var(--mute);font:12px var(--mono)"></span></div><div class="sres" id="sres"></div>${footer()}</div>`
  const draw = () => { const r = search(q, 250, kind); $('#scount').textContent = `${r.length}${r.length === 250 ? '+' : ''} results`; $('#sres').innerHTML = r.map((e) => resHTML(e, qtoks(q))).join('') || '<div class="empty">No results.</div>' }
  $('#kseg').onclick = (ev) => { const b = ev.target.closest('button'); if (!b) return; kind = b.dataset.k; $$('#kseg button').forEach((x) => x.classList.toggle('on', x === b)); draw() }
  draw()
}

// ---------- whole-file viewer ----------
async function sourceView(parts) {
  const line = /^L\d+$/.test(parts[parts.length - 1]) ? +parts.pop().slice(1) : 0
  const path = parts.join('/')
  document.title = `${path} · Tungsten`
  const here = D.classes.filter((c) => c.files.some(([f]) => f === path))
  view.innerHTML = `<div class="wide"><div class="crumbs">${path.split('/').map((p, i, a) => i < a.length - 1 ? `<span>${esc(p)}</span><span class="sep">/</span>` : `<span style="color:var(--ink)">${esc(p)}</span>`).join('')}</div>
    ${here.length ? `<div class="chips" style="margin:0 0 14px">${here.slice(0, 40).map((c) => `<a class="chip" href="${chref(c.name)}"><em>${c.kind === 'trait' ? 'trait' : '+'}</em> ${esc(c.name)}</a>`).join('')}</div>` : ''}
    <div class="srcbar"><span>${esc(path)}</span><span class="r"><a href="${GH}${path}" target="_blank" rel="noopener">GitHub (main) ↗</a></span></div><div id="filesrc"><div class="skel" style="height:320px"></div></div>${footer()}</div>`
  let n = 1
  try { n = (await loadFile(path)).length } catch {}
  $('#filesrc').innerHTML = await sourceHTML(path, 1, n, 20000)
  const el = line && $(`#filesrc .ln:nth-child(${line})`)
  if (el) { el.classList.add('hit'); setTimeout(() => el.scrollIntoView({ block: 'center', behavior: 'instant' }), 60) }
}

// ---------- examples ----------
async function examples(path) {
  document.title = 'Examples · Tungsten'
  const g = D.gallery
  if (!path) path = (g.find(([p]) => /01-basics\/hello/.test(p)) || g[0])[0]
  const groups = {}
  for (const e of g) (groups[e[0].split('/').slice(2, -1).join('/') || 'showcase'] ||= []).push(e)
  view.innerHTML = `<div class="wide"><div class="title"><h1>Examples</h1><span class="kind example">${g.length} programs</span></div><p class="doc">Runnable programs from <code>doc/examples</code> — language tours, GPU kernels and Rosetta Code solutions. Send any of them to the REPL.</p>
    <div class="exlist" style="margin-top:22px"><div class="exnav scroll">${Object.entries(groups).map(([k, es]) => `<div class="group" style="margin:12px 13px 6px">${esc(k)}</div>${es.map(([p, t, n]) => `<a href="#/examples/${encodeURIComponent(p)}" class="${p === path ? 'on' : ''}">${esc(p.split('/').pop())}<small>${esc(t || n + ' lines')}</small></a>`).join('')}`).join('')}</div>
    <div><div class="srcbar" style="margin-top:0"><span>${esc(path)}</span><span class="r"><a href="#" id="torepl">▶ open in REPL</a><a href="${src(path)}">permalink</a></span></div><div id="excode"><div class="skel" style="height:300px"></div></div></div></div>${footer()}</div>`
  $('.exnav a.on')?.scrollIntoView({ block: 'center' })
  try {
    const lines = await loadFile(path)
    $('#excode').innerHTML = await sourceHTML(path, 1, lines.length, 2000)
    $('#torepl').onclick = (ev) => { ev.preventDefault(); sessionStash('repl:code', lines.join('\n')); location.hash = '#/repl' }
  } catch { $('#excode').innerHTML = await sourceHTML(path, 1, 1) }
}
export function sessionStash(k, v) { try { v === undefined ? sessionStorage.removeItem(k) : sessionStorage.setItem(k, v) } catch {} }

// ---------- hierarchy ----------
function tree() {
  document.title = 'Hierarchy · Tungsten'
  const kids = new Map(), nodes = new Set()
  for (const c of D.classes) if (c.parent) { const p = base(c.parent); (kids.get(p) || kids.set(p, []).get(p)).push(c.name); nodes.add(p); nodes.add(c.name) }
  const roots = [...nodes].filter((n) => !C.get(n)?.parent).sort()
  const leaves = (n) => (kids.get(n) || []).reduce((s, k) => s + leaves(k), 0) || 1
  const total = roots.reduce((s, r) => s + leaves(r), 0)
  const P = [], L = []
  const place = (n, a0, a1, d, parent) => {
    const a = (a0 + a1) / 2, r = d * 165, me = { n, a, r, x: Math.cos(a) * r, y: Math.sin(a) * r, parent, leaf: !kids.has(n) }
    P.push(me); if (parent) L.push([parent, me])
    let s = a0; const tot = leaves(n)
    for (const k of (kids.get(n) || []).sort()) { const w = (a1 - a0) * leaves(k) / tot; place(k, s, s + w, d + 1, me); s += w }
  }
  let s = -Math.PI / 2
  for (const r of roots) { const w = Math.PI * 2 * leaves(r) / total; place(r, s, s + w, 1, null); s += w }
  const link = ([p, c]) => { const mr = (p.r + c.r) / 2; return `M${p.x},${p.y}C${Math.cos(p.a) * mr},${Math.sin(p.a) * mr} ${Math.cos(c.a) * mr},${Math.sin(c.a) * mr} ${c.x},${c.y}` }
  const traits = D.classes.filter((c) => c.kind === 'trait')
  view.innerHTML = `<div class="wide"><div class="title"><h1>Hierarchy</h1><span class="kind">${nodes.size} classes in ${roots.length} families</span></div>
    <p class="doc">Every <code>+ Child &lt; Parent</code> relationship in core, radially. Hover to trace a lineage, click to open, drag to pan, scroll to zoom.</p>
    <div id="treewrap" style="margin-top:20px"><svg viewBox="-900 -900 1800 1800"><g id="tg">${L.map((l, i) => `<path class="lk" data-c="${esc(l[1].n)}" d="${link(l)}"/>`).join('')}
      ${P.map((p) => { const deg = p.a * 180 / Math.PI, flip = Math.cos(p.a) < 0; return `<g class="nd ${C.has(p.n) ? '' : 'ph'}" data-n="${esc(p.n)}" style="--sc:var(--s${C.has(p.n) ? secIdx(secOf(C.get(p.n).area)) : 6})" transform="translate(${p.x},${p.y})"><circle r="${p.leaf ? 3.2 : 4.6}"/><text transform="rotate(${flip ? deg + 180 : deg})" x="${flip ? -9 : 9}" dy=".32em" text-anchor="${flip ? 'end' : 'start'}">${esc(p.n)}</text></g>` }).join('')}</g></svg><div class="treehint">drag · scroll to zoom · double-click to reset</div></div>
    <section><div class="sh"><h2>Traits</h2><p>behaviour mixed in with <code>is</code></p></div>${traits.map((t) => `<div class="doc" style="max-width:none"><h4><a href="${chref(t.name)}">${esc(t.name)}</a> · ${t.methods.length} methods</h4><div class="chips" style="margin:0">${D.classes.filter((c) => (c.traits || []).includes(t.name)).map((c) => `<a class="chip" href="${chref(c.name)}">${esc(c.name)}</a>`).join('') || '<span style="color:var(--mute)">no conformers in core</span>'}</div></div>`).join('')}</section>${footer()}</div>`
  const svg = $('#treewrap svg'), wrap = $('#treewrap'), byName = new Map(P.map((p) => [p.n, p]))
  let vb = [-900, -900, 1800, 1800], drag = null, moved = false
  const setVB = () => svg.setAttribute('viewBox', vb.join(' '))
  wrap.addEventListener('wheel', (e) => { e.preventDefault(); const k = e.deltaY > 0 ? 1.12 : .89, r = svg.getBoundingClientRect(); const mx = vb[0] + (e.clientX - r.left) / r.width * vb[2], my = vb[1] + (e.clientY - r.top) / r.height * vb[3]; const nw = Math.min(3200, Math.max(260, vb[2] * k)), f = nw / vb[2]; vb = [mx - (mx - vb[0]) * f, my - (my - vb[1]) * f, nw, vb[3] * f]; setVB() }, { passive: false })
  wrap.addEventListener('pointerdown', (e) => { drag = [e.clientX, e.clientY, vb[0], vb[1]]; moved = false; wrap.setPointerCapture(e.pointerId) })
  wrap.addEventListener('pointermove', (e) => {
    if (drag) { const r = svg.getBoundingClientRect(), dx = e.clientX - drag[0], dy = e.clientY - drag[1]; if (Math.abs(dx) + Math.abs(dy) > 4) moved = true; vb[0] = drag[2] - dx / r.width * vb[2]; vb[1] = drag[3] - dy / r.height * vb[3]; setVB(); return }
    const g = document.elementFromPoint(e.clientX, e.clientY)?.closest?.('.nd'); hilite(g?.dataset.n)
  })
  wrap.addEventListener('pointerup', (e) => { const g = !moved && document.elementFromPoint(e.clientX, e.clientY)?.closest?.('.nd'); drag = null; if (g && C.has(g.dataset.n)) location.hash = chref(g.dataset.n) })
  wrap.addEventListener('dblclick', () => { vb = [-900, -900, 1800, 1800]; setVB() })
  let cur = null
  function hilite(n) {
    if (n === cur) return; cur = n
    $$('.hi', svg).forEach((x) => x.classList.remove('hi')); $('#tg').classList.toggle('dimmed', !!n)
    $$('.nd,.lk', svg).forEach((x) => x.classList.toggle('dim', !!n))
    if (!n) return
    const on = new Set(); let p = byName.get(n); while (p) { on.add(p.n); p = p.parent }
    const down = (x) => { on.add(x); (kids.get(x) || []).forEach(down) }; down(n)
    $$('.nd', svg).forEach((x) => { if (on.has(x.dataset.n)) { x.classList.remove('dim'); x.classList.add('hi') } })
    $$('.lk', svg).forEach((x) => { if (on.has(x.dataset.c)) { x.classList.remove('dim'); x.classList.add('hi') } })
  }
}

// ---------- wiring ----------
function toast(t) { const d = document.createElement('div'); d.className = 'toast'; d.textContent = t; document.body.append(d); setTimeout(() => d.remove(), 1500) }
function wire() {
  addEventListener('hashchange', route)
  $('#opensearch').onclick = () => openPal()
  $('#menu').onclick = () => document.body.classList.toggle('menu')
  $('#theme').onclick = toggleTheme
  $('#pal').addEventListener('pointerdown', (e) => { if (e.target.id === 'pal') closePal() })
  $('#palq').addEventListener('input', runPal)
  $('#palres').addEventListener('click', () => setTimeout(closePal, 0))
  $('#palq').addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); movePal(1) } else if (e.key === 'ArrowUp') { e.preventDefault(); movePal(-1) }
    else if (e.key === 'Enter') { const q = $('#palq').value.trim(); if (e.shiftKey && q) location.hash = `#/search/${encodeURIComponent(q)}`; else { const el = $$('#palres .res')[palSel]; if (el) location.hash = el.getAttribute('href') } closePal() }
  })
  addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); $('#pal').classList.contains('on') ? closePal() : openPal(); return }
    if (e.key === 'Escape') { closePal(); document.body.classList.remove('menu'); return }
    if (e.target.matches('input, textarea, select') || e.metaKey || e.ctrlKey || e.altKey) return
    if (e.key === '/') { e.preventDefault(); openPal() } else if (e.key === 'r') location.hash = '#/random'; else if (e.key === 't') toggleTheme()
    else if (e.key === 'g') location.hash = '#/tree'; else if (e.key === 'h') location.hash = '#/'
  })
  document.addEventListener('click', (e) => {
    const c = e.target.closest('[data-copy]'); if (c) { navigator.clipboard?.writeText(c.dataset.copy); toast('Copied ' + c.dataset.copy) }
    const l = e.target.closest('[data-copylink]'); if (l) { e.preventDefault(); navigator.clipboard?.writeText(location.href.split('#')[0] + l.dataset.copylink); history.replaceState(null, '', l.dataset.copylink); toast('Link copied') }
  })
}
function toggleTheme() { const r = document.documentElement; r.dataset.theme = r.dataset.theme === 'light' ? 'dark' : 'light'; sessionStash('theme', r.dataset.theme) }
