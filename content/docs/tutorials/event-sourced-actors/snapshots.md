+++
title       = "Snapshots"
description = "Shorten recovery with snapshots, so a device does not replay its whole history."
weight      = 3
+++

A device which has recorded a reading every second for a year has a long history. Replaying all of
it on every start takes time. A snapshot stores the state at some point, so recovery starts from
the latest snapshot and replays only the events after it.

## The state as a snapshot

{{<example path="tellus/examples/tutorials/event_sourced/03_snapshots.rs" anchor="readings"/>}}

The state now also counts the readings, so `snapshot` can decide when one is due. It doubles as the
snapshot type, so it is `Versioned` like an event.

{{<example path="tellus/examples/tutorials/event_sourced/03_snapshots.rs" anchor="apply"/>}}

Once the events of an effect have been applied and its continuations have run, tellus asks
`snapshot` whether one is due. An effect without events, like the one for `Read`, is never followed
by a snapshot. The device offers one after every third reading.

{{<example path="tellus/examples/tutorials/event_sourced/03_snapshots.rs" anchor="init"/>}}

On recovery, if there is a snapshot, `init_from_snapshot` turns it into the state, and only the
events after the snapshot are replayed. Without a snapshot, `init` is the starting point, as
before. `init` must stay pure, because it is skipped as soon as a snapshot exists. Work
which touches the world at start, like spawning children, belongs in `recovered`, which runs after
every recovery.

A snapshot is never the source of truth; the events are. If a snapshot cannot be saved, or can no
longer be decoded later, recovery replays more events.

## Talking to the device

{{<example path="tellus/examples/tutorials/event_sourced/03_snapshots.rs" anchor="main"/>}}

The snapshot store is configured with `with_snapshot_store`. The in-memory store serves both roles.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features persistence-in-memory --example event_sourced_03_snapshots
```

It prints:

```txt
Stored events: 7, the snapshot covers the first 6
After recovery: 7 readings, the last one 22.3
```

The second system starts from the snapshot after six readings and replays only the seventh event.

## What you learned

Snapshots shorten recovery. `snapshot` decides when one is due, `init_from_snapshot` starts from it,
and the events remain the source of truth. Finally, the device moves to a real database.
