// The same tungsten.wasm, run in a Web Worker on the visitor's machine.
import { run, loadBundle } from './wasi_shim.js'
let ready
const compile = async () => {
  try { return await WebAssembly.compileStreaming(fetch('./tungsten.wasm')) } catch { return WebAssembly.compile(await (await fetch('./tungsten.wasm')).arrayBuffer()) }
}
const init = () => (ready ||= Promise.all([compile(), fetch('./tungsten.fs').then((r) => r.arrayBuffer()).then(loadBundle)]))
onmessage = async (e) => {
  try {
    const [mod, fs] = await init()
    const t0 = performance.now()
    const r = run(mod, { args: ['tungsten', '/work/main.w'], files: [new Map([['/work/main.w', new TextEncoder().encode(e.data.code)]]), fs], maxOutputBytes: 256 * 1024 })
    postMessage({ stdout: r.stdout, stderr: r.stderr, exitCode: r.exitCode, ms: Math.round(performance.now() - t0) })
  } catch (err) { ready = null; postMessage({ error: String(err?.message || err) }) }
}
