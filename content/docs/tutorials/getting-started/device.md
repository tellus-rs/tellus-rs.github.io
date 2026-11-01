+++
title       = "A device actor"
description = "Keep state in an actor, tell it readings and ask it for the last one."
weight      = 2
+++

A device records temperature readings and answers when asked for the last one. In this step you
write it as an actor with state, and you talk to it in the two basic ways: `tell` and `ask`.

## The messages

A device understands two messages:

{{<example path="tellus/examples/tutorials/getting_started/02_device.rs" anchor="message"/>}}

`Record` carries a reading. `Read` asks for the last reading and carries a `ReplyTo`, the
destination for the answer. A `ReplyTo` can be used at most once: calling `reply` consumes it.

## The actor

{{<example path="tellus/examples/tutorials/getting_started/02_device.rs" anchor="device"/>}}

The state is `Option<f64>`: no reading at first, later the last one. `receive` gets the current
state by value and returns the state for the next message. For `Record` that is the new reading.
For `Read` the device replies and keeps its state unchanged.

There is no `&mut self` and no field to update. The state lives in the return value, so you can
read every transition in one place, the `match`.

The `let ... else` at the top deals with `Incoming`. Besides messages an actor can receive signals
about other actors terminating. The device watches no actor, so it never gets one; you will meet
signals in [Watching devices](@/docs/tutorials/getting-started/watch.md).

## Talking to the device

{{<example path="tellus/examples/tutorials/getting_started/02_device.rs" anchor="main"/>}}

`tell` sends a message and returns at once. It neither waits for the message to be handled nor
reports whether it arrived. That makes it fast, and it is how actors talk to each other.

`ask` is for code outside of actors, like `main` here. It builds the request around a `ReplyTo`,
sends it and waits for the reply, at most for the given duration. Passing `DeviceMessage::Read`
works because the variant is a function from `ReplyTo` to a message.

Messages from one sender arrive in the order they were sent. So the `Read` is handled after both
readings, and the answer is always the second one. At the end, `system.stop()` stops the root
actor and `terminated` waits for it.

## Run it

From this step on, every step is an example in the tellus repository, and the pages show its
relevant parts. Clone the repository once, at the release these pages show, and run the examples
from there:

```sh
git clone --branch {{<tellus_tag/>}} https://github.com/tellus-rs/tellus
cd tellus
cargo run --quiet -p tellus --example getting_started_02_device
```

It prints:

```txt
Last reading: 22.0
```

## What you learned

An actor's state is a value that `receive` takes and returns. `tell` sends without waiting, `ask`
waits for a reply, and messages from one sender arrive in order. Next, you let one actor spawn
others.
