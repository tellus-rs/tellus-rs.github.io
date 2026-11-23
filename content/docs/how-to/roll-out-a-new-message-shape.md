+++
title       = "Roll out a new message shape"
description = "Change the shape of a message in a rolling upgrade: the new release encodes the old shape for old nodes and upcasts it when it arrives."
weight      = 130
+++

In a rolling upgrade, nodes of the old and of the new release run side by side in one cluster. Old
code cannot be taught a new shape of a message, so the new release bridges both directions. It
encodes the old shape for nodes of the old release, and it upcasts the old shape it receives: it
decodes it and converts it into the new one. For that, every payload carries the schema version of
its shape, and every handshake carries the application version of its node, if one is configured.

The examples on this page come from two nodes. The first one runs version 2.0.0 of the application,
whose greeting carries a language. The legacy node runs version 1.0.0, whose greeting does not. Each
node asks the greeter of the other one. The program plays both nodes and needs the `cluster-dev`
feature, as in the [clustered actors tutorial](@/docs/tutorials/clustered-actors/two-nodes.md).
[Messages that travel](@/docs/tutorials/clustered-actors/remotable-messages.md) introduces `Schema`
and `Manifest`, which this page builds on.

## Version the message

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="greeting"/>}}

`Greeting` is the message in the shape of version 2.0.0. Version 1.0.0 sends it without the
language, as schema version 0, the default. So `Greeting` sets `VERSION` to 1, and its manifest
stays `greeting`.

tellus calls `encode` when a greeting is told to an actor on another node, before it is queued, with
the `Peer` it is for. `Peer::app_version` is the application version that node announced at its
handshake. For a peer whose major version is below 2, `encode` writes the old shape as schema
version 0, and the language is dropped. `GreetingV0View` borrows the fields the old shape has. They
keep the order of the old shape, since the codec, postcard, encodes fields by position. Any other
peer gets the current shape. The old shape may have no place for a value, a new enum variant for
instance. Then the `encode` override returns an error made with `CodecError::make_encoding`. A tell
then becomes a dead letter on the sending node, and an ask fails as `AskError::NotEncodable`.

`app_version` is `None` before the first handshake with the peer has completed, and for a peer which
announced no version. `is_none_or` treats `None` like a peer of version 1.0.0. An override treats
`None` as the oldest version it still encodes, since a message in a newer shape is a dead letter at
an older peer. Before the first handshake has completed, a greeting hence crosses in the old shape,
even between two nodes of version 2.0.0. A greeting in German then arrives with the language `en`,
which the upcast fills in.

`decode` gets the schema version a payload carries. It decodes version 0 as a `LegacyGreeting` and
upcasts it to a `Greeting` with the language `en`. Version 1 decodes as it is, and every other
version fails with `UnsupportedSchemaVersion`. The example holds both releases in one program, so
`decode` uses the legacy node's own type. In an application, version 2.0.0 keeps a struct of the old
shape, deriving `Deserialize`, only to decode it.

## Greet in both releases

The greeter of version 2.0.0 gets every greeting in the new shape, whichever shape crossed the wire:

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="greeter"/>}}

It answers with the name and the language and keeps running. The answer, a `String`, has one shape
forever. A reply type of the application evolves like `Greeting`, since its `encode` gets the node
which asked as its peer. The legacy node's greeter is the code of version 1.0.0, unchanged:

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="legacy-greeter"/>}}

The empty `Schema` impl of `LegacyGreeting` keeps the defaults: it encodes its one shape as schema
version 0 and decodes version 0 only. Its manifest is `greeting` too. A key names its message type
by the manifest, so both greeters are registered under the same key. The legacy greeter answers once
and stops.

## Announce the application version

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="start-endpoint"/>}}

`EndpointConfig::app_version` is the version of the application a node runs. The endpoint announces
it at every handshake, and on the other side `encode` gets it as `Peer::app_version`. `AppVersion`
is semver's `Version`. With the `serde` feature, a config file gives it as a string, such as
`app_version: "2.0.0"`. The default, `None`, announces nothing.

## Ask across releases

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="first-node"/>}}

The first node starts the legacy node as a second process of this program, with `legacy-node`, its
address and the seeds as arguments. It runs version 2.0.0 and registers its greeter under the key
`greeter`. Once `bootstrap` has made it a member, `find_greeter` polls `receptionist::lookup_at` at
the legacy node's address every 100 ms, until the registration has arrived. The first node asks that
greeter with a greeting in German. The legacy node announced 1.0.0, so the greeting crosses in the
old shape. The first node prints the answer once the legacy node has exited, and stops its greeter.

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="legacy-node"/>}}

The legacy node runs version 1.0.0, registers its greeter and asks the greeter at the first seed,
the first node's address. It prints the answer at once. `cluster::leave_on_terminated` then waits
until the legacy greeter has stopped after its one greeting, and leaves the cluster. The example
treats a missing acknowledgment of the departure as an error.

## What to keep in mind

**One rollout is enough.** The new release bumps `VERSION`, decodes the old version and encodes the
old shape for nodes of the old release, so it can be rolled out node by node. A rollback brings old
nodes back, and the same `encode` serves them. A later release serves them too, as long as it keeps
encoding the old shape. Without an `encode` override, it takes two rollouts: first a release which
decodes both shapes but sends the old one, then one which sends the new one. The [cluster
demo](https://github.com/tellus-rs/tellus/tree/main/tellus-cluster-demo) rolls its five nodes
between versions 1.0.0 and 2.0.0 with an `encode` override like this one, one node at a time.

**A node drops a payload of a version it does not decode.** On the legacy node, that is every
version but 0. Such a payload is a dead letter on the receiving node, so nothing is decoded in the
wrong shape. The dead-letter warning names the type and both versions, and an ask fails as
`AskError::NoReply`. The connection stays open, and the sender's later messages are delivered as
usual.

**Every change to a shape bumps `VERSION`.** Since postcard encodes by position, the schema version
is the only reliable check on a changed shape. Two fields of one type swapped, or a field whose type
changed, can decode silently wrong. A change inside a field of an application type bumps the
message's `VERSION`.

**`decode` decodes a payload once.** Decoding a `ReplyTo` claims the reply's destination, so a
`decode` which tries one shape and then another can leave the asker without a reply. Match on the
schema version and decode once.

**The manifest never changes.** A type renamed in the new release has to keep its manifest.
Otherwise a lookup omits the actors which the other release registered. Where only those hold the
name, the lookup fails with `ReceptionistError::TypeMismatch`.

For the contract behind all of this, see [Rolling
upgrades](https://github.com/tellus-rs/tellus/blob/main/docs/cluster.md#rolling-upgrades) in the
internals documentation. [Evolve events](@/docs/how-to/evolve-events.md) upcasts stored events the
same way.

## Run it

{{<example path="tellus/examples/how_to/roll_out_a_new_message_shape.rs" anchor="main"/>}}

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_roll_out_a_new_message_shape
```

```txt
The current node answered: Hello, Bob (en)
The legacy node answered: Hello, Ann
```

The first line is the legacy node's. Its greeting reached the first node, the current one, in the
old shape, and the upcast added the language `en`. The second line is the first node's. Its German
greeting reached the legacy node in the old shape, without the language. The legacy node prints as
soon as it has its answer. The first node prints only after the legacy node has exited, so the
legacy node's line always comes first. tellus logs to stderr; `RUST_LOG=tellus=debug` shows what
both nodes do meanwhile.
