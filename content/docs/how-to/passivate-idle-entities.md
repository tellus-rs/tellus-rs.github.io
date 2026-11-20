+++
title       = "Passivate idle entities"
description = "Spawn one actor per key on its first message with a Host, and stop it again once no message has reached it for a while."
weight      = 55
+++

Some actors belong to a key: a session per visitor, a cart per customer, an account per account
number. Spawning all of them up front is rarely possible, and keeping every one alive forever
wastes memory. A `Host` spawns an entity, an actor identified by its key, on the first message for
that key. With an idle timeout, it also passivates the entity once no message has been routed to it
for that long. The next message for the key spawns a new incarnation.

The examples on this page come from a host of session actors, one per visitor of a website. A
session counts the visits of its visitor.

## Spawn a host

{{<example path="tellus/examples/how_to/passivate_idle_entities.rs" anchor="main"/>}}

`Host::new` takes a `HostConfig` and a function which spawns the entity for a key.
`HostConfig::default()` keeps every entity alive, and `with_idle_timeout` turns passivation on. It
fails for a zero timeout. The function gets the key and the host's context. It must spawn a fresh
child through that context on every call, here with `context.spawn`, and must not return an actor
it has returned before. One entity per key and the delivery of buffered messages rest on that, and
the signature cannot enforce it.

The host is the root actor here, so `system.root()` is its reference. Its messages are
`HostEnvelope { key, message }`, and `tell` and `ask` reach an entity through it. The `visit`
helper of the example asks the host with an envelope naming the visitor and carrying a `Visit`:

{{<example path="tellus/examples/how_to/passivate_idle_entities.rs" anchor="visit"/>}}

`main` sends three visits, waits until the session of alice has been passivated and then visits
once more as alice.

## Handle the host's messages

An entity's message type is `Hosted<M>`, where `M` is its domain message, here `Visit`. The host
wraps every message routed to it in `Hosted::Message` and asks it to stop with `Hosted::Passivate`:

{{<example path="tellus/examples/how_to/passivate_idle_entities.rs" anchor="receive"/>}}

Only an actor itself or its parent can stop it, so the host asks, and the session stops itself with
`Control::Stop`. It also tells `main` through a channel, which the example needs only to know when
to visit again. A `HostEnvelope` carries the bare `Visit`, so a client cannot request a passivation
through the host, and `Visit` needs no stop variant.

## What to keep in mind

**Passivation drops the state.** The next incarnation starts from `init`. Passivate only entities
whose state is disposable, like these sessions, or recoverable. An event-sourced entity, spawned
with `context.spawn_event_sourced`, recovers its state from the store in its next incarnation, see
[Event sourcing](@/docs/explanation/event-sourcing.md#recovery).

**Only routed messages count.** Messages told to an entity's reference directly, the replies and
piped outputs it receives and its own timers do not reset the idle time. An entity busy with those
alone is idle to the host.

**Idle entities are found by periodic checks.** The host checks once per idle timeout. It asks an
entity to passivate on a check after the entity has been idle for at least one timeout. Scheduling
and messages queued for the host can delay a check. A full mailbox refuses `Hosted::Passivate`, and
the host then asks again at the next check. Once asked, the entity still has to handle the request
and stop.

**Messages wait while an entity stops.** From the moment the host has sent `Hosted::Passivate`, it
buffers the messages routed to that entity until the entity has terminated. Then it spawns the next
incarnation and delivers them in order, so the order of one sender holds across a passivation. The
buffer holds 64 messages per entity unless `HostConfig::new` sets another size. Beyond it, the
newest message is dropped as a dead letter. An entity which does not stop on `Hosted::Passivate`
keeps the messages buffered until it stops.

**Timers end with the old incarnation.** The pending timers of an entity end when it stops. Its
next incarnation starts without them, but it can start fresh ones in `init`, or in `recovered` for
an event-sourced entity. Nothing wakes a passivated entity at a deadline.

**An entity which stops on its own is replaced.** If an entity stops by itself, for example after a
failure under `SupervisionStrategy::Stop`, the next message for its key spawns a new one. Until the
host has received its terminated signal, the messages routed to it are dead letters.

**A host is local.** `HostEnvelope` and `Hosted` implement no `Schema`, so neither the host's nor an
entity's reference crosses nodes. A client on another node reaches an entity through a local actor
of the application which forwards to the host.

**The configuration can come from a file.** With the `serde` feature, `HostConfig` is
deserializable like the actor configuration, see
[Configure an actor from a file](@/docs/how-to/configure-supervision.md). Both fields are optional:
an omitted `buffer` is 64, and an omitted `idle_timeout` leaves passivation off. A zero idle
timeout is refused there as well.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --example how_to_passivate_idle_entities
```

```txt
Session of alice started
alice visits /
Visits in the session of alice: 1
Session of bob started
bob visits /
Visits in the session of bob: 1
alice visits /pricing
Visits in the session of alice: 2
Session of alice passivated
Session of bob passivated
Session of alice started
alice visits /signup
Visits in the session of alice: 1
```

The first visits of alice and bob start their sessions, and the second visit of alice reaches the
existing session, which counts 2. Once both sessions have been idle for the idle timeout,
the host passivates them; the two lines come in either order. The last visit of alice then starts a
new session, which counts from 1 again.
