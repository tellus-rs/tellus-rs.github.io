+++
title       = "Hello, tellus"
description = "Create an actor system with a single actor that handles one message and stops."
weight      = 1
aliases     = [ "/guide/tutorial/hello/" ]
+++

In this tutorial you build a small temperature monitor: devices record readings, a group manages
its devices, and you can ask the group for the average temperature. Each step is a complete
program that compiles and runs. Besides tellus and Tokio, the programs use anyhow for errors, and
the last three steps also use thiserror and tracing-subscriber.

## Set up a project

Create a new binary crate and add tellus together with Tokio and anyhow:

```sh
cargo new hello-tellus
cd hello-tellus
cargo add anyhow
cargo add tokio --features macros,rt-multi-thread
cargo add tellus
```

## Your first actor

Replace `src/main.rs` with this program:

{{<example path="tellus/examples/tutorials/getting_started/01_hello.rs"/>}}

## Run it

```sh
cargo run --quiet
```

```txt
Hello, Tellus!
```

## What happens here

An actor is a value whose type implements the `Actor` trait. The trait has five associated types:

- `Message` is the type of the messages the actor receives, here `Greet`.
- `Timers` says whether the actor can start timers. The greeter needs none, so it is `Untimed`.
  [A later step](@/docs/tutorials/getting-started/stale-readings.md) uses them.
- `Stash` says whether the actor can defer messages. The greeter defers none, so it is `Unstashed`.
  [A how-to](@/docs/how-to/defer-messages.md) shows a stash.
- `State` is the actor's state. The greeter needs none, so it is `()`.
- `Error` is the type of the actor's failures. The greeter cannot fail, so it is `Infallible`.

`init` creates the initial state. `receive` is called for every incoming message. It gets the
current state and returns what happens next: `Control::Continue` with the state for the next
message, or `Control::Stop` to stop the actor. The greeter stops after its first message.

`ActorSystem::new` spawns the greeter as the root actor of a new actor system. `tell` sends it a
message without waiting for anything. `terminated` resolves once the root actor has stopped, and
then the program ends.

Notice that `receive` is a plain function, not an `async fn`. An actor reacts to one message at a
time, from start to finish.

## What you learned

An actor is a type that implements `Actor`: its associated types, an `init` that creates the
state and a `receive` that handles one message at a time. `ActorSystem::new` spawns it, and `tell`
sends it a message. Next, you give an actor state that changes with every message.
