// The REPL: Tungsten's self-hosted interpreter, compiled to wasm32-wasi.
// "edge" posts to ./run (worker.js runs the wasm on Cloudflare); "browser" runs the same wasm in a Web Worker here.
import { hl, esc } from './hl.js?v=6'

const MARK = '\u0001', VAL = '\u0002'
const PRESETS = {
  'hello, filament': `# Pseudocode that runs. ⌘↵ to run, or type in the console →\n+ Filament\n  -> new(@metal, @kelvin)\n\n  -> glow\n    if @kelvin > 2500\n      "[@metal] glows white at [@kelvin] K"\n    else\n      "[@metal] is barely orange"\n\n<< Filament.new("tungsten", 3422).glow\n<< Filament.new("iron", 1200).glow\n`,
  'operators & classes': `+ Vec\n  ro :x, :y\n\n  -> new(@x, @y)\n\n  -> +(other)\n    Vec.new(@x + other.x, @y + other.y)\n  -> to_s\n    "⟨[@x], [@y]⟩"\n\na = Vec.new(1, 2)\nb = Vec.new(3, 4)\n<< (a + b).to_s\n`,
  'exact numbers': `# Integers promote to bignums; literals stay exact.\n<< 2 ** 200\n<< 1/3 + 1/6\n<< 0.1 + 0.2 == 0.3\n\n-> fact(n)\n  if n < 2\n    return 1\n  n * fact(n - 1)\n\n<< fact(30)\n`,
  'collections': `squares = (1..10).map -> (n) n * n\n<< squares\n<< squares.select(-> (n) n % 2 == 0)\n<< squares.reduce(0, -> (a, b) a + b)\n\nelements = {"W" => 74, "Fe" => 26, "Au" => 79}\nelements.each -> (sym, z)\n  << "[sym] has atomic number [z]"\n`,
  'units & exact math': `# Quantities carry their units; rationals stay exact.\n<< 5 m + 20 cm\n<< 60 km / 2 h\n<< 1/3 + 1/6\n<< (2/3) ** 2\n<< 17.prime?\n\nz = Complex.new(1, 2)\n<< z * z\n<< "héllo".graphemes.size\n`,
  'traits & ro': `trait Loud\n  -> shout\n    name.upcase + "!"\n\n+ Dog\n  is Loud\n  ro :name\n  rw :tricks\n\n  -> new(@name)\n    @tricks = 0\n\nrex = Dog.new("rex")\nrex.tricks = 3\n<< rex.shout\n<< "[rex.name] knows [rex.tricks] tricks"\n`,
  'fizzbuzz': `(1..20).each -> (i)\n  if i % 15 == 0\n    << "FizzBuzz"\n  elsif i % 3 == 0\n    << "Fizz"\n  elsif i % 5 == 0\n    << "Buzz"\n  else\n    << i\n`,
}

let engine = 'edge', browserWorker = null, session = []

