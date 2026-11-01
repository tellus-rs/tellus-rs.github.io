+++
title       = "Apply backpressure"
description = "Keep a fast producer from overwhelming slow actors with work pulling, and bound mailboxes safely."
weight      = 4
+++

`tell` never blocks. If a producer sends faster than an actor can handle, the mailbox grows. By
default it grows without limit. A bounded mailbox grows until it is full, and then further messages
are dropped. Neither slows the producer down. For backpressure, let the consumers decide when they
get work: with work pulling, a worker asks for the next job when it is ready for it.

The examples on this page come from a manager which owns a queue of documents and three workers
which count their words.

## Let workers request jobs

{{<example path="tellus/examples/work_pulling.rs" anchor="request"/>}}

A worker sends a `RequestJob` to the manager. The request carries a `ReplyTo` for the answer,
which is `Next`, the worker's own message type. The worker requests its first job in `init`:

{{<example path="tellus/examples/work_pulling.rs" anchor="init"/>}}

In `receive`, it handles the answer:

{{<example path="tellus/examples/work_pulling.rs" anchor="work"/>}}

After each job, the worker requests the next one. When there is no work left, it stops.

## Hand out one job per request

{{<example path="tellus/examples/work_pulling.rs" anchor="hand-out"/>}}

The manager answers each request with exactly one job, or with `Drained` when the queue is empty.
A `ReplyTo` can reply only once, so one request can never get more than one job. The queue stays
in the manager, where it is visible and can be bounded, instead of being spread over the workers'
mailboxes.

## Size the mailboxes by the protocol

{{<example path="tellus/examples/work_pulling.rs" anchor="spawn"/>}}

A worker has at most one job in flight, so its mailbox never holds more than one message, and a
capacity of one documents that bound. The capacity never drops a job anyway: the jobs arrive as
replies to the worker's `ReplyTo`, which a full mailbox takes as well.

The same argument bounds the manager's mailbox:

{{<example path="tellus/examples/work_pulling.rs" anchor="system"/>}}

Each worker has at most one request in flight, so the manager never holds more requests than there
are workers. When the protocol bounds the number of messages in flight like this, the capacity
documents and enforces that bound.

The capacity must not be smaller than that bound. A dropped request takes its `ReplyTo` with it, and
nothing ever answers the worker. With a capacity of one for the manager, a first request can be
dropped when it arrives while the mailbox still holds another one. The workers whose requests got
through still process all documents. But a worker whose request was dropped never stops, so the
manager waits for it forever. To see it happen, lower the manager's capacity in the example to one
and run it with `RUST_LOG=warn`. When a request is dropped, the dead letter in the log tells why.

## Bound every mailbox

A bounded mailbox is not backpressure. When it is full, `tell` drops the newest message and logs it
at warn level as a dead letter, with the actor ID and the message type. An `ask` to a full mailbox
fails with `AskError::MailboxFull`. A terminated signal, a `reply_to` reply, the output of a piped
future and the messages a `Host` buffered while passivating an entity are enqueued even when the
mailbox is full. All but the terminated signal still count against the capacity, so ordinary tells
are dropped and asks fail until the mailbox has drained back under it. A message forced past the
capacity this way is still a dead letter if the actor has terminated.

Still, bound every mailbox. An unbounded mailbox hides overload until the process runs out of
memory. A bounded one caps the memory taken by ordinary messages and reports every dropped message
in the log. Size it by the number of messages the protocol allows in flight, as above. Where the
protocol does not bound them, size it by the largest burst the actor should absorb, and decide what
a dropped message costs:

- A dropped periodic reading costs little, because the next reading follows soon anyway.
- A dropped request costs its answer. From outside an actor, send it with `ask`, which fails with
  `AskError::MailboxFull` right away. Between actors, bound the requests in flight by the
  protocol, as work pulling does.

The capacity does not cap what the actor started itself. Each future it piped and each `ReplyTo` it
has open can add one message past the capacity, and nothing limits how many of them are open. An
actor which pipes a future or opens a `ReplyTo` per request to a slow backend can hence hold far
more messages than its capacity. Bound its open requests, e.g. with a window.

The default is unbounded only because no capacity fits every actor. Configure the capacity with
`ActorConfig`, in code as above or [from a file](@/docs/how-to/configure-supervision.md).

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --example work_pulling
```

```txt
## 7 words in: a terminated signal arrives behind all messages
## 5 words in: one message at a time
## 3 words in: backpressure by design
## 9 words in: the quick brown fox jumps over the lazy dog
## 5 words in: actors all the way down
## 6 words in: workers pull instead of being pushed
## All documents processed
```

The three workers run concurrently, so the order of the lines varies from run to run.
