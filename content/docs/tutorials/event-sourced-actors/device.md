+++
title       = "An event-sourced device"
description = "Persist readings as events and recover the last one in a new actor system."
weight      = 1
+++

An event-sourced actor stores what happened, not what its state is. For a device, what happens is
that a reading is recorded. In this step the device persists every reading as an event, and a new
actor system over the same store recovers the last reading by replaying those events.

This tutorial needs the `persistence-in-memory` feature, which brings an in-memory store for
trying things out and for tests.

## Commands and events

{{<example path="tellus/examples/tutorials/event_sourced/01_device.rs" anchor="types"/>}}

The device still receives two messages, now called commands: `Record` and `Read`. What it persists
is an event, `Recorded`. Events are stored, so they implement `Serialize`, `Deserialize` and
`Versioned`. The manifest is a stable name for the event type, independent of the Rust type, and
the version allows the event to evolve later.

## The device

{{<example path="tellus/examples/tutorials/event_sourced/01_device.rs" anchor="device"/>}}

An event-sourced actor implements `EventSourced` instead of `Actor`. The work of `receive` is now
split in two:

- `handle` decides. It gets the current state by reference and returns an `Effect`. For `Record`,
  the effect persists a `Recorded` event. For `Read`, it persists nothing, and the reply runs in a
  continuation, `then`, which receives the state. A continuation runs only once the effect's events
  are durable and applied, and never on replay. That makes it the place for a reply, or for
  anything else that reaches beyond the actor. For an effect without events, like the one for
  `Read`, it runs right after `handle`.
- `apply` changes the state. It folds one event into the state and is the only state transition.

tellus appends the events to the store, and only then applies them. On recovery, it replays the
stored events through the same `apply`, so the recovered state is exactly the state the device
had.

`persistence_id` names the device's stream of events. Every incarnation of this device, today or
next year, reads and writes the same stream. `init` is the state before any event.
`init_from_snapshot` is unreachable here, because `Nothing` as the snapshot type means no
snapshots. [Snapshots](@/docs/tutorials/event-sourced-actors/snapshots.md) adds them.

## Talking to the device

{{<example path="tellus/examples/tutorials/event_sourced/01_device.rs" anchor="main"/>}}

`ActorSystem::event_sourced` spawns the root as an event-sourced actor, with a `Persistence` that
names the store. The first system records two readings and stops. The second system, a new
incarnation of the same device over the same store, starts without any reading in memory, replays
the two events and answers with the last one.

Notice the `ask` before the first `stop`. `stop` takes effect between two commands, so without
waiting for an answer, the queued readings might never be handled.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features persistence-in-memory --example event_sourced_01_device
```

It prints:

```txt
Last reading before stopping: 22.0
Last reading after recovery: 22.0
```

Both answers are the same: the second system has recovered the reading from the events alone.

## What you learned

An event-sourced actor decides in `handle` and changes its state only in `apply`. Its events are
stored before they are applied, and replaying them recovers the state. Next, the device fails.
