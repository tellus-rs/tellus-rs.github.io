+++
title       = "The death watch ordering guarantee"
description = "Why receiving Terminated proves that you have seen every message from that actor you will ever see."
weight      = 4
+++

An actor can watch another actor and then gets a signal once that actor has terminated. tellus
adds a guarantee to that signal: it arrives behind every message the terminated actor delivered to
the watcher. This page explains what the guarantee says, why it holds and what you can build on it.

## Watching

`context.watch(&actor)` registers interest in another actor's termination. Once that actor has
terminated, the watcher receives `Incoming::Terminated` with the terminated actor's `ActorId`, in
its ordinary mailbox, handled by `receive` like any message.

Watching is race-free: if the actor has already terminated, the signal is delivered right away.
A terminated signal is delivered even when the watcher's bounded mailbox is full, and it proves
that the terminated actor's destructors have run.

## The guarantee

Receiving `Terminated` proves that the watcher has seen every message from that actor it will
ever see. Each of them arrived before the signal or was dropped as a dead letter. None can arrive
after it.

{{<watch_diagram/>}}

## Why it holds

Messages from one sender arrive in the order they were sent, because a mailbox is a single FIFO
queue. A watch hands the watched actor a way to send into exactly that queue. When the watched
actor terminates, after its destructors have run, it sends the terminated signal this way. The
signal enters the same queue as all the messages it delivered to the watcher before, so it queues
up behind them.

The guarantee covers delivered messages only. `tell` delivers at most once: a message dropped as
a dead letter, for example because the watcher's bounded mailbox was full, never entered the
queue. That is why the guarantee says "seen every message it will ever see" and not "received
every message it sent". Messages which a task spawned by the actor sends on its behalf are not
covered either, because they do not come from the actor itself.

## What you can build on it

**Waiting for answers without timeouts.** An actor that asks several others and waits for their
answers can watch each of them. When `Terminated` arrives for one, its answer cannot come
anymore, so the actor stops waiting for it. The query actor in the
[tutorial](@/docs/tutorials/getting-started/query.md) works this way. It cannot wait forever for a
device that has terminated, and the only timeout is the one on `ask` at the boundary to the
outside world.

**Handovers.** An actor can send a final message before it stops, and its watcher knows that this
message comes before `Terminated`. In the [tutorial](@/docs/tutorials/getting-started/watch.md),
retiring devices hand over their last reading this way.

**Registries.** A parent that keeps its children in a map can watch them and remove an entry on
`Terminated`. Since nothing from that child can arrive afterward, no message ever comes from a
child that is no longer in the map.

## Unwatching

`context.unwatch(&actor)` reverts a watch. Its contract is absolute: after it returns, the watcher
never receives a terminated signal for that actor. This holds even if the signal is already
waiting in its mailbox. tellus enforces this on the watcher's side and drops such a signal before
`receive` sees it. Unwatch as soon as you no longer care, for example once an actor has answered.

## Across nodes

With the `cluster` feature, `context.watch` works on a reference to an actor on another node, too.
The guarantee then comes in two tiers, which the API does not tell apart.

A real termination keeps the full guarantee. The watched actor's node sends the terminated signal
over the wire as part of the actor's termination, behind every message the actor sent the watcher,
so it arrives behind all of them, exactly as within one process. It also proves that the actor's
destructors have run.

A node that crashes or is cut off cannot report anything. Once the cluster has downed that node,
see [Membership and downing](@/docs/explanation/membership-and-downing.md), the watcher gets a
synthesized signal instead. That signal promises less: the actor may still be running on the other
side of a partition, and its destructors may never run. It guarantees one thing, by construction:
no message from that actor is delivered on this node again. That is still enough for what the
guarantee is used for, such as a query that stops waiting for an answer that cannot come anymore.

Two more cases fire a synthesized signal without a downing, and they do not carry even that
promise. In the first, the watch cannot be sent: toward an address tellus refuses, toward a
connection bound to another incarnation, or while this node is downed or leaving. In the second,
tellus gives up connecting to an address that no member advertises, and signals every actor watched
there. Neither case marks the watched node down, so a message from the actor may still arrive
afterward. The API does not tell these signals apart from the others.

Unwatching stays absolute across nodes, and watching stays race-free: watching an actor that has
already terminated, or one on a node that is already down, signals right away.

For the implementation, see
[Death watch](https://github.com/tellus-rs/tellus/blob/main/docs/actors.md#death-watch) and, across
nodes, [Guarantees](https://github.com/tellus-rs/tellus/blob/main/docs/cluster.md#guarantees) in the
internals documentation.
