+++
title       = "Rust actor frameworks compared"
description = "How tellus differs from actix, kameo and ractor: message handlers, mailboxes, supervision, death watch, clustering and persistence."
weight      = 8
+++

Rust has several actor frameworks. This page compares tellus with three widely used ones:
[actix](https://crates.io/crates/actix), [kameo](https://crates.io/crates/kameo) and
[ractor](https://crates.io/crates/ractor). It describes tellus 0.5.2, and actix 0.13.5, kameo
0.22.2 and ractor 0.16.5 as of October 2026. The facts about the other three come from their own
documentation and source code.

The maintainers of tellus wrote this page, so read it with that in mind. If something about
another framework is wrong or out of date, please
[open an issue](https://github.com/tellus-rs/tellus-rs.github.io/issues).

## At a glance

<div class="table-wrap">

| | tellus | actix | kameo | ractor |
|---|---|---|---|---|
| Runtime | Tokio | actix-rt, a single-threaded Tokio runtime per arbiter | Tokio | Tokio or async-std |
| Message handler | synchronous | synchronous, can return a future | `async` | `async` |
| State | passed in by value, returned | `&mut self` | `&mut self` | `&mut State` |
| Message types per actor | one | one `Handler<M>` per type | one `Message<T>` per type | one |
| Mailbox, unbounded / bounded | ✓ / ✓ | ✓ / ✓ | ✓ / ✓ | ✓ / ✗ |
| Supervision | restart with limit and backoff, or stop | restart hook on the same actor | one-for-one, one-for-all, rest-for-one, with limit | supervisor is notified, restarts are your code |
| Death watch | `watch`, ordered behind messages | none | links | links and monitors |
| Clustering | built in, QUIC | none official | built in, libp2p | `ractor_cluster` crate, TCP |
| Persistence | event sourcing | none | none | none |
| Unit testing handlers | `TestContext` | none | none | none |
| First release | 2026 | 2017 | 2024 | 2023 |

</div>

The sections below explain each row.

## Message handlers

The biggest difference is how an actor handles a message. In kameo and ractor, the handler is an
`async fn`. It can await a database query or a reply from another actor while it handles a message.
The actor handles no other message in the meantime.

In tellus, `receive` is a plain function. It takes the state by value and returns the next one, so
an actor is a state machine. Async work runs on its own task with `pipe_to_self`, and its result
arrives as a message. [Synchronous message handlers](@/docs/explanation/synchronous-handlers.md)
explains why tellus is designed this way. The cost is an extra message and an explicit state where
an async handler would simply await.

actix sits in between. Its `handle` is synchronous, too, but it can return a future with access to
the actor's state, a `ResponseActFuture`. Wrapped in an `AtomicResponse`, the future keeps the
actor from handling other messages until it completes.

The frameworks also keep the state in different places. actix and kameo keep it in the actor
itself, behind `&mut self`. ractor passes a separate `&mut State` into `handle`, next to a shared
`&self`. tellus separates the two as well, but passes the state by value, so it always has exactly
one owner.

## Messages and addresses

In tellus and ractor, an actor has one message type, usually an enum. Its address is typed by that
message type, `ActorRef<M>`, and a `match` in the handler shows every message the actor
understands.

In actix and kameo, an actor implements a handler trait once per message type: `Handler<M>` or
`Message<T>`. Each implementation has its own reply type. The address is typed by the actor,
`Addr<A>` or `ActorRef<A>`, and a `Recipient<M>` refers to any actor which handles `M`.

## Mailboxes

kameo bounds a mailbox to 64 messages by default, to apply backpressure: a sender which awaits its
send waits for space. actix bounds a mailbox to 16 messages by default, and a capacity of 0 makes
it unbounded. Its `send` returns a future which waits for space, while `do_send` ignores the limit.
ractor's mailboxes are always unbounded. Only its factories, which distribute work across a pool of
workers, can bound their queue and discard messages beyond it.

A tellus mailbox is unbounded by default. A bounded one never makes the sender wait: `tell` drops a
message which does not fit and logs it as a dead letter. Replies the actor asked for, the outputs
of its piped futures and terminated signals still get in.
[Message delivery](@/docs/explanation/message-delivery.md) describes these rules, and
[Apply backpressure](@/docs/how-to/apply-backpressure.md) shows how a consumer pulls its work
instead.

## Supervision

All four frameworks can restart a failed actor, but they build in different amounts of it.

In actix, a `Supervisor` restarts an actor when it stops. It does not create a new actor but calls
the `restarting` method of the same one, which keeps its fields. There are no restart limits, no
backoff and no tree of parents and children.

In ractor, actors spawned with `spawn_linked` form a tree. When a child fails, with an error or a
panic, its supervisor receives a `SupervisionEvent`. Whether the child restarts is up to the
supervisor's code, since ractor has no restart strategies for actors in general. Its factories do
replace failed workers.

kameo has had supervision trees in the style of Erlang/OTP since version 0.20. A supervisor
restarts its children one for one, all for one or the rest for one. A restart limit, by default 5
restarts within 5 seconds, stops a child that keeps failing.

In tellus, every actor except the root has a parent, and its supervision strategy decides what
happens when it fails. `Stop`, the default, terminates it. `Restart` stops its children, waits a
backoff delay and runs `init` again for a fresh state. The delay doubles with every consecutive
restart, and an actor which fails again after `max_restarts` restarts stops for good. tellus
supervises each actor on its own; it has no strategy which restarts siblings together.
[Supervision and lifecycle](@/docs/explanation/supervision-and-lifecycle.md) has the details.

## Death watch

An actor often needs to know that another one is gone. In kameo, linked actors learn about each
other's death in `on_link_died`. In ractor, the supervisor receives a `SupervisionEvent`, and with
the `monitors` feature any monitoring actor does, too. actix has no such mechanism.

tellus adds an ordering guarantee to it. A watcher receives `Terminated` only after every message
the terminated actor delivered to it, so the signal proves that no more messages from that actor
will come. The query actor of the
[getting started tutorial](@/docs/tutorials/getting-started/query.md) relies on this to collect
answers from many devices without a timeout. Neither kameo nor ractor documents an order between
the notification and the actor's earlier messages.
[The death watch ordering guarantee](@/docs/explanation/death-watch-ordering.md) explains how tellus
keeps it.

## Clustering

tellus has clustering behind the `cluster` feature. An `ActorRef` is serializable, and `tell`, `ask`
and `watch` work across nodes through the same API. Nodes talk QUIC with mutual TLS and find each
other through seeds, DNS or Kubernetes. They gossip the membership, detect failures and down
unreachable nodes. A receptionist finds actors by key across the cluster, and pub-sub is built on
top of it. The cluster singleton and sharding are next on the roadmap. tellus aims at clusters of
tens of nodes; [Membership and downing](@/docs/explanation/membership-and-downing.md) explains how
its nodes agree on who belongs.

kameo has remote actors behind the `remote` feature, built on libp2p. Actors register under a name
in a distributed hash table and are looked up with `RemoteActorRef::lookup`. Its documentation says
that the quick `bootstrap()`, which finds peers via mDNS, "may not be suitable for production
deployments".

ractor's clustering is the separate crate `ractor_cluster`: TCP with optional TLS, and process
groups synchronized across nodes. Its README says that it "shouldn't be considered production
ready, but it is relatively stable".

actix has no official clustering. A few third-party crates exist.

## Persistence

tellus has event-sourced actors behind the `persistence` feature. Their events are appended to a
store before they are applied, and the state is recovered by replaying them, optionally from a
snapshot. `tellus-persistence-postgres` provides a PostgreSQL store.
[Event sourcing](@/docs/explanation/event-sourcing.md) explains the guarantees. None of the other
three frameworks has persistence built in or in an official crate.

## Testing

tellus has `TestContext` behind the `test-util` feature. With it, a test calls `receive`, `handle`
and `apply` directly, without an actor system, and checks the returned state and the messages sent,
as [Unit test an actor](@/docs/how-to/unit-test.md) shows. As far as their documentation goes, the
other three test an actor by spawning it. actix provides `#[actix::test]`, which runs a test inside
an actix system.

## Runtime

tellus, kameo and ractor run on a plain multi-threaded Tokio runtime, and ractor also supports
async-std. actix runs on its own runtime, actix-rt. Each arbiter is one thread with a
single-threaded Tokio runtime, and an actor stays on the arbiter it was started on. Blocking work
goes to a `SyncArbiter`, a pool of threads.

## Performance

The [comparison dashboard](https://tellus.rs/tellus/comparison/) measures the messaging throughput
of tellus against kameo and ractor for every release, under the same rules for all three. actix is
not included, because it runs actors on single-threaded arbiters rather than on a shared Tokio
runtime. The benchmarks are microbenchmarks: they say nothing about supervision, distribution or
ergonomics. And tellus's synchronous `receive` gives it an advantage in exactly these benchmarks,
since it neither allocates nor polls a future per message.

## Which one to choose

Choose kameo when you want async handlers, actors which handle many message types and supervision
strategies in the style of Erlang/OTP. Choose ractor when you want Erlang's gen_server model in a
framework with production use, and you are fine writing restart logic yourself. actix fits a
project which already uses it; for a new one, keep in mind that its releases have become rare and
that it has neither a supervision tree nor a death watch.

Choose tellus when you want actors as typed state machines, restarts with backoff, a death watch
you can rely on, event sourcing and a cluster, all from one crate. tellus also lets you unit test
`receive` without a running system. In return, accept that tellus is young. The
[getting started tutorial](@/docs/tutorials/getting-started/_index.md) is the quickest way to find
out whether it suits you.
