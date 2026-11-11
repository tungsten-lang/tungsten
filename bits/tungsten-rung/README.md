# rung

Write a task once, then run it up a ladder of models. Each model sees the task
and the current state of the answer, then tries to improve it. After every call,
an integrator model merges the new answer into the state and returns a short
verdict: did the state improve, what changed, and which claims still need
checking. Rounds repeat until one full round brings no improvement.

```sh
rung task.md                                    # the default ladder: codex, agy, grok, carbon, fable, claude
rung task.md --models "ollama:glm-5.3,claude"   # a different ladder
rung task.md -m "codex,ollama:glm-5.3|ollama:kimi-k3,claude" -r 3
rung task.md --dry-run                          # write the plan and the first prompts, call nothing
rung --resume task.rung/20261027-101500         # continue after Ctrl-C, a crash or --max-rounds
rung models                                     # the registry: installed? signed in?
rung check task.md                              # validate the registry, the guard and the prompt file
rung config > ~/.config/rung/models.toml        # start a registry from the built-ins
```

Build it from the Tungsten root with `cd bits/tungsten-rung && ../../bin/tungsten build`
(this writes `bin/rung`), or run the source directly:
`bin/tungsten bits/tungsten-rung/bin/rung.w -- task.md`.

## Options

| option | meaning |
|---|---|
| `-m, --models LIST` | Ladder order, comma-separated. `a\|b\|c` makes one parallel step. |
| `-i, --integrator MODEL` | The model that merges answers (default `claude`). |
| `-r, --max-rounds N` | Round cap; `0` means no cap and runs until a plateau. The default is 8. |
| `-t, --timeout SECS` | Per-call timeout for every call. |
| `-o, --out DIR` | Run directory (default `TASK.rung/STAMP` beside the prompt file). |
| `-n, --dry-run` | Plan only. `rung --resume DIR` then runs it. |
| `--resume RUN_DIR` | Continue a run from its last completed step. `--max-rounds` may be raised. |
| `-c, --config FILE` | Registry file (also `$RUNG_CONFIG`). |
| `--no-guard` | Do not wrap calls in the memory/time guard. |
| `-q, --quiet` | Only the final summary. |

Exit codes: 0 when finished (plateau or round cap), 1 on error, 2 on usage errors,
3 when paused because the integrator is unavailable (`rung --resume` continues
once it is back), and 130 when interrupted (every running call is stopped
first).

## The prompt file

The prompt file is Markdown. An optional front-matter block sets the run, and the
body is the task:

```markdown
---
models: codex, agy, ollama:glm-5.3 | ollama:kimi-k3, claude
integrator: claude
stage:
  - README.md
  - src/**/*.w
timeout: 1800
max_rounds: 4
deliverable: |
  One Markdown note: the bound, its proof, and how each claim is established.
---
# Tighten the bound in README.md

The README proves |S(n)| ≤ 3n. Find the best constant you can, and prove it.
```

| key | meaning |
|---|---|
| `models` | Ladder order. Use a comma list or a `- item` list; join models with `\|` to make a parallel step. |
| `integrator` | The model that merges answers. |
| `stage` (or `files`) | Files to stage, relative to the prompt file. Accepts globs with `*` and `?`, `**` for any depth, and directories. |
| `timeout`, `integrator_timeout` | Seconds per call. |
| `max_rounds` | Round cap (`0` for no cap). |
| `deliverable` | What the answer must be. The default is "one self-contained Markdown answer". |
| `retries`, `retry_wait` | Retries per failed call (default 2), and seconds between them (default 60). |
| `guard`, `guard_mem_mb` | `false` turns the guard off, or give another guard command. `guard_mem_mb` sets the memory cap. |
| `title` | Report title (default: the first heading). |

Command-line options win over the front matter, and the front matter wins over
the registry.

## Models

The built-in registry matches the standing ladder, with read-only modes on:

| model | command (abridged) | answer |
|---|---|---|
| `codex` | `codex exec -m gpt-6-astra … xhigh -s read-only -C {workdir} -o {answer_file} - < {prompt_file}` | file |
| `agy` | `agy -p "$(cat {prompt_file})" --model gemini-4-argon-high --print-timeout {timeout}s` | stdout |
| `grok` | `grok --prompt-file {prompt_file} -m grok-4.7 --reasoning-effort high --permission-mode dontAsk --no-subagents` | stdout |
| `carbon` | `agy -p "$(cat {prompt_file})" --model gemini-4-carbon-high --print-timeout {timeout}s` | stdout |
| `fable` | `claude -p --model claude-fable-5-2 --effort high --permission-mode plan < {prompt_file}` | stdout |
| `muse` | `muse exec --model muse-wonder-full-1.0 --reasoning-effort xhigh --workspace {workdir} --prompt-file {prompt_file}` | stdout |
| `claude` | `claude -p --permission-mode plan < {prompt_file}` | stdout |
| `ollama:<model>` | `ollama launch claude --model <model>:cloud -- -p --permission-mode plan < {prompt_file}` | stdout |

To change or add models, put entries in `~/.config/rung/models.toml` (or pass
`--config`). The file is merged over the built-ins key by key:

```toml
[defaults]
models = ["codex", "ollama:glm-5.3 | ollama:kimi-k3", "claude"]
integrator = "claude"
retry_wait = 120

[models.codex]
timeout = 900                      # only this key changes

[models.local]
command = 'llm -m local-model < {prompt_file}'
timeout = 600
check = 'llm models'               # exit 0 means "signed in" for rung models

[providers.ollama]
concurrency = 3                    # at most three ollama calls at once
shared = true                      # ... counted across every rung on the machine
```

