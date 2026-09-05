# Scheduler ownership and evented-idle tranche

This work keeps both existing execution topologies: independent cooperative
schedulers (used by Forge/Hammer workers), and the shared M:P scheduler. It
does not introduce a new G-M-P object model or change callback semantics.

## Ownership before synchronization

Cooperative runnable queues remain thread-local. Their enqueue and running
claims do not need compare-and-swap; the shared M:P path still does. M:P local
queues are single-producer, multiple-consumer FIFOs: the owner publishes the
tail, and owner/thieves claim the same head. Atomic slots protect speculative
reads during ring reuse. Positions are unsigned 64-bit values. A yielding
task rejoins the tail, and a periodic global-queue check bounds starvation by
local yielding tasks. This is not preemption or an I/O-latency bound.

A task marks itself PARKING before suspending but cannot become executable
until the scheduler has saved its context. An early wake records a notification
or hands off to the scheduler; it never publishes the still-running stack.
The winning waker finishes outcome and registration cleanup before publishing
RUNNABLE. Deadline removal and expiry claims share the wait's original lock,
including after membership has been removed. Goroutine and processor sizes
remain 256 and 2112 bytes respectively on ARM64.

Runtime yield/park boundaries are opaque to C inlining. Mutex ownership keeps
the stable goroutine identity across suspension instead of a cached address
of the old worker's TLS. An unbuffered goroutine receiver does not retain a
native pthread cleanup frame across migration; native receivers retain their
cancellation cleanup. This is not a general solution for arbitrary extension
code retaining TLS addresses across a migratable context switch.

## Eliminate redundant waits and scans

An idle cooperative scheduler enters one blocking event wait, bounded by its
nearest deadline. Already-ready I/O returns immediately from that wait. There
is no 64-call empty-poll prelude, and a completed batch exits without a final
empty event poll. In the baseline that terminal poll is normally nonblocking,
not a 1 ms sleep; measurements must not attribute a millisecond to its removal.

Cooperative deadlines live in indexed per-event-loop heaps. One worker no
longer locks and scans another independent worker's timers. The minimum is
O(1); insertion, update and eager cancellation are O(log n), with no allocation
per wait after heap capacity is established. A sticky kqueue user event or
Linux eventfd interrupts the poll if its deadline changes. The poller arms
wakeup delivery before snapshotting the minimum, covering updates immediately
before entry into the kernel. Kqueue uses that single snapshot with a
nanosecond timeout rather than rounding to milliseconds.

The raw deadline API only manages heap membership. A successful pop transfers
the detached record to its caller; a subsequent cancellation returning false
does not authorize freeing or reusing it until that consumer finishes. Concurrent
operations on one record must use the same externally assigned loop; separate
loop mutexes do not arbitrate initial ownership. Production scheduler expiry
uses the stronger detach-and-claim-under-lock protocol described above.

M:P deadlines retain their shared list so another worker can still expire a
wait when its original owner is busy. Removal is O(1), reusing the goroutine's
runnable link as the deadline predecessor while parked. Queue and deadline
membership are mutually exclusive.

## Remaining eventification work

1. M:P idle workers still use the existing 1 ms event-poll timeout. Replace it
   only together with coordinated enqueue, work-steal, earlier-deadline and
   shutdown notifications. A bare condition variable cannot also wake for
   socket readiness. Sleeping workers need a race-free arm/recheck protocol.
2. Core Timer still owns a native thread per timer and checks cancellation in
   5 ms slices. Share pending-timer coordination, while preserving native
   callback execution, cancellation guarantees and fixed-rate semantics.
3. Channel and mutex waits still retry through yield/sleep. Add wait queues,
   owner-routed wakeups and explicit transfer/close/cancel arbitration before
   removing those retries. Select needs one winner shared by all its arms.
4. Ready I/O can still be delayed by a continuously nonempty runnable queue.
   Add a measured, wait-aware dispatch budget or another notification path;
   removing idle spin is not a fix for busy-worker I/O fairness.
5. Generation-aware kernel registrations and complete cancellation of live
   tasks at shutdown remain separate work. Stop/restart tests here cover
   quiescent shutdown, not arbitrary cancellation and reclamation.

The existing [wait migration design](event-loop-waits.md) records the required
Timer/channel/select contracts. The
[public-API benchmark](../../benchmarks/concurrency/README.md) measures matched
runtime builds, exact results, CPU time and context switches. Scheduler
microbenchmarks are not a claim about whole HTTP applications.
