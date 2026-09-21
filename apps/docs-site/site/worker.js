// POST ./run {code} -> {stdout, stderr, exitCode}. Tungsten's self-hosted interpreter, compiled to
// wasm32-wasi, one fresh Instance per request. Everything else 404s through to the app's files.
import wasm from './tungsten.wasm'
import { run, loadBundle } from './wasi_shim.js'

let bundle // core/*.w + lexer tables, parsed once per isolate
async function stdlib(env) {
  if (!bundle) {
    const r = await env.FILES.fetch('/tungsten.fs')
    if (!r.ok) throw new Error('tungsten.fs: ' + r.status)
    bundle = loadBundle(await r.arrayBuffer())
  }
  return bundle
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url)
    if (!/\/run\/?$/.test(url.pathname)) return new Response('not found', { status: 404 })
    if (req.method !== 'POST') return Response.json({ error: 'POST {"code": "<< 1 + 1"}' }, { status: 405 })
    let code
    try { ({ code } = await req.json()) } catch { code = null }
    if (typeof code !== 'string' || code.length > 65536) return Response.json({ error: 'code must be a string of at most 64 KB' }, { status: 400 })
    const fs = await stdlib(env)
    const r = run(wasm, {
      args: ['tungsten', '/work/main.w'],
      files: [new Map([['/work/main.w', new TextEncoder().encode(code)]]), fs],
      maxOutputBytes: 64 * 1024,
      timeoutMs: 4000,
    })
    return Response.json({ stdout: r.stdout, stderr: r.stderr, exitCode: r.exitCode, truncated: r.truncated }, { headers: { 'cache-control': 'no-store' } })
  },
}
