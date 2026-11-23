+++
title       = "Retry failed writes"
description = "Retry a failed batch with backoff, resend what was never acknowledged, and keep every entry in the store exactly once with keyed writes."
weight      = 80
+++

A write to a database fails now and then, for example when a connection resets. [Batch
writes](@/docs/how-to/batch-writes.md) lets such a failure fail the journal, which loses the entries
it was holding. On this page no entry is lost. The journal retries a failed batch with a growing
delay. When it gives up, its supervision restarts it, and the producer which sent the entries
resends what was never acknowledged. tellus delivers messages at most once and leaves
acknowledgments and redelivery to protocols built from messages, as [Message
delivery](@/docs/explanation/message-delivery.md#at-most-once) explains. The producer and the
journal form such a protocol.

Retrying raises a question: was the failed write committed? A connection can drop after the database
has written the rows and before the client has learned of it. After such an ambiguous commit, a
retry writes the rows a second time, unless the write is keyed. Every entry carries a sequence
number, and the store keeps one row per number. A repeated write hence changes nothing.

The examples on this page come from a producer which sends 2000 numbered entries to a journal. The
journal writes them in batches to a store stand-in. Writes fail in scripted ways. This page builds
on [Batch writes](@/docs/how-to/batch-writes.md) and assumes you know the [getting started
tutorial](@/docs/tutorials/getting-started/_index.md).

## The journal retries through a timer

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="journal"/>}}

The journal builds on the one of [Batch writes](@/docs/how-to/batch-writes.md). It writes one batch
at a time with `pipe_to_self`, and `write_if_due` starts a write once the mailbox has run empty or
`MAX_BATCH` entries, 100, are buffered. New entries wait in `pending`. The batch being written stays
in `in_flight` until its write has succeeded, so a failed batch can be written again. Each `Entry`
keeps its `ReplyTo` meanwhile, and the write gets a copy of the sequence numbers and texts.

An `Append` carries the entry's sequence number, its text and a `ReplyTo` for the acknowledgment.
The journal is `Timed`, since it retries through a timer, and `Retry` is the timer's message. Unlike
the journal of Batch writes, it has no `Close` message. The producer stops once every entry is
acknowledged, and the journal stops with it as its child. At that point every entry is in the store,
so stopping the journal loses nothing.

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="retry"/>}}

A successful write acknowledges every entry of the batch through the `ReplyTo` of its `Append`. A
failed write starts a timer under the key `retry`, and the timer's `Retry` writes the same batch
again. The entries which arrive meanwhile wait in `pending`, since `write_if_due` starts no batch
while one is in flight. So a retry never lets a later batch overtake the failed one. After
`MAX_ATTEMPTS` failed attempts, 3 in the example, the journal gives up and fails with
`WriteFailed::GaveUp`. A write which panicked is not retried: `result?` fails the journal with
`WriteFailed::Panicked`.

The delay comes from `retry_delay`, which doubles it with every attempt, starting at the minimum of
the journal's `Backoff` and capped at its maximum. `main` builds that `Backoff` from `BACKOFF_MIN`,
10 ms, and `BACKOFF_MAX`, 80 ms. So the journal waits 10 ms before the second attempt and 20 ms
before the third. The producer gives the same `Backoff` to the journal's `RestartPolicy`. A restart
of the journal hence waits 10 ms first and twice as long for every further consecutive restart, up
to 80 ms. `Backoff` hands out only its bounds, so `retry_delay` computes the same curve for the
retries itself.

Why a timer and not a sleep inside the piped future? A restart cancels an actor's timers, and
termination drops them. Neither cancels a future the actor has piped. A retry which sleeps inside a
piped future would hence still write after the journal has stopped. After a restart, its `Written`
would reach a new state which never started that write.

## The keyed write

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="write"/>}}

