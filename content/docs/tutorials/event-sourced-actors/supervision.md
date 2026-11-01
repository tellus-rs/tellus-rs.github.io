+++
title       = "When devices fail, again"
description = "Let a failing event-sourced device restart and recover its state by replay."
weight      = 2
+++

In the [getting started tutorial](@/docs/tutorials/getting-started/supervision.md), a device which
failed on an invalid reading restarted with a fresh state and lost its last reading. An
event-sourced device restarts the same way, but it recovers its state from its events.

## Failing in handle

{{<example path="tellus/examples/tutorials/event_sourced/02_supervision.rs" anchor="handle"/>}}

`handle` validates a command before it causes any event. A reading which is not a number fails
the device: `handle` returns an error, and no event is persisted. The failure goes to the device's
supervision strategy, exactly as for a plain actor. The `Error` type is now `InvalidReading`, as
in the getting started tutorial.

## Restarting with replay

{{<example path="tellus/examples/tutorials/event_sourced/02_supervision.rs" anchor="main"/>}}

The device runs under the `Restart` strategy, which `ActorSystem::event_sourced_with_config` takes
in an `ActorConfig`. When the invalid reading fails the device, tellus restarts it. The restart
recovers the state by replaying the events from the store, just like the new actor system in the
previous step. The mailbox survives the restart, so the queued `Read` is handled by the recovered
device.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features persistence-in-memory --example event_sourced_02_supervision
```

It prints:

```txt
Last reading after the restart: 21.5
```

The plain device of the getting started tutorial had no reading in the same situation.

## What you learned

Validation belongs in `handle`, before any event exists. A failure restarts an event-sourced actor
like any other, and the restart recovers its state from the store. Next, recovery gets faster.
