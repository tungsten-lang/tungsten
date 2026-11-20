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

`push.py`/`push_src.py` write into whatever draft the token's session opens;
set `YAKS_DRAFT=<id>` (from the first write's answer) to keep them in one.

Then `app_deploy` marks the release and uploads `worker.js` with the
`tungsten.wasm` it imports. With ~1,300 files it outlasts the MCP tool's
timeout: send the same JSON-RPC `tools/call app_deploy` over HTTP (as `push.py`
does), with `base` = the live version and `draft`.

**Binaries over the upload cap.** `app_files` refuses a request body somewhere
under 8 MiB, i.e. a file over ~5.6 MB once base64-encoded (`tungsten.wasm` is
6.6 MB, `tungsten.fs` 7.1 MB as of 93e6ab7f; `-Os`/`-Oz` builds still miss).
Ship them gzipped and let the live worker inflate them:

1. `gzip -9 -k tungsten.wasm tungsten.fs`, push the two `.gz` files, deploy.
2. `app_files op: fetch, path: tungsten.wasm, url: https://thecompanygardener.yaks.app/tungsten/unz/tungsten.wasm`
   (same for `tungsten.fs`): `worker.js` serves `GET ./unz/<file>` as
   `<file>.gz` inflated. Check the sha256 the fetch reports against the local file.
3. Delete the `.gz` files in that draft and deploy again. Bump the `?v=N` on the module URLs in
`index.html`, `app.js` and `repl.js` when shipping JS changes — browsers cache
ES modules hard. `hl.js` must be imported with the *same* specifier everywhere
or it loads twice and the class index splits.

## Sections

`core/`'s top-level directories ("areas") are grouped into the sections in
`SECTIONS` at the top of `app.js` (Foundations, Algebra & number theory,
Analysis & geometry, Data & science, Graphics & publishing), each area with a
one-line `AREA_BLURB`. A new `core/` directory still shows up, under "More",
until it is filed there; `AREA_ALIAS` folds tiny areas into another. The
sidebar, the Library page and the home page's treemap (squarified,
section > area > class, sized by method count) all read them.

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
in `wasm/` (`wasm/build.sh`; its README has the build, every stub and the host
contract). Copy the three files into `site/` after a build. One fresh `WebAssembly.Instance` per
request; the stdlib bundle is fetched once per isolate through `env.FILES`.
yaks.app gives a worker 50 ms of CPU per request: `<< 1 + 1` is ~3 ms, a class
~13 ms, `[1,2,3].map` ~25 ms (it re-parses the autoloaded core files each run).
Anything over budget comes back as a 5xx and `repl.js` reruns it in the browser
engine. The console "session" is a replay: every accepted input is re-sent,
and output after a `\u0001` marker is the new part.