The store stand-in is a `Table` behind a lock, which `main` creates and the producer hands on to
the journal. Its rows map a sequence number to the entry's text. A write inserts every row whose key
is new and counts the rows it skips. `writes` counts the writes which reached the rows. Every write
first sleeps for `WRITE_LATENCY`, 2 ms. In PostgreSQL, for example, the write is an
`INSERT ... ON CONFLICT DO NOTHING`, and the error type is the database client's.

The failures are scripted by the entries a batch holds. The batch holding entry 301
(`RESET_BEFORE_WRITE_SEQ`) fails once before writing. The batch holding entry 901
(`RESET_AFTER_WRITE_SEQ`) writes its rows and then fails once, which is the ambiguous commit. The
batch holding entry 1501 (`GIVE_UP_SEQ`) fails `MAX_ATTEMPTS` times before writing, so the journal
gives up on it. Its next write, after the resend, succeeds.

The journal holds the store in its actor value, not in its state. A restart keeps the actor value,
so the restarted journal writes to the same table. Whether a retry can help depends on the error.
The example retries every `ConnectionReset`. An error which is permanent, such as a constraint
violation, fails every attempt the same way. Retrying it only delays the failure, so such an error
should fail the journal at once. The producer resends the same entries, so the error still stops the
journal for good once its restarts are used up.

## The producer keeps a window

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="producer"/>}}

The producer is the root of the actor system and the journal's parent. Its `init` spawns the journal
with a `Restart` strategy, whose `RestartPolicy` allows `MAX_RESTARTS` consecutive restarts, 2 in
the example. A journal which gave up hence starts over with an empty buffer. The producer also
watches the journal, for the case that the journal stops for good (see below).

The producer's state, `Sending`, holds the journal's reference, the next sequence number and the
open appends. `Acked` removes an append from the window and fills the window up again. Once all
`TOTAL` entries, 2000, are acknowledged, the producer stops. `AckTimeout` resends the open appends.

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="window"/>}}

The producer keeps at most `WINDOW` appends open, 256 in the example. An append is open from its
send until its acknowledgment, and it remembers when it was sent. Every `Append` carries a `ReplyTo`
from `context.reply_to`, which turns the journal's reply into an `Acked` message of the producer's
own protocol. When the journal loses an append, its `ReplyTo` is dropped without a reply. Such a
`ReplyTo` reports nothing then, so the producer watches the time instead. `append` starts the timer
`ack` with `ACK_TIMEOUT`, 500 ms, when an append enters an empty window.

The window also bounds the journal's buffer, which Batch writes leaves unbounded. Without a resend,
every entry the journal holds is an open append, so it never holds more than `WINDOW` entries. Every
resend can add another copy of each open append, so the bound holds only while writes complete (see
below).

## One timer for the oldest open append

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="ack-timer"/>}}

Acknowledgments need not arrive in order. A restarted journal keeps its mailbox but not its buffer.
So the appends still in its mailbox are written and acknowledged before the lost ones, which were in
flight or waiting in `pending`. The producer resends the lost ones only once their time is up. So an
acknowledgment removes its append wherever it sits in the window.

One timer is enough nonetheless. The front of the window always has the earliest send time, so it
is the first to time out. When the front goes, the timer restarts with the time remaining for the
new front. When the last open append goes, the timer is canceled. A replaced or canceled timer is
never received, even if it was due already. So once the front is acknowledged, the timeout started
for it never arrives.

An append which was resent before its first acknowledgment arrived can be acknowledged twice, once
per `ReplyTo`. The second acknowledgment finds nothing in the window and is ignored.

## Resending

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="resend"/>}}

When the timer fires, the producer resends every open append in order, each with a fresh `ReplyTo`.
A `ReplyTo` replies at most once, and the first one went with the lost append. The send times start
over, and the timer restarts with the full `ACK_TIMEOUT`.

