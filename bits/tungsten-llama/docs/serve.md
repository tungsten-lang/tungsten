# Serving Qwen3.8-Flash-Next over an OpenAI-compatible HTTP API

`scripts/bench/qwen38fn_mlx.w` is the Tungsten inference engine for
**Qwen3.8-Flash-Next (125B/A6B MoE, NVFP4)** on Apple Metal. Passing `serve`
as the first argument turns it into a single-process, OpenAI-compatible HTTP
server instead of a benchmark run.

## Start the server

```bash
BIT_HOME=$PWD/bits FN_QUANT=1 bin/tungsten run scripts/bench/qwen38fn_mlx.w serve 8080
```

Run it from the repository root. `BIT_HOME` is **not optional** — see
*The BIT_HOME trap* below. Weights are read from
`~/.cache/tungsten/qwen38-flash-next-nvfp4/`; the first minute or two is model
load (75 GB of no-copy mmap'd shards + kernel compilation). The server is ready
when stderr prints:

```
[serve] qwen3.8-flash-next OpenAI-compatible server on http://127.0.0.1:8080
[serve] routes: GET /health, GET /v1/models, POST /v1/chat/completions, POST /v1/completions
[serve] context 2051 tokens (FN_CTX), spec depth 0 (FN_SPEC), quant true
```

All server logging goes to **stderr** (stdout is fully buffered when piped, so
it is useless for progress). Poll `GET /health` to detect readiness.

A useful production-ish invocation — 32k context, speculative decode, listening
on all interfaces:

```bash
BIT_HOME=$PWD/bits FN_QUANT=1 FN_CTX=32768 FN_HOST=0.0.0.0 \
  bin/tungsten run scripts/bench/qwen38fn_mlx.w serve 8080
```

(FN_SPEC and FN_CTX > 2051 are mutually exclusive — see *Limits*.)

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `BIT_HOME` | `~/.tungsten/bits` | **Set this to `$PWD/bits`.** Without it the engine builds against the installed bit tree and its stale `core/`. |
| `FN_QUANT=1` | off | Route the big matvecs through the self-quantized NVFP4 sidecars. **Recommended** — much faster, and what the published numbers use. |
| `FN_HOST` | `127.0.0.1` | Bind address. Use `0.0.0.0` to accept remote clients (there is no auth — put it behind something). |
| `FN_CTX` | `2051` | Maximum position count = the hard cap on `prompt + max_tokens`. Up to `262144`. Above 2051 the QSA lightning indexer takes over from dense attention. Larger contexts allocate proportionally larger K/V and index caches. |
| `FN_SPEC` | `0` | Speculative-decode draft depth (1..7); loads the MTP head and decodes greedy requests through the depth-D verify loop. `FN_SPEC=3` measured ~+39% tok/s. Greedy requests only. |
| `FN_CHUNK` | on | `FN_CHUNK=0` forces serial token-by-token prefill instead of 512-token chunked prefill (A/B escape hatch; much slower). |
| `FN_NA=1` | off | Neural-Accelerator (matmul2d) GEMMs for the bf16 backbone in the chunked prefill. |
| `FN_TIME=1` | off | Per-round host phase timings on stdout. |

The port is `ARGV[1]` (default `8080`).

## The BIT_HOME trap

`use tungsten-llama/...` resolves through `BIT_HOME`, which defaults to the
**installed** bit tree (`$TUNGSTEN_HOME/bits`, i.e. `~/.tungsten/bits`) rather
than this checkout's `bits/`. That install carries its own `core/` too, so the
build silently picks up an old `core/json.w` — one whose byte parser indexes a
borrowed `u8[]` view without bounds checks.

Nothing about the build fails; the server starts and answers normal requests
fine. It only shows up when a client sends malformed JSON: the parser walks off
the end of the string and the process either spins (allocating until the OS
kills it) or dies outright, taking the loaded model with it.

`BIT_HOME=$PWD/bits` pins resolution to this checkout. To confirm you got the
right one:

```bash
BIT_HOME=$PWD/bits bin/tungsten -e 'use core/json
<< JSON.parse("\[1e5]").to_s'
```

`[100000]` is the current parser. `[1, 5]` means you are on the old one — the
exponent was split into two array elements — and the server will not survive a
malformed request.

## Routes

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | `{"status":"ok", "model", "max_context", "spec_depth", "quantized"}` |
| `GET` | `/v1/models` | OpenAI model list |
| `POST` | `/v1/chat/completions` | Chat completions (streaming or not) |
| `POST` | `/v1/completions` | Raw-prompt completions |
| `OPTIONS` | any | CORS preflight |

`/models`, `/chat/completions` and `/completions` are also accepted without the
`/v1` prefix.

### Request fields

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `messages` | array | required (chat) | `{role, content}`; `content` may be a string or an array of `{type:"text", text}` parts |
| `prompt` | string | required (completions) | Fed to the tokenizer verbatim — no chat template |
| `max_tokens` | int | `256` | Also accepted as `max_completion_tokens` |
| `temperature` | number | `0` | `0` = greedy argmax. `> 0` samples the logits (and forces the serial decode loop, since the speculative verify is argmax-only) |
| `top_k` | int | `0` | `0` = full-vocab sampling; `> 0` restricts to the K highest logits |
| `stream` | bool | `false` | `true` = `text/event-stream`, one chunk per token |
| `stop` | string or array | none | Stop strings; matching text is truncated and `finish_reason` is `"stop"` |
| `enable_thinking` | bool | `false` | Also read from `chat_template_kwargs.enable_thinking`. `false` closes an empty `<think>` block so the model answers directly; `true` opens `<think>` and prepends the `xhigh` reasoning preamble |
| `model` | string | ignored | One model is loaded per process |

Every field is type-checked before use and a bad type is a `400` with an
OpenAI-shaped error body. `finish_reason` is `"stop"` (EOS token or a stop
string) or `"length"` (`max_tokens` reached).

## Examples

Non-streaming:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"What is the capital of France?"}],
       "max_tokens":32}'
