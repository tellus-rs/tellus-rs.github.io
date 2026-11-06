+++
title       = "Defer messages while an actor waits"
description = "Stash the requests which arrive while an actor waits for a piped future, and answer them in order once it has what it needs."
weight      = 2
+++

`receive` is a plain function, so an actor [pipes async code to itself](@/docs/how-to/call-async-code.md)
and keeps handling messages while the future runs. A request which needs the future's output
cannot be answered before it arrives, and a stash defers it until then. The actor keeps `receive`
synchronous and decides for each message whether it waits; an `await` would defer everything.

The examples on this page come from the directory actor of the previous page. It now loads its
whole customer table once, at startup, and answers lookups from it.

## Declare a stash

Stashing is opt-in per actor type. Every actor declares `type Stash`. With `Unstashed`, the context
has no `stash` and no `unstash_all`, and the actor runs a loop without stash code. `Stashed` adds
the two methods:

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="types"/>}}

The mode is the context's third type parameter, which defaults to `Unstashed`. `init` and `receive`
take `&ActorContext<Self::Message, Self::Timers, Self::Stash>`. This actor, being untimed, writes
`&ActorContext<Self::Message, Untimed, Stashed>`, as `init` below shows.

## Pipe the future and wait

`init` starts the load and returns the state `Loading`. The table arrives later as the `Loaded`
message:

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="init"/>}}

The load itself is an ordinary async function, here a simulated database read which takes 300 ms:

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="load-customers"/>}}

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="state"/>}}

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="message"/>}}

## Stash while waiting

While the table loads, the actor stashes every incoming but `Loaded`, since it cannot answer a
lookup yet. `stash` takes the `Incoming` as `receive` got it, which keeps a terminated signal in its
place behind the messages of the stopped actor:

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="loading"/>}}

The stash has the capacity of the mailbox, three in this example (see `main` below). A full stash
neither drops the message nor panics: `stash` hands it back as its error, and the actor decides.
Here it answers `Busy`, so the caller can try again. Akka's `StashBuffer`, the model for this API,
throws when it is full.

## Unstash when the output arrives

When `Loaded` arrives, the actor calls `unstash_all` and becomes `Ready`. `unstash_all` hands every
stashed item back to the run loop, which receives them one `receive` each, in the order they were
stashed. The `Ready` state answers them from the table like any later lookup:

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="ready"/>}}

## What to keep in mind

**`stash` and `unstash_all` are requests.** They take effect once the item at hand is settled: when
`receive` or `init` has returned successfully, and for an event-sourced actor when `recovered` has
returned or once the command's events are durable. They apply in the order they were made:
`stash(x)` followed by `unstash_all` hands `x` back, `unstash_all` followed by `stash(x)` keeps `x`
stashed. A failure discards them.

**Unstashed items come first.** The run loop receives them ahead of a due timer and of the mailbox;
only a stop by the parent comes before them. The run below cannot show the order against the
mailbox, since the actor is idle while it waits;
[`tests/stash.rs`](https://github.com/tellus-rs/tellus/blob/main/tellus/tests/stash.rs) proves it.
A drain cannot starve the mailbox, as
[Message delivery](@/docs/explanation/message-delivery.md#stashing) explains.

**The stash has the mailbox's capacity.** The outputs of piped futures and the replies to `reply_to`
destinations pass a full mailbox but not a full stash.
[Message delivery](@/docs/explanation/message-delivery.md#stashing) has the accounting.

**A restart hands the stash back.** The new state receives every stashed item first, in order,
after `init`, or after recovery and `recovered` for an event-sourced actor. Termination drops the
stash with the mailbox, so a `ReplyTo` stashed inside a request resolves its `ask` as `NoReply`.

**Terminated signals can be stashed.** A stashed signal keeps its place and skips the stash's
capacity. `unwatch` drops the stashed signals of the unwatched actor as it drops the queued ones,
with [one exception](@/docs/explanation/death-watch-ordering.md#unwatching).

**Testing.** `TestContext::stashed` creates the context of a stashed actor, `take_stashed` returns
what the actor has stashed, and `take_unstashed` what `unstash_all` handed back, in the order it
would be received. See [Unit test an actor](@/docs/how-to/unit-test.md).

## Run it

{{<example path="tellus/examples/how_to/defer_messages.rs" anchor="main"/>}}

The mailbox is bounded to three, so the stash is too. `tokio::join!` sends the first three lookups
at once, and they fill the mailbox. The mailbox frees capacity when the directory receives them.
The fourth lookup goes out 50 ms later, after they have left the mailbox and while the table still
loads. It gets into the mailbox, and the directory finds the stash full. From a clone of the tellus
repository:

```sh
cargo run --quiet -p tellus --example how_to_defer_messages
```

```txt
Loaded 3 customers
Customer 1: Alice
Customer 2: Bob
Customer 3: Carol
Customer 4: busy, try again later
Customer 9: unknown customer 9
```

Lookup 4 was answered at once, while the first three waited for the table. The directory answered
those three in the order they were stashed; `main` prints every answer in id order, so the output
shows the answers, not that order. Lookup 9 came after the table and was answered right away.
