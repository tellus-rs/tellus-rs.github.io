+++
title       = "When devices fail"
description = "Let failing actors restart with backoff, and stop them when they keep failing."
weight      = 6
+++

Sensors are flaky. Sometimes a device reports a reading that is not a number at all. In this step
such a reading makes the device fail, and tellus restarts it.

## Failing

{{<example path="tellus/examples/tutorials/getting_started/06_supervision.rs" anchor="device"/>}}

The device's `Error` type is now `InvalidReading` instead of `Infallible`, a unit struct deriving
`thiserror::Error`. For a reading that is not a number, `receive` returns `Err(InvalidReading)`.
You can also use `?` to escalate a failure the same way. A panic in `receive` counts as a failure,
too.

What happens next is up to the device's supervision strategy.

## Restarting

{{<example path="tellus/examples/tutorials/getting_started/06_supervision.rs" anchor="spawn"/>}}

The default strategy is `Stop`: a failing actor stops for good. So the group spawns every device
with `spawn_with_config` and an `ActorConfig` whose strategy is `Restart`. When a device fails,
tellus runs `init` again for a fresh state. The device keeps its `ActorRef` and its mailbox, so
messages that are already queued are still handled after the restart. Only the state is lost: a
restarted device has no last reading.

Restarts back off exponentially, starting at 250 ms by default. The number of restarts is limited:

{{<example path="tellus/examples/tutorials/getting_started/06_supervision.rs" anchor="max-restarts"/>}}

A device which fails more than three times stops for good. The count starts over once a device has
run for 30 seconds without failing, the default of `RestartPolicy`. Since the group watches its
devices, it gets `Terminated` and prunes the device, just as for a retired one.

## Talking to the group

{{<example path="tellus/examples/tutorials/getting_started/06_supervision.rs" anchor="main"/>}}

`main` records readings for four devices, among them an invalid one for `left` and four invalid
ones for `broken`, retires `right` and asks for the average. The query waits until `broken` has
used up its restarts and stopped, which takes about two seconds. So `main` asks with a timeout of
five seconds here.

## Run it

From a clone of the tellus repository:

```sh
RUST_LOG=tellus=debug cargo run --quiet -p tellus --example getting_started_06_supervision
```

On stdout it prints:

```txt
Average temperature: 20.40
```

`left` failed and restarted, so it lost its 21.5 and has no reading. `broken` failed four times and
stopped. `right` retired. Only `middle` still has a reading.

On stderr tellus logs every failure and restart, as JSON because the example configures the
tracing subscriber that way.

## What you learned

An actor fails by returning an error or panicking. Its supervision strategy decides whether it
restarts or stops. A restart rebuilds the state but keeps the address and the mailbox. Together
with watch, the group copes with devices failing for good. Next, you put a manager on top of the
groups.