export function mountRepl(view, shared) {
  let code = PRESETS['hello, filament']
  try { const s = sessionStorage.getItem('repl:code'); if (s) { code = s; sessionStorage.removeItem('repl:code') } } catch {}
  if (shared) try { code = new TextDecoder().decode(Uint8Array.from(atob(shared.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0))) } catch {}
  view.innerHTML = `<div class="wide">
    <div class="title"><h1>REPL</h1><span class="kind method">wasm32-wasi</span></div>
    <p class="doc" style="max-width:88ch;margin-top:10px">The real thing, not a toy: Tungsten's self-hosted interpreter compiled to WebAssembly. <b>Edge</b> runs it inside a Cloudflare Worker next to this page; <b>Browser</b> runs the identical module on your machine. The console replays your session each turn, so definitions persist.</p>
    <div class="repl" style="margin-top:18px">
      <div class="pane"><div class="ph"><span class="lights"><i></i><i></i><i></i></span><span>scratch.w</span><span class="r"><select id="preset"><option value="">examples…</option>${Object.keys(PRESETS).map((k) => `<option>${k}</option>`).join('')}</select><button class="btn sm" id="share">share ⧉</button><button class="btn sm hot" id="run">▶ Run <kbd style="background:rgba(0,0,0,.15);border-color:rgba(0,0,0,.2);color:inherit">⌘↵</kbd></button></span></div>
        <div class="ed scroll"><pre id="edhl" aria-hidden="true"></pre><textarea id="edin" spellcheck="false" autocapitalize="off" autocomplete="off"></textarea></div></div>
      <div class="pane"><div class="ph"><span class="pulse" id="pulse"></span><span id="status">ready</span><span class="r"><div class="seg" id="eng"><button data-e="edge" class="on" title="Run on Cloudflare Workers">⚡ edge</button><button data-e="browser" title="Run in this tab">▣ browser</button></div><button class="btn sm" id="clear">clear</button></span></div>
        <div id="out" class="scroll"><div class="o-meta">Tungsten REPL — expressions echo their value, definitions persist. <kbd>↵</kbd> run · <kbd>⇧↵</kbd> newline · <kbd>↑</kbd> history</div></div>
        <div class="prompt"><b>w›</b><textarea id="line" rows="1" spellcheck="false" autocapitalize="off" placeholder="2 ** 100"></textarea></div></div>
    </div></div>`
  const $ = (s) => view.querySelector(s)
  const ed = $('#edin'), pre = $('#edhl'), out = $('#out'), lineIn = $('#line')
  const paint = () => { pre.innerHTML = hl(ed.value) + '\n'; ed.style.height = 'auto'; ed.style.height = Math.max(ed.scrollHeight, ed.parentNode.clientHeight) + 'px'; ed.style.width = Math.max(pre.scrollWidth, ed.parentNode.clientWidth) + 'px' }
  ed.value = code; session = []; paint()
  ed.addEventListener('input', paint)
  ed.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') { e.preventDefault(); ed.setRangeText('  ', ed.selectionStart, ed.selectionEnd, 'end'); paint() }
    if (e.key === 'Enter' && !e.metaKey && !e.ctrlKey) { // keep indentation; indent after a block opener
      const before = ed.value.slice(0, ed.selectionStart), cur = before.slice(before.lastIndexOf('\n') + 1)
      const ind = cur.match(/^ */)[0] + (/^\s*(\+ |-> |fn |trait |if |elsif |else|unless |while |until |for |case |when |begin|rescue|ensure|loop)|->\s*(\([^)]*\))?\s*$/.test(cur) ? '  ' : '')
      e.preventDefault(); ed.setRangeText('\n' + ind, ed.selectionStart, ed.selectionEnd, 'end'); paint()
    }
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); runEditor() }
  })
  $('#preset').onchange = (e) => { if (e.target.value) { ed.value = PRESETS[e.target.value]; paint(); e.target.value = '' } }
  $('#share').onclick = () => { const b = btoa(String.fromCharCode(...new TextEncoder().encode(ed.value))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); const u = location.href.split('#')[0] + '#/repl/' + b; navigator.clipboard?.writeText(u); history.replaceState(null, '', '#/repl/' + b); say('meta', 'Share link copied to clipboard.') }
  $('#clear').onclick = () => { out.innerHTML = ''; session = []; say('meta', 'Session cleared.') }
  $('#run').onclick = runEditor
  $('#eng').onclick = (e) => { const b = e.target.closest('button'); if (!b) return; setEngine(b.dataset.e) }
  const setEngine = (e) => { engine = e; view.querySelectorAll('#eng button').forEach((x) => x.classList.toggle('on', x.dataset.e === e)) }
  setEngine(engine)

  function say(kind, text) {
    const d = document.createElement('div'); d.className = 'o-' + kind
    if (kind === 'in') { d.innerHTML = hl(text).split('\n').map((l, i) => i ? `<div class="o-in cont">${l}</div>` : l).join('') } else d.textContent = text
    out.append(d); out.scrollTop = out.scrollHeight
  }
  const busy = (on, label) => { $('#pulse').className = 'pulse' + (on ? ' busy' : ''); $('#status').textContent = label }

  async function exec(program) {
    busy(true, engine === 'edge' ? 'running on the edge…' : 'running in your browser…')
    const t0 = performance.now()
    let r
    try {
      r = engine === 'edge' ? await runEdge(program) : await runBrowser(program)
    } catch (err) {
      if (engine === 'edge') {
        say('meta', err.budget ? 'over the edge budget (Cloudflare allows 50 ms of CPU per request) — running this one in your browser instead' : `edge engine unavailable (${err.message}) — switching to the in-browser engine`)
        if (!err.budget) setEngine('browser')
        busy(true, 'running in your browser…')
        try { r = await runBrowser(program) } catch (e2) { r = { stdout: '', stderr: 'Both engines failed: ' + e2.message, exitCode: 1 } }
      } else r = { stdout: '', stderr: err.message, exitCode: 1 }
    }
    r.wall = Math.round(performance.now() - t0)
    busy(false, `${r.engine || engine} · ${r.ms != null ? r.ms + ' ms run · ' : ''}${r.wall} ms round trip`)
    if (r.exitCode) $('#pulse').className = 'pulse off'
    return r
  }
  function show(stdout, stderr) {
    for (const l of stdout.replace(/\n$/, '').split('\n')) { if (l.startsWith(VAL)) say('val', '=> ' + l.slice(1)); else if (l || stdout) say('out', l) }
    if (stderr.trim()) say('err', tidyErr(stderr))
  }
  async function runEditor() {
    const src = ed.value
    say('meta', '── run scratch.w ──')
    const r = await exec(src)
    show(r.stdout || '', r.stderr || '')
    session = r.exitCode ? [] : [src]
    if (!r.exitCode) say('meta', 'definitions from scratch.w are now live in the console')
  }
  async function runLine(text) {
    say('in', text)
    const r = await exec([...session, `<< "${MARK}"`, echo(text)].join('\n') + '\n')
    const so = r.stdout || '', at = so.lastIndexOf(MARK)
    show(at >= 0 ? so.slice(at + 2) : so, r.stderr || '')
    if (!r.exitCode) session.push(text)
  }
  // History + submit rules for the prompt.
  const hist = []; let hi = 0
  const grow = () => { lineIn.style.height = 'auto'; lineIn.style.height = lineIn.scrollHeight + 'px' }
  lineIn.addEventListener('input', grow)
  lineIn.addEventListener('keydown', (e) => {
    const v = lineIn.value
    if (e.key === 'Enter' && !e.shiftKey) {
      const lines = v.split('\n'), opener = /^\s*(\+ |-> |fn |trait |if |unless |while |until |for |case |begin|loop)|->\s*(\([^)]*\))?\s*$/
      const open = lines.some((l) => opener.test(l)), lastBlank = !lines[lines.length - 1].trim()
      if (open && !(lastBlank && lines.length > 1)) { e.preventDefault(); const ind = lines[lines.length - 1].match(/^ */)[0] + (opener.test(lines[lines.length - 1]) ? '  ' : ''); lineIn.setRangeText('\n' + ind, lineIn.selectionStart, lineIn.selectionEnd, 'end'); grow(); return }
      e.preventDefault(); const t = v.replace(/\s+$/, ''); if (!t) return
      hist.push(t); hi = hist.length; lineIn.value = ''; grow(); runLine(t)
    } else if (e.key === 'ArrowUp' && !v.includes('\n') && hi > 0) { e.preventDefault(); lineIn.value = hist[--hi]; grow() }
    else if (e.key === 'ArrowDown' && !v.includes('\n') && hi < hist.length) { e.preventDefault(); lineIn.value = hist[++hi] || ''; grow() }
    else if (e.key === 'l' && e.ctrlKey) { e.preventDefault(); out.innerHTML = '' }
  })
  lineIn.focus()
}

