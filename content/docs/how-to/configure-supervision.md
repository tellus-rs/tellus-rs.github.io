+++
title       = "Configure an actor from a file"
description = "Load mailbox capacity and supervision from a config file instead of hard-coding them."
weight      = 3
+++

An `ActorConfig` sets an actor's mailbox capacity and supervision strategy. With the `serde`
feature it is deserializable, so the values can come from a config file. The example on this page
loads it with the [config](https://crates.io/crates/config) crate, but any format and loader
supported by serde works:

```sh
cargo add tellus --features serde
cargo add config --no-default-features --features toml
```

## Write the configuration

{{<code path="tellus/tellus/examples/how_to/device.toml" lang="toml" title="tellus/examples/how_to/device.toml"/>}}

The keys are the fields of `ActorConfig`:

- `mailbox_capacity` is `"unbounded"` (the default) or `{ bounded = n }` with `n` of at least 1.
- `supervision_strategy` is `"stop"` (the default) or a `restart` table.
- `max_restarts` is the only required key of `restart`, and it is at least 1. The others default to
  the values shown. The backoff grows from 250 ms to at most 4 s. The restart count resets once the
  actor has run for 30 s without failing. A `backoff` table needs both `min` and `max`.

Durations use the [humantime](https://docs.rs/humantime) format, for example `"250ms"`, `"4s"` or
`"1m"`.

## Load it

{{<example path="tellus/examples/how_to/configure_supervision.rs" anchor="load"/>}}

`try_deserialize` produces the `ActorConfig`, which you pass to `ActorSystem::with_config` for the
root, or to `context.spawn_with_config` for a child. Because `ActorConfig` is `Copy`, you can load
it once and use it for many actors.

## Rely on the validation

Invalid configuration fails while loading, not when an actor fails for the first time. An unknown
key is an error, so a typo does not silently fall back to a default. A backoff whose minimum is
zero or above its maximum is an error, too:

{{<example path="tellus/examples/how_to/configure_supervision.rs" anchor="invalid"/>}}

{{<example path="tellus/examples/how_to/configure_supervision.rs" anchor="error"/>}}

The error names the table with the offending key. In your application, return it from `main`
instead of printing it, so a misconfigured service does not start.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features serde --example how_to_configure_supervision
```

```txt
Loaded: ActorConfig { mailbox_capacity: Bounded(100), supervision_strategy: Restart(RestartPolicy { max_restarts: 3, backoff: Backoff { min: 250ms, max: 4s }, reset_after: 30s }) }
Rejected: max backoff 1s below min backoff 10s for key `supervision_strategy.backoff`
```

The explanation [Supervision and lifecycle](@/docs/explanation/supervision-and-lifecycle.md)
describes what these values do at runtime.
