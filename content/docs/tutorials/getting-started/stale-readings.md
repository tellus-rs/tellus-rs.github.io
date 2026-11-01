+++
title       = "Stale readings"
description = "Let devices forget old readings with a timer, which an actor opts into by its type."
weight      = 8
+++

A sensor which goes silent keeps its last reading forever, so the averages keep counting a
temperature that may be hours old. In this step a device forgets its reading once it has received
no new one for a while. The manager, the groups and the query are those from the previous step,
unchanged.

## A timer per device

{{<example path="tellus/examples/tutorials/getting_started/08_stale_readings.rs" anchor="stale-after"/>}}

{{<example path="tellus/examples/tutorials/getting_started/08_stale_readings.rs" anchor="device"/>}}

The device declares `type Timers = Timed`. This gives its context two more methods, `start_timer`
and `cancel_timer`. `init` and `receive` always take `ActorContext<Self::Message, Self::Timers>`.
The earlier steps could write `ActorContext<Self::Message>`, because the context's second type
parameter defaults to `Untimed`, which is what their actors declare. The device has to name
`Self::Timers`. Every other actor keeps `Untimed`, and its context has no `start_timer` at all. An
actor can only start a timer if its type says so, and an untimed actor runs without the
bookkeeping timers need.

On `Record`, the device calls `start_timer` with a key, a message and a delay. Once `STALE_AFTER`
has elapsed, the device receives `Expire`, as if it had told itself, and it forgets its reading.

## One timer per key

The key names the timer. Starting a timer under a key which is in use replaces the timer, so every
`Record` pushes the deadline back. A device which keeps reporting never receives `Expire`.

A replaced timer is never received, even when it was already due. A timer's message is also handled
behind everything that was queued when the timer fired. So a `Record` which arrived before the
deadline is handled first, replaces the timer, and the fresh reading stays.

## Timers and restarts

A device which fails on an invalid reading restarts without a reading, as in
[step 6](@/docs/tutorials/getting-started/supervision.md). The restart also cancels its timers,
since they belong to the old state. No `Expire` from before the restart reaches the new state.

## Talking to the manager

`main` is like the one of the previous step. It records readings for `left`, `right` and `window`
in the attic and for `boiler` in the cellar, retires `right` and asks all three groups for their
average. What follows is new:

{{<example path="tellus/examples/tutorials/getting_started/08_stale_readings.rs" anchor="rounds"/>}}

`print_averages` is the loop over the three groups from the previous step, moved into a function.
After the first round, `main` waits for twice `STALE_AFTER`, records a new reading for `left` and
asks again.

Why ask before waiting? A device starts its timer when it handles its `Record`, not when `main`
sends it. The group tells each device its `Record` before the query sends its `Read`, and both
arrive in the device's mailbox in that order. So when the first answers arrive, every device has
started its timer, and the wait begins after that.

## Run it

From a clone of the tellus repository:

```sh
RUST_LOG=tellus=debug cargo run --quiet -p tellus --example getting_started_08_stale_readings
```

On stdout it typically prints:

```txt
Average temperature in attic: 19.65
Average temperature in cellar: 11.00
No readings in garage
Average temperature in attic: 22.30
No readings in cellar
No readings in garage
```

In the first round the attic averages `left` and `window`, since `right` retired. In the second
round `window` has gone stale, so only the new reading of `left` counts. The cellar's `boiler` has
gone stale, too.

The timing leaves a margin of a full `STALE_AFTER` on both sides, but it is not guaranteed. On a
heavily loaded machine a device can get to its `Expire` only after the second query's `Read`.

## What you learned

A timer lets an actor send itself a message after a delay. Timers are opt-in: only an actor whose
`Timers` type is `Timed` can start one. Starting a timer under a key in use replaces it, and a
restart cancels all of them.

## Where to go from here

You have used the core features of tellus: actors with state, `tell` and `ask`, child actors,
watch with its ordering guarantee, supervision and timers.

The next tutorials build on this one.
[Event-sourced actors](@/docs/tutorials/event-sourced-actors/_index.md) makes the devices survive
restarts, and [Clustered actors](@/docs/tutorials/clustered-actors/_index.md) spreads them across
nodes.
