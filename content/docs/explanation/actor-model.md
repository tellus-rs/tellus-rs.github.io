+++
title       = "The actor model in Rust"
description = "What actors are, why they suit Rust's ownership rules, and when tasks, channels or locks are the better choice."
weight      = 0
+++

The actor model is a model of concurrent computation, introduced by Carl Hewitt and colleagues in
1973. tellus implements it for Rust, on top of Tokio. This page explains the model itself, shows
where its parts appear in tellus, and discusses when actors are the right tool. The other
explanation pages build on it.

## Actors, messages and addresses

An actor is the unit of computation in the model. It has state, which no one else can access, and
an address, through which others send it messages. Messages queue up in the actor's mailbox, and
the actor handles them one at a time. As Hewitt is often quoted, "one actor is no actor, they
come in systems": actors get work done only by sending each other messages.

In reaction to a message, an actor may do three things:

- send a finite number of messages to actors whose addresses it knows,
- create a finite number of new actors,
- designate the behavior for the next message.

Nothing else is part of the model. There is no shared memory, and no call which waits for another
actor to return.

In tellus, the messages of an actor are a plain Rust type, usually an enum. Here are the messages
of the device from the [getting started tutorial](@/docs/tutorials/getting-started/_index.md):

{{<example path="tellus/examples/tutorials/getting_started/02_device.rs" anchor="message"/>}}

The address of the device is an `ActorRef<DeviceMessage>`. It is typed, so the compiler rejects
any message the device cannot handle. It is also cheap to clone, so any number of actors can know
the device. Code outside of actors, like `main`, uses the same address:

{{<example path="tellus/examples/tutorials/getting_started/02_device.rs" anchor="main"/>}}

`tell` puts a message into the mailbox and returns at once. `ask` sends a request which carries a
`ReplyTo` and awaits the reply. The model itself promises nothing about the order in which
messages arrive. tellus adds a guarantee: messages from one sender arrive in the order they were
sent, as [Message delivery](@/docs/explanation/message-delivery.md) explains.

## The three reactions in tellus

A group of devices reacts to a reading for a device it has not seen before with all three
reactions at once:

{{<example path="tellus/examples/tutorials/getting_started/03_group.rs" anchor="record"/>}}

`context.spawn` creates an actor, `tell` sends it a message, and `Control::Continue(devices)`
designates the state, and with it the behavior, for the next message. How the state selects the
behavior is the topic of [Actors as state machines](@/docs/explanation/state-machines.md). Why
`receive` handles a message from start to finish, without awaiting anything, is explained in
[Synchronous message handlers](@/docs/explanation/synchronous-handlers.md).

## Why actors suit Rust

Rust does not allow shared mutable state without synchronization. The usual answer is
`Arc<Mutex<T>>`, and with it come the usual problems: contention, a guard held across an `await`,
and deadlocks when two tasks take two locks in different orders.

An actor needs no lock, because it owns its state exclusively. Only the actor's own `receive` ever
sees the state, one message at a time. tellus makes this ownership literal: `receive` takes the
state by value and returns the next one, so the state always has exactly one owner.

Messages move into the mailbox. Spawning an actor requires the actor value, its messages and its
state to be `Send + 'static`. So the compiler checks that whatever crosses from one actor to
another is safe to send.

Each actor runs as a single Tokio task, so an actor costs a task, not a thread.

Actors also give failures a place, as Erlang showed with supervision trees. In tellus, an actor's
supervision strategy decides whether a failed actor restarts with a fresh state or stops. Actors
form a tree, and stopping always goes from the children to the parent. An actor which watches
another learns when it terminates. It then knows that it has seen every message from it that it
will ever see. See
[Supervision and lifecycle](@/docs/explanation/supervision-and-lifecycle.md) and
[The death watch ordering guarantee](@/docs/explanation/death-watch-ordering.md).

## When to use actors, and when not

Actors are a good fit for long-lived state that many parts of a program use concurrently: a
device, a session, a connection, an account. They also fit when parts of a program need a
lifecycle of their own, starting, failing, restarting and stopping as a unit, together with their
children. And they fit when one part needs to know that another one is gone, and that nothing more
can come from it.

Other tools are often simpler:

- A pipeline of transformations, where no stage has state worth an address, is a chain of
  channels or a stream.
- Data which is read often and written rarely, like configuration, is an `Arc`, maybe with a lock
  for the rare writes.
- Independent work which ends with a result is a set of tasks, for example in a `JoinSet`.
- A request handler which only reads and writes a database is a plain async function, because the
  database already coordinates concurrent access.

Mixing is normal. An HTTP handler can ask an actor for its state. And an actor can pipe a
database query to itself with `pipe_to_self` and receive the result as a message, as
[Call async code from an actor](@/docs/how-to/call-async-code.md) shows.

## Further reading

The [getting started tutorial](@/docs/tutorials/getting-started/_index.md) builds an actor system
step by step, from a single actor to a tree of groups and devices with supervision. For how Akka,
one of the inspirations of tellus, implements the model, read
[The Actor Model in Akka and Akka Typed](https://heikoseeberger.de/2017-10-02-actor-model/) on
Heiko Seeberger's blog.
