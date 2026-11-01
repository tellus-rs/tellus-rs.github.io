+++
title       = "Call async code from an actor"
description = "Run a database query or an HTTP request for an actor and get the result back as a message."
weight      = 1
+++

`receive` is a plain function, so an actor cannot await. To use async code, for example a database
query or an HTTP request, pipe the future to the actor itself with `context.pipe_to_self`. The
future runs on its own Tokio task, and its output arrives as an ordinary message. The actor keeps
handling other messages meanwhile.

The examples on this page come from a directory actor which looks up customers in a simulated
database.

## Pipe a future to the actor

The message type has a variant for the request, `Lookup`, and one which carries the result back,
`Found`. `Checksum` and `Computed` follow further below:

{{<example path="tellus/examples/how_to/call_async_code.rs" anchor="message"/>}}

The lookup itself is an ordinary async function:

{{<example path="tellus/examples/how_to/call_async_code.rs" anchor="find-customer"/>}}

In `receive`, the actor pipes the future returned by `find_customer` to itself:

{{<example path="tellus/examples/how_to/call_async_code.rs" anchor="lookup"/>}}

`pipe_to_self` takes the future and a function which turns its output into a message. Here the
function is a closure which also moves the request's `ReplyTo` into the `Found` message. When
`Found` arrives, the actor replies. Between `Lookup` and `Found`, the actor is free for other
messages.

## Handle errors

If the async code can fail, the failure is part of the future's output: `find_customer` returns a
`Result`, and the `Found` message carries it as it is. The actor decides what to do with an error
in `receive`, as with any other message. Here it passes the error on to whoever asked.

## Run blocking work

Blocking or CPU-heavy work goes into `tokio::task::spawn_blocking`. Its `JoinHandle` is itself a
future, so you pipe it the same way:

{{<example path="tellus/examples/how_to/call_async_code.rs" anchor="checksum"/>}}

The output is a `Result<u64, JoinError>`. It is an error if, for example, the blocking closure
panicked.

## What to keep in mind

**Other messages can come first.** The actor handles other messages while the future runs, and the
result arrives whenever the future is ready. Write `receive` so that it does not depend on the
result arriving before anything else.

**Stopping does not cancel the future.** If the actor has terminated by the time the future is
ready, the result is dropped and logged as a dead letter.

**A restart does not cancel the future either.** A restarted actor keeps its mailbox, so the result
of a future piped before the restart is received by the new state. If an actor must tell such
results apart, it gives each request an identifier and keeps the open ones in its state.

**A panic delivers nothing.** If the future or the conversion panics, tellus logs the panic at
error level, and no message arrives. A `ReplyTo` captured by the conversion is dropped with it, so
an `ask` waiting for it fails with `AskError::NoReply` instead of waiting for its timeout.

## Run it

{{<example path="tellus/examples/how_to/call_async_code.rs" anchor="main"/>}}

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --example how_to_call_async_code
```

```txt
Customer 1: Alice
Customer 2: Bob
Customer 3: unknown customer 3
Checksum: 9c3434cbfbedb0d2
```
