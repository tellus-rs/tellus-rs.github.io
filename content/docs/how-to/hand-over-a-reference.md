+++
title       = "Hand over a reference"
description = "Pass an actor reference to another node out of band, as bytes on its command line, and use it once that node has joined."
weight      = 64
+++

Within a cluster, references travel inside messages: an `ActorRef` or a `ReplyTo` in a message
crosses the wire with it. The first reference a node gets has to come from somewhere else. Usually
the receptionist finds it by key, as in
[Finding the device manager](@/docs/tutorials/clustered-actors/receptionist.md). Instead,
`cluster::serialize_ref` and `cluster::deserialize_ref` turn a reference into bytes and back, so it
can be handed over out of band: in a configuration file, an environment variable or on a command
line.

The examples on this page come from two nodes. The first one serializes the reference of its
greeter and passes it to the second one on the command line, in hex. The program plays both nodes,
as in the [clustered actors tutorial](@/docs/tutorials/clustered-actors/two-nodes.md).

## Serialize the reference

{{<example path="tellus/examples/how_to/hand_over_a_reference.rs" anchor="first-node"/>}}

`serialize_ref` needs a started endpoint and encodes the reference with the endpoint's codec. The
bytes carry the manifest of the message type next to the reference. A command line takes text, so
the example writes the bytes in hex; any encoding of bytes works. The first node then starts the
second node with the reference as an argument and bootstraps the cluster. It keeps the greeter
running until the second node has exited.

## Deserialize it on the other node

{{<example path="tellus/examples/how_to/hand_over_a_reference.rs" anchor="second-node"/>}}

`deserialize_ref::<Greet>` resolves the bytes into an `ActorRef<Greet>`. It refuses bytes
serialized for another message type, rather than resolving them into a reference which drops every
message told to it. `Greet` crosses the wire, so it derives serde's `Serialize` and `Deserialize`
and implements `Schema`, and it implements `Manifest` for the type check, see
[Messages that travel](@/docs/tutorials/clustered-actors/remotable-messages.md).

The second node asks the greeter only once `bootstrap` has made it a member: the handshake between
two nodes refuses a peer which is not a member. From then on the reference works like any other,
and the reply finds its way back through the `ReplyTo` inside `Greet`. Finally the second node
leaves the cluster and exits.

## What to keep in mind

**Every node has to agree on the manifest.** tellus compares the manifest in the bytes with that of
the requested type. It cannot check that the manifest names the same type on every node, so a
manifest is unique per type across the cluster.

**The bytes name one actor.** Once that actor has terminated, the reference names nothing anymore,
and messages told to it are dead letters. A
[subscription](@/docs/tutorials/clustered-actors/receptionist.md) at the receptionist follows
whichever actors are registered under a key instead.

**Only the first reference needs this.** Every further reference can travel inside a message told
to one already resolved.

## Run it

{{<example path="tellus/examples/how_to/hand_over_a_reference.rs" anchor="main"/>}}

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_hand_over_a_reference
```

```txt
The greeter answered: Hello, Bob
```

The second node prints the answer of the greeter, which runs on the first node. tellus logs to
stderr; `RUST_LOG=tellus=debug` shows what both nodes do meanwhile.