```

```json
{"id":"chatcmpl-fn1788386000-1","object":"chat.completion","created":1788386000,
 "model":"qwen3.8-flash-next",
 "choices":[{"index":0,"message":{"role":"assistant","content":"The capital of France is Paris."},
             "finish_reason":"stop"}],
 "usage":{"prompt_tokens":19,"completion_tokens":8,"total_tokens":27}}
```

Streaming (one SSE chunk per token, a final chunk carrying `finish_reason` and
`usage`, then `data: [DONE]`):

```bash
curl -N -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Name three colours."}],
       "max_tokens":48,"stream":true}'
```

```
data: {"id":"chatcmpl-…","object":"chat.completion.chunk",…,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"chatcmpl-…","object":"chat.completion.chunk",…,"choices":[{"index":0,"delta":{"content":"Red"},"finish_reason":null}]}

…

data: {"id":"chatcmpl-…","object":"chat.completion.chunk",…,"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":16,"completion_tokens":12,"total_tokens":28}}

data: [DONE]
```

Sampling, stop strings and thinking mode:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Write a limerick."}],
       "max_tokens":128,"temperature":0.8,"top_k":40,"stop":["\n\n"],
       "enable_thinking":false}'
```

Raw completion:

```bash
curl -s http://127.0.0.1:8080/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"The three laws of robotics are","max_tokens":64}'
```

Health / models:

```bash
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/v1/models
```

Any OpenAI client works by pointing `base_url` at `http://127.0.0.1:8080/v1`
with a dummy API key.

## Limits

- **One request at a time.** The GPU is a single engine and the server is a
  single-threaded accept loop: connections queue, they are not interleaved.
  Each response closes its connection (`Connection: close`); there is no
  keep-alive.
- **No conversation cache.** Every request resets the GDN convolution and
  recurrent state, the PLE convolution state and the n-gram context, then
  prefills the whole prompt from position 0. A multi-turn chat re-prefills the
  entire history each turn.
- **`prompt + max_tokens <= FN_CTX`**, enforced up front — over the limit is a
  `400` with `"type": "context_length_exceeded"`, naming both counts. Raise
  `FN_CTX` and restart to serve longer conversations.
- **`FN_SPEC` requires `FN_CTX <= 2051`.** The speculative/multi path beyond the
  dense-attention boundary is not wired to the QSA indexer yet; the process
  refuses to start with both. Speculative decode is also greedy-only —
  `temperature > 0` silently falls back to the serial loop for that request.
- **No auth, no rate limiting, no TLS.** Bind to localhost or front it with a
  reverse proxy.
- **Unsupported OpenAI fields** are ignored rather than rejected: `n`,
  `top_p`, `presence_penalty`, `frequency_penalty`, `logprobs`, `tools` /
  `tool_choice`, `seed`, `response_format`. Image and audio content parts are
  rejected with a `400`.
- **Sampling cost.** `temperature > 0` reads all 248,320 logits back to the
  host per token; `top_k > 0` costs another `K` passes over that array. Both
  are small next to the forward step, but greedy decoding is the fast path.

## Where the code lives

All of it is one clearly delimited section at the end of
`scripts/bench/qwen38fn_mlx.w`, under the banner
`==== SERVE MODE — OpenAI-compatible HTTP server ====`, plus a short block near
the top that parses `serve` / the port and parks the benchmark driver. The
server has to live inside that file because the engine is a top-level script
whose functions close over top-level locals (buffers, pipelines, layer tables) —
it cannot be driven from a separate program.
