# Item 15: migrate waits without changing concurrency contracts

Current source: `core/timer.w` starts one native Thread per timer and checks
cancellation at most every 5 ms. `Channel.select` rotates nonblocking probes
and sleeps 100 microseconds. Runtime channel/mutex waits likewise yield or
sleep. Socket I/O already parks goroutines through `runtime/event_loop.h`.

I propose one shared wait-registration protocol, integrated in stages:

1. Add monotonic deadline heaps and a cross-thread wakeup source to the existing
   kqueue/epoll backends. The next heap deadline bounds the blocking poll. A
   newly earlier deadline or cancellation must wake an already blocked poll.
2. Move **waiting timers** onto this heap. Dispatch due callbacks onto native
   Threads initially, preserving their current blocking/thread-local behavior.
   This removes one sleeping Thread per pending timer without silently turning
   callbacks into cooperative goroutines. Reuse the current WAITING/CALLBACK/
   TERMINAL claim and fixed-rate skip-missed-ticks semantics.
3. Add parkable single-channel waits. Register under the channel lock, recheck
   readiness, then atomically park. Send/receive/close detaches and claims
   waiters under that same lock, and schedules them after releasing it.
4. Implement select with one shared winner token and one registration per arm.
   All registrations carry a generation. The winning arm commits its transfer;
   losers are removed before returning. Timeout and close compete through the
   same state transition, preventing two sends or a lost received value.
5. Migrate mutex waits after channels prove the protocol; keep ordinary native
   threads on condition variables and preserve cooperative scheduler progress.

The wait token is `WAITING -> READY | TIMED_OUT | CANCELLED`, transitioned once.
Its lifetime extends until every backend registration is detached, including
late kernel events. A generation prevents a recycled goroutine address from
waking a different wait. Wakers enqueue through the scheduler's deduplication
path. Cancellation has an explicit result; it never silently consumes a
channel value. Zero-duration operations remain nonblocking probes.

Timer cancellation retains its existing meaning: true guarantees the next
callback will not start; false may mean one is already running. `wait` still
joins completion and re-raises callback errors. Repeating callbacks remain
non-overlapping and advance from their previous monotonic deadline.

Rollout should be opt-in by backend until existing channel rendezvous/timeout,
Timer cancellation/error, and socket deadline specs pass in native-thread,
cooperative, and M:P contexts. Add deterministic barriers around the
register/recheck/park and claim/cancel races, plus churn tests that recycle
waiters while close/timeout fires. Measure 1/100/10,000 idle timers and blocked
channels: CPU time, native-thread count, memory, and wakeup p50/p99. Idle CPU
and waiting-thread count should fall without regressing wakeup tails or
changing cancellation outcomes.

This entry is the requested migration proposal. It does not change the default
scheduler or claim that polling has already been removed. The first concrete
implementation should be the deadline/wakeup backend API; a timer-only patch
without interrupting a blocked poll would have a lost-wakeup bug.