The timeout has to be longer than the time the journal may need for a full window, with its retries
and one restart. Otherwise the producer resends appends which the journal still holds, and every
copy is written again only for the store to skip it. In the example a batch gets at most three
attempts of 2 ms each, with 10 and 20 ms between them, about 36 ms in all. A full window of 256
appends spans three batches of 100. The appends still in the journal's mailbox when it gives up on a
batch also wait for the restart, 10 ms for the first one. That comes to about 120 ms, and
`ACK_TIMEOUT` is 500 ms.

## A journal which stops for good

When the journal fails once more after `MAX_RESTARTS` restarts, with less than `reset_after` (30 s
by default) of failure-free running in between, it stops for good, as [Supervision and
lifecycle](@/docs/explanation/supervision-and-lifecycle.md#restarts-are-limited) explains. Only its
watchers learn of that. Without the watch, the producer would resend its window every 500 ms
forever, and every resent append would be a dead letter. So the producer watches the journal, and on
the terminated signal it fails with `JournalStopped`. The producer is the root and runs under the
default strategy, `Stop`. Its failure hence terminates the actor system, and `main` reads the store.
The scripted run never takes this path: the journal gives up once, and two restarts are allowed.

## What the recipe promises

Unless the journal stops for good or a write never completes, every entry reaches the store at least
once. A failed write costs a retry, and a batch the journal gave up on costs a resend. Every entry
is in the store exactly once, through the keyed write and not through delivery. A retry after the
ambiguous commit writes rows the store already has, and so does a resend of an append the journal
still held. The store skips them. The writes need not follow the order of the entries, since the
appends still in a restarted journal's mailbox are written before the resent ones. The store keeps
its rows by key, so their order does not depend on the order of the writes.

A write which never completes keeps its batch in flight forever. The producer then resends its
window every 500 ms, and the journal buffers every copy. Only a timeout around `write` covers that,
and database clients usually have timeouts of their own. The window lives in the producer's state,
so a producer which fails loses its record of what is unacknowledged. A producer which must
survive its own failure, or the end of the process, keeps that record durable, for example as an
[event-sourced actor](@/docs/explanation/event-sourcing.md).

## Run it

{{<example path="tellus/examples/how_to/retry_writes.rs" anchor="main"/>}}

`main` starts the actor system with the producer as its root and waits until it has terminated. Then
it reads the table and prints the number of rows, the writes which reached the rows, whether the
keys are exactly 1 to `TOTAL`, and the duplicate rows skipped. From a clone of the tellus
repository:

```sh
cargo run --quiet -p tellus --example how_to_retry_writes
```

```txt
Journal started
Retrying a batch of 100 entries in 10 ms: connection reset
Retrying a batch of 100 entries in 10 ms: connection reset
Skipped 100 duplicates
Retrying a batch of 100 entries in 10 ms: connection reset
Retrying a batch of 100 entries in 20 ms: connection reset
Giving up on a batch of 100 entries after 3 attempts: connection reset
Journal started
Resending 256 entries after 500 ms without an ack
2000 rows written in 21 batches, every key 1..=2000 present once: true, duplicate writes skipped: 100
```

The first `Retrying` line is for the batch holding entry 301, which failed before writing. Its retry
writes the rows. The second is for the batch holding entry 901, which wrote its rows and then
failed. Its retry finds all 100 keys present and skips them, which prints the only line of skipped
duplicates. The batch holding entry 1501 fails three times, and the journal gives up. Its
supervision restarts it after 10 ms with an empty buffer, which prints the second
`Journal started`. The producer resends its 256 open appends once the oldest of them has waited
500 ms, and the restarted journal writes them. The last line counts 2000 rows and 21 writes which
reached the rows: 20 batches of new rows and the retry which only skipped. The attempts which
failed before writing are not counted.

The batch sizes depend on scheduling, as in [Batch writes](@/docs/how-to/batch-writes.md#run-it). A
batch of fewer than 100 entries can change the sizes in the lines, the number of writes and the
duplicates skipped, but not the rows or the check of the keys.
