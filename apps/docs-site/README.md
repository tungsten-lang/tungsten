# Tungsten core docs — https://thecompanygardener.yaks.app/tungsten/

A static reference for every class, trait and method in `core/`, hosted on
yaks.app, plus a REPL that runs the self-hosted interpreter as WebAssembly on
Cloudflare Workers.

```
site/    what is served: index.html, app.js (views + search), hl.js (highlighter +
         doc-comment renderer), repl.js, style.css, icon.png
         worker.js          POST ./run {code} -> {stdout, stderr, exitCode}; runs tungsten.wasm
         browser-engine.js  the same module in a Web Worker (fallback / "browser" engine)
         wasi_shim.js       dependency-free wasi_snapshot_preview1 host (from wasm/, see below)
tools/   extract.py   core/*.w (+ spec/, doc/examples) -> docs.json
         push.py      write files into the yaks.app app (needs YAKS_TOKEN)
         push_src.py  upload the source files the site shows, as src/<path>, batched
```

Generated, not committed (`site/.gitignore`): `docs.json`, `tungsten.wasm`,
`tungsten.fs`, `src/`.

## Regenerate and deploy

```sh
ROOT=$(git rev-parse --show-toplevel)
python3 apps/docs-site/tools/extract.py $ROOT /tmp/docs $(git rev-parse HEAD) "optional footer note"
cp /tmp/docs/docs.json apps/docs-site/site/

export YAKS_TOKEN=...            # yaks.app `grant` tool, scoped to the space
cd apps/docs-site/site
python3 ../tools/push.py tungsten index.html style.css app.js hl.js repl.js docs.json
# source files the pages link to (every file docs.json names):
python3 - <<'PY' > /tmp/src_files.txt
import json; d = json.load(open('docs.json')); fs = set()
for c in d['classes']:
    fs |= {f for f, _ in c['files']} | set(c.get('specs', []))
    for m in c.get('methods', []): fs.add(m['f']); fs |= {x[0] for x in m.get('x', [])}
fs |= {m['f'] for m in d['functions']} | {g[0] for g in d['gallery']}
print('\n'.join(sorted(fs)))
PY
python3 ../tools/push_src.py tungsten $ROOT /tmp/src_files.txt
```

Then `app_deploy` (yaks.app MCP tool) marks the release and uploads `worker.js`
with the `tungsten.wasm` it imports. Bump the `?v=N` on the module URLs in
`index.html`, `app.js` and `repl.js` when shipping JS changes — browsers cache
ES modules hard. `hl.js` must be imported with the *same* specifier everywhere
or it loads twice and the class index splits.

## What the extractor understands

`+ Class < Parent`, `trait`, `is`/`with`, `-> name(params)` (class methods via a
leading `.`), bodiless declarations (abstract), bodiless `-> new(@a, @b)`
(binds fields), `ro :a, :b` / `rw :c` and the constructor's trailing `ro`/`rw`
(accessors), `runtime :name` (native), `- data` layouts, constants, `# ----
section ----` dividers as method groups, doc comments (prose + indented code),
and the `auto` table in `core/tungsten.w` (autoloaded vs `use`). Usage examples
are lines from `spec/` and `doc/examples/` that call a method whose owner is
unambiguous.

## The REPL engine

`tungsten.wasm` + `tungsten.fs` + `wasi_shim.js` come from the wasm32-wasi port
(`wasm/` in the `worktree-agent-a4163fbcdb9be146e` worktree; its README has the
build, every stub and the host contract). One fresh `WebAssembly.Instance` per
request; the stdlib bundle is fetched once per isolate through `env.FILES`.
yaks.app gives a worker 50 ms of CPU per request: `<< 1 + 1` is ~3 ms, a class
~13 ms, `[1,2,3].map` ~25 ms (it re-parses the autoloaded core files each run).
Anything over budget comes back as a 5xx and `repl.js` reruns it in the browser
engine. The console "session" is a replay: every accepted input is re-sent,
and output after a `\u0001` marker is the new part.