The placeholders are `{prompt_file}`, `{workdir}`, `{answer_file}`, `{model}` (an
`ollama:*`-style name without its prefix) and `{timeout}`. Paths are substituted
shell-quoted. `answer = "file"` means the command writes `{answer_file}` itself.
Otherwise the answer is the command's stdout. A top-level `builtins = false` drops
the built-in models, which is useful for test registries.

## Parallel steps

`ollama:glm-5.3 | ollama:mistral-large-4 | ollama:kimi-k3` is one step. All its
members answer the same state at once, and each provider caps how many of its
calls run together: 3 for `ollama` and 1 for everything else, set with
`[providers.<name>] concurrency`. Calls from different providers in one group
always overlap. Every call keeps its own timeout, retries and guard.

The ollama cap is an account limit, so ollama is `shared`: its cap counts calls
from every rung process on the machine, not just this run. Each running call
holds a slot directory, `~/.cache/rung/slots/ollama.<i>` (or `$RUNG_SLOTS`). A
call that finds no free slot waits, and a slot whose owning process has died
is reclaimed. Other providers count per run unless you set `shared = true`.

The integrator then merges the whole group in one call. It sees every answer
side by side, keeps what is better, and names the contributors on its
`credit:` line. One call per group costs one integration instead of three, and
it lets the integrator weigh answers that disagree. Answers merged one at a
time would be judged in an arbitrary order.

## What happens

1. `state.md` starts out as the task. No answer has been accepted yet.
2. Each step writes every member's `prompt.md`: the task, the deliverable, the
   current state and "improve on this". Each call runs in its own work dir,
   which holds read-only copies of the staged files, and its answer is saved.
3. The integrator gets the task, the state and the step's answers. It returns
   `<rung-state>…</rung-state>`, the new state in full, and a
   `<rung-verdict>` block with `improved`, `credit`, `changed` and `verify`.
   An improved state replaces `state.md`. Otherwise the state is kept.
4. A round runs every step once. The ladder stops after a round with no
   improvement (a plateau), after a round in which every model or the
   integrator failed, or at the round cap.
5. `report.md` holds the final state, the credited improvements, the step log
   with timings, the claims still to verify, and every failure and skip.

A failed call is classified, and the report quotes the CLI's own line as
evidence:

| failure | example evidence | what rung does |
|---|---|---|
| usage limit | `You've hit your weekly limit · resets Nov 1`, `429 … session usage limit` | No retry, since waiting a minute cannot help. The model is skipped for the rest of the run. |
| model unavailable | `API Error: 410 … was retired` | Same as a usage limit. |
| rate limited | `429 Too Many Requests`, `overloaded` | Retried after `retry_wait` seconds, up to `retries` times. |
| not signed in, command not found | `Not signed in` | No retry. |
| timed out, exit code N, empty answer | the error line, not the CLI's warning noise | Retried. |

A model that still fails is skipped for that step, and the ladder goes on
without it. If the integrator fails with a usage limit, sign-in or
unavailability error, every later step would fail the same way. So rung
pauses at once (status `paused`, exit 3) without recording the step, and
`rung --resume` later redoes only that integration, reusing the answers.

## The run directory

```
task.rung/20261027-101500/
  rung.json        the frozen plan: ladder, integrator, resolved commands, timeouts
  task.md          the task
  stage/           read-only master copies of the staged files
  state.md         the current state
  status.json      created / planned / running / finished / paused / interrupted / failed
  log.md           one line per finished step
  report.md
  steps/r01-s01-codex/
    calls/codex/   prompt.md  work/  cmd.sh  answer.md  log.txt  meta.json
    integrate/     prompt.md  work/  cmd.sh  answer.md  log.txt  meta.json
    verdict.md  state.md  step.json
```

`step.json` marks a step done. `--resume` reruns only unfinished steps, and
within a step it reuses every call whose `meta.json` says `ok`.

## Safety

- rung only moves text. It never executes anything a model proposes, and the
  answers are only read.
- Models get copies, never the originals. Staged files are copied into each
  call's work dir with mode 0444, and the size of a stage is capped (200 files
  and 8 MB by default).
- Read-only modes are on in every built-in command: codex `-s read-only`,
  claude `--permission-mode plan`, grok `dontAsk`, and muse with its sandbox
  on. Every prompt also asks the model not to modify, build or run anything.
- No background processes outlive a call. Each call runs in its own process
  group with stdin from `/dev/null`. At its timeout it gets TERM, then KILL 10 s
  later, and on Ctrl-C rung stops every call before it exits. When
  `~/math/openai/tools/guard.sh` exists, each call also runs under it, which
  caps RSS (`guard_mem_mb`, default 4096) and wall time (timeout + 120 s).
- The prompts rung adds are generic. They contain no names, emails or machine
  paths, only your task text and the model names.

## Tests

```sh
BIT_HOME=$PWD/bits bin/tungsten bits/tungsten-rung/spec/rung_spec.w
```

The spec runs offline in a few seconds. It uses a registry of shell stand-ins
(echo, grep, sleep, and a fake integrator) with `builtins = false`, and covers
the parsers, the registry, staging, the reply format, plateaus, dry runs,
resumes, retries, timeouts, sign-in failures, answer files, read-only copies and
the provider concurrency cap.
