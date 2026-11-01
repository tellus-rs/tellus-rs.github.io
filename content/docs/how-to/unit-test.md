+++
title       = "Unit test an actor"
description = "Test receive, handle and apply as plain functions with TestContext, without an actor system."
weight      = 2
+++

`receive` is a plain function, so you can call it in a test like any other function: pass a
message and a state, and check what it returns. The only arguments you cannot build by hand are
the `ActorContext` and any `ReplyTo` in a message. The `test-util` feature provides both through
`TestContext`:

```sh
cargo add tellus --dev --features test-util
```

The examples on this page test the device and the group of the
[getting started tutorial](@/docs/tutorials/getting-started/_index.md).

## Check the next state

{{<example path="tellus/tests/how_to_unit_test.rs" anchor="record"/>}}

`test_context.context()` is the `ActorContext` for the call. No actor system runs, and nothing needs
to be awaited. `receive` returns a `Result` with the `Control` and the next state. `assert_matches!`
checks all of it in one assertion and prints the actual value when the check fails. It needs Rust
1.96 or later and is imported with `use std::assert_matches;`. Its bindings do not leave the macro,
though. When a test goes on with the state, `let ... else` takes the result apart instead, as in
[Test children and death watch](#test-children-and-death-watch).

## Check what an actor sends

{{<example path="tellus/tests/how_to_unit_test.rs" anchor="reply"/>}}

A reply goes to whoever asked. In a test, a second `TestContext` stands in for the asker: its
context's `reply_to` creates the `ReplyTo` for the message. After the call, `take_incoming` returns
everything that arrived at the asker, in order. Messages an actor sends to itself through
`context.self_ref()` arrive at its own `TestContext` the same way.

## Test children and death watch

{{<example path="tellus/tests/how_to_unit_test.rs" anchor="children"/>}}

`context.spawn` starts a real child actor, so this test needs a Tokio runtime, here via
`#[tokio::test]`. The test then simulates the child's termination by passing
`Incoming::Terminated` with its ID. To test the watching itself, simulate the watched actor with a
second `TestContext`, watch its `self_ref()` and call `terminate` on it. Like a real termination,
`terminate` sends the terminated signal to the watchers.

## Test an event-sourced actor

For an event-sourced actor, `handle` decides and `apply` changes the state. Both are plain
functions too. The examples come from the device of the
[event-sourced actors tutorial](@/docs/tutorials/event-sourced-actors/_index.md) and need the
`persistence` feature as well.

{{<example path="tellus/tests/how_to_unit_test_event_sourced.rs" anchor="decide"/>}}

`Effect` tells which events a command causes, via `events`, and whether it stops the actor, via
`stop_requested`. `settle`, imported from `tellus::testing` like `TestContext`, does what tellus
does once the events are stored: it applies them to the state in order and runs the continuations.

{{<example path="tellus/tests/how_to_unit_test_event_sourced.rs" anchor="reject"/>}}

A rejected command returns the actor's error instead of an `Effect`, so nothing is persisted.
`assert_matches!` names the expected error, so the test fails on success as well as on any other
error.

{{<example path="tellus/tests/how_to_unit_test_event_sourced.rs" anchor="reply"/>}}

A continuation attached with `then` runs only during `settle`, so the asker has the reply only
after `settle`.

{{<example path="tellus/tests/how_to_unit_test_event_sourced.rs" anchor="replay"/>}}

Recovery replays the stored events through `apply`, starting from `init`. A fold over a list of
events tests exactly that, without a store.

## What these tests do not cover

A direct call differs from a running actor in a few ways:

- Nothing supervises the call. An error or a panic reaches the test, and nothing restarts the
  actor.
- The run loop drops a terminated signal of an actor which is no longer watched. A direct call to
  `receive` sees every signal it is given.
- Dropping the `TestContext` asks the children to stop, but does not wait for them.

Mailbox delivery, supervision and the ordering guarantees belong to tellus and have tests of their
own. A test which spawns a system, sends a message with `tell` and then checks some result mostly
tests those again. It also has to wait for the actor somehow, because `tell` returns before the
message is handled.

## Run it

From a clone of the tellus repository:

```sh
cargo test --quiet -p tellus --features test-util,persistence --test how_to_unit_test --test how_to_unit_test_event_sourced
```

```txt
running 3 tests
...
test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s

running 4 tests
....
test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```
