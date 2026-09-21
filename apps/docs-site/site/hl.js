// Tungsten syntax highlighter + doc-comment renderer.
export const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
let classes = new Map()
export const setClassIndex = (m) => { classes = m }

const KW = new Set('if elsif else unless while until for in return raise use is with trait fn case when recase loop break next yield self nil true false and or not rescue ensure begin do then auto ro rw alias super ccall ccall_nobox runtime field readonly data'.split(' '))
const TOK = /(##\s*[\w\[\]<>, ]+?(?=\s*(?:#|$)))|(#.*$)|("(?:\\.|[^"\\])*"?)|('(?:[^'\n])*')|(:[a-zA-Z_]\w*[?!]?)|(\b0x[\da-fA-F_]+\b|\b\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?(?:[a-zA-Zµ]+\d*)*)|(@\d+|@[a-zA-Z_]\w*|\$[a-zA-Z_]\w*)|(->|<<|=>|\*\*|\.\.\.?|[+\-*\/%=<>!&|^~]+)|([A-Z]\w*)|([a-z_]\w*[?!]?)/g

export function hl(code) {
  return String(code).split('\n').map(line).join('\n')
}
function line(src) {
  let out = '', last = 0, prev = '', m
  TOK.lastIndex = 0
  while ((m = TOK.exec(src))) {
    out += esc(src.slice(last, m.index)); last = TOK.lastIndex
    const t = m[0]
    if (m[1]) out += `<span class="ty">${esc(t)}</span>`
    else if (m[2]) out += `<span class="c">${esc(t)}</span>`
    else if (m[3]) out += `<span class="s">${esc(t).replace(/\[([^\[\]]+)\]/g, '<span class="in">[$1]</span>')}</span>`
    else if (m[4]) out += `<span class="s">${esc(t)}</span>`
    else if (m[5]) out += `<span class="sy">${esc(t)}</span>`
    else if (m[6]) out += `<span class="nu">${esc(t)}</span>`
    else if (m[7]) out += `<span class="iv">${esc(t)}</span>`
    else if (m[8]) out += `<span class="${t === '->' || t === '<<' ? 'k' : 'op'}">${esc(t)}</span>`
    else if (m[9]) out += classes.has(t) ? `<a class="ty" href="#/c/${encodeURIComponent(t)}">${esc(t)}</a>` : `<span class="ty">${esc(t)}</span>`
    else if (prev === '->' || prev === 'fn') out += `<span class="df">${esc(t)}</span>`
    else out += KW.has(t) ? `<span class="k">${esc(t)}</span>` : esc(t)
    if (!/^\s*$/.test(t)) prev = t
    if (m.index === TOK.lastIndex) TOK.lastIndex++
  }
  return out + esc(src.slice(last))
}

const inline = (s) => esc(s)
  .replace(/`([^`]+)`/g, (_, c) => { const d = c.replace(/&lt;.*/, ''); return classes.has(d) ? `<a href="#/c/${encodeURIComponent(d)}"><code>${c}</code></a>` : `<code>${c}</code>` })
  .replace(/(^|[\s(])(https?:\/\/[^\s)]+)/g, '$1<a href="$2" target="_blank" rel="noopener">$2</a>')
  .replace(/(^|[\s(])([A-Z][a-z]\w+)(?=[\s.,;:)#]|$)/g, (all, pre, w) => (classes.has(w) ? `${pre}<a href="#/c/${encodeURIComponent(w)}">${w}</a>` : all))

// Doc comments are prose with indented code, `-- Heading --` rules, bullets and the odd @tag.
export function renderDoc(text) {
  if (!text) return ''
  const lines = text.split('\n'), out = []
  let para = [], code = [], list = []
  const flushP = () => { if (para.length) out.push(`<p>${inline(para.join(' '))}</p>`); para = [] }
  const flushC = () => { while (code.length && !code[code.length - 1].trim()) code.pop(); if (code.length) { const ind = Math.min(...code.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length)); out.push(`<pre>${hl(code.map((l) => l.slice(ind)).join('\n'))}</pre>`) } code = [] }
  const flushL = () => { if (list.length) out.push(`<ul>${list.map((l) => `<li>${inline(l)}</li>`).join('')}</ul>`); list = [] }
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]
    const h = l.match(/^\s*(?:--+|==+|──+)\s*(.+?)\s*(?:--+|==+|──+)\s*$/)
    if (h) { flushP(); flushC(); flushL(); out.push(`<h4>${esc(h[1])}</h4>`); continue }
    if (!l.trim()) { if (code.length) code.push(''); flushP(); flushL(); continue }
    if (/^( {2,}|\t)/.test(l) && !list.length) { flushP(); code.push(l); continue }
    flushC()
    const b = l.match(/^\s*[-*•]\s+(.*)$/)
    if (b) { flushP(); list.push(b[1]); continue }
    if (list.length && /^\s+/.test(l)) { list[list.length - 1] += ' ' + l.trim(); continue }
    flushL()
    const tag = l.match(/^@(\w+)\s*(.*)$/)
    if (tag) { flushP(); out.push(`<p><span class="tag">${esc(tag[1])}</span>${inline(tag[2])}</p>`); continue }
    para.push(l.trim())
  }
  flushP(); flushC(); flushL()
  return out.join('')
}