// Single-line expressions echo their value, like any civilised REPL.
function echo(text) {
  if (text.includes('\n')) return text
  if (/^\s*(<<|use |raise |return |if |unless |while |until |for |case |\+ |-> |fn |trait |begin|#)/.test(text)) return text
  const asg = text.match(/^\s*([a-z_]\w*)\s*(?:[-+*\/%|&^]|\*\*|<<|>>)?=(?!=)/)
  if (asg) return `${text}\n<< "${VAL}[${asg[1]}]"`
  return `__w = (${text})\n<< "${VAL}[__w]"`
}
const tidyErr = (s) => s.replace(/\x1b\[[0-9;]*m/g, '').replace(/\n\s*--> \/work\/main\.w\s*$/m, '').replace(/\/work\/main\.w:?/g, 'line ').replace(new RegExp(`[${MARK}${VAL}]`, 'g'), '').trim()

async function runEdge(code) {
  const r = await fetch('./run', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ code }) })
  if (!r.ok) throw Object.assign(new Error(r.status === 404 ? 'not deployed' : `HTTP ${r.status}`), { budget: r.status >= 500 })
  return { ...(await r.json()), engine: 'edge' }
}
function runBrowser(code) {
  return new Promise((resolve, reject) => {
    if (!browserWorker) browserWorker = new Worker('./browser-engine.js', { type: 'module' })
    const w = browserWorker
    const timer = setTimeout(() => { w.terminate(); browserWorker = null; resolve({ stdout: '', stderr: 'Timed out after 10 s — the run was terminated.', exitCode: 124, engine: 'browser' }) }, 10000)
    w.onmessage = (e) => { clearTimeout(timer); e.data.error ? reject(new Error(e.data.error)) : resolve({ ...e.data, engine: 'browser' }) }
    w.onerror = (e) => { clearTimeout(timer); browserWorker = null; reject(new Error(e.message || 'engine failed to load')) }
    w.postMessage({ code })
  })
}
