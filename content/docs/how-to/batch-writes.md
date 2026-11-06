+++
title       = "Batch writes"
description = "Write buffered entries in batches, without blocking, starting a write once the mailbox has run empty."
weight      = 6
+++

A write to a database or a file costs a round trip or a system call, whatever its size, so writing
entries in batches is cheaper than writing them one by one. An actor must not block, so it cannot
write in `receive`. Instead it runs the write as a future with `context.pipe_to_self`, as described
in [Call async code from an actor](@/docs/how-to/call-async-code.md). That leaves the question of
when to start a write. A good moment is when the mailbox has run empty: `context.queued()` tells the
actor how many items in its mailbox it has not received yet. Under light load every entry is
written right away, and under heavy load the batches grow.

The examples on this page come from a journal actor which receives entries and writes them in
batches.

## One write at a time

{{<example path="tellus/examples/how_to/batch_writes.rs" anchor="journal"/>}}

The journal buffers every entry and then calls `write_if_due`, whatever the message. It has at most
one write in flight, so the writes happen in order. While a write runs, entries keep arriving and
wait in the buffer for the next one. When the write has finished, its future pipes `Written` back to
the journal, which may then start the next write.

## Write when the mailbox runs empty

{{<example path="tellus/examples/how_to/batch_writes.rs" anchor="write-if-due"/>}}

When no write is in flight, the journal starts one if `context.queued()` is 0. Then no entry follows
right now, and waiting longer would only delay the buffered ones. It also starts one when a full
batch is buffered. A write takes at most `MAX_BATCH` entries, so a batch never exceeds that size.

The buffer itself is not bounded. If entries arrive faster than the writes complete, it grows. To
keep a producer from overwhelming an actor, see
[Apply backpressure](@/docs/how-to/apply-backpressure.md).

## Why no entry is left behind

For the actor itself, `queued()` is a lower bound: only the actor removes items, and senders only
add them. If it is positive, at least one more message will be received, and `write_if_due` runs
again then. If it is 0, a message can still arrive right after, and the batch was merely written a
little early. Every `Written` runs `write_if_due` as well, so entries buffered during a write are
written after it.

## When a write fails

Every write must report back. Otherwise `writing` stays `true`, and the journal never writes again.
So `write` returns an `io::Result`, and the journal runs it on a task of its own with `task::spawn`.
`pipe_to_self` then awaits the task's `JoinHandle`, whose output is a `JoinError` if the write
panicked. Either way `Written` arrives, and `result??` turns a failure into the journal's error.

The journal then fails, and its supervision strategy decides what happens next. By default it
stops. With `Restart` it starts over with an empty buffer. The failure comes with the `Written` of
the only write in flight, so a restarted journal never receives a stale `Written`.

The entries still in the buffer are lost when the journal fails, in line with the at-most-once
delivery of tellus. Retrying a batch instead needs a backoff between attempts, which is a recipe of
its own. A write which never completes leaves the journal waiting forever. Only a timeout around
`write` covers that, and database clients usually have timeouts of their own.

## Stopping

{{<example path="tellus/examples/how_to/batch_writes.rs" anchor="main"/>}}

Stopping an actor drops the messages still in its mailbox, and the journal's buffer goes with its
state. tellus has no hook which runs when an actor stops, so the journal cannot write what remains
on its own. In the example, the pause after the last burst gives the journal time to write
everything before `main` stops the system. A real application drains the journal through its
protocol instead. For example, the journal can handle a message after which it writes what remains
and stops itself once the last `Written` has arrived.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --example how_to_batch_writes
```

```txt
Wrote a batch of 100 entries
Wrote a batch of 100 entries
Wrote a batch of 50 entries
Wrote a batch of 30 entries
Wrote a batch of 5 entries
```

`main` sends three bursts of 250, 30 and 5 entries, with a pause after each. The first burst
arrives faster than the journal handles it, so the first two writes take a full batch each. The
remaining 50 entries are written once the mailbox has run empty. During the pauses the mailbox runs
empty, so each of the later bursts becomes one batch. The batch sizes depend on scheduling and can
vary from run to run.
