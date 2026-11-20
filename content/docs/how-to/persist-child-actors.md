+++
title       = "Persist child actors"
description = "Spawn event-sourced children from a plain actor, persist a batch of events atomically and restart a timer after recovery."
weight      = 63
+++

An event-sourced actor does not have to be the root of its actor system. Any actor can spawn
event-sourced children with `context.spawn_event_sourced`, and each child recovers its own event
stream when it starts. What replay does not bring back is runtime state such as a timer, so a child
which needs one starts it again once it has recovered.

The examples on this page come from a building which spawns one event-sourced device per name. A
device persists batches of readings and forgets them once no new batch has arrived for a while.

## Spawn event-sourced children

{{<example path="tellus/examples/how_to/persist_child_actors.rs" anchor="building"/>}}

The building is a plain actor. It spawns a device on the first message for its name and forwards
every message to it as a command. `spawn_event_sourced` takes the actor and a `Persistence`, which
holds the store. The building keeps one and hands every device a clone, so all devices write to
the same store, each to the stream its `persistence_id` names. `spawn_event_sourced_with_config`
also takes an `ActorConfig`. Supervision, death watch and termination work as for plain children.
An event-sourced actor must also be `Sync` because tellus borrows it across store calls.

## Persist a batch atomically

{{<example path="tellus/examples/how_to/persist_child_actors.rs" anchor="handle"/>}}

A `Record` command carries a batch of readings, and `Effect::persist_all` turns it into one
`Recorded` event per reading. tellus appends the events of one effect atomically, so after a crash
the store holds the whole batch or nothing of it, and `apply` folds them in order. `Read` persists
nothing and replies once the command is settled. `Expire` persists an `Expired` event, so
forgetting the readings is part of the history too: a recovery after it replays the clearing.

## Start the timer again after recovery

The device declares `type Timers = Timed`, so its context can start timers. On every batch it
starts the expiry timer under the key `expire`, which replaces the timer of the previous batch:

{{<example path="tellus/examples/how_to/persist_child_actors.rs" anchor="expire-after"/>}}

A timer is runtime state. It is neither persisted nor recreated by replay, and a restart cancels
it. Replay only applies events and never calls `handle`, so a device which recovers its readings has
no timer which would expire them. `recovered` runs once after every recovery, at the first start as
after a restart, and starts the timer again:

{{<example path="tellus/examples/how_to/persist_child_actors.rs" anchor="recovered"/>}}

`recovered` starts the full delay again, counted from the recovery. To keep the original deadline
instead, record it in an event and start the timer in `recovered` with the time remaining.

`recovered` has the context needed to start timers, spawn children or register with other actors
after recovery. `init` has no context and is skipped when a snapshot is loaded. A `then`
continuation receives only the state, so it cannot start a timer either.

## Run it

{{<example path="tellus/examples/how_to/persist_child_actors.rs" anchor="main"/>}}

The first actor system records a batch for each device and reads them back, then stops. The second
actor system starts on the same store. From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features persistence-in-memory --example how_to_persist_child_actors
```

```txt
Device left: 21.5, 22.0, 22.4
Device right: 19.1, 19.4
Device left recovered 3 readings
Device left: 21.5, 22.0, 22.4
Device right recovered 2 readings
Device right: 19.1, 19.4
Device left: no readings
Device right: no readings
```

In the first actor system the devices have nothing to recover, so `recovered` prints nothing. In the
second one, the building spawns each device again on its first `Read`. The device recovers its
readings and starts its timer again in `recovered`. After twice `EXPIRE_AFTER`, both timers have
fired, and the devices have forgotten their readings.
