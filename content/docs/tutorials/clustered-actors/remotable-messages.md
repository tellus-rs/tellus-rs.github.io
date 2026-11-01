+++
title       = "Messages that travel"
description = "Move the device manager to a node of its own and send it readings and questions across the wire."
weight      = 2
+++

In this step the device manager of the
[getting started tutorial](@/docs/tutorials/getting-started/device-manager.md) moves to a node of
its own. The first node sends it readings and asks it for averages, with the same `tell` and `ask`
as before. For that, its messages have to cross the wire.

## Messages for the wire

The device manager, its groups, devices and queries are the ones of the getting started tutorial,
with one change: names are `String` instead of `&'static str`. A message that arrives from another
node is deserialized from bytes, so it cannot borrow a string that lives in the sender's program.

Only the messages that cross the wire need more. That is just `Command`, the messages for the
device manager:

{{<example path="tellus/examples/tutorials/clustered/02_remotable_messages.rs" anchor="command"/>}}

The serde derives make `Command` encodable. `Average` carries a `ReplyTo`, which is serializable
too, so the reply finds its way back to the asking node. `Manifest` gives the message type a name
that every node agrees on. A reference looked up by name needs it, so the receiving node can tell
that the name means the same type there. The messages of the groups, devices and queries never
leave the device manager's node, so they need neither serde nor a manifest.

## The device manager node

The second node now runs the device manager:

{{<example path="tellus/examples/tutorials/clustered/02_remotable_messages.rs" anchor="manager-node"/>}}

After joining the cluster, it spawns the device manager as the root actor of its actor system and
registers it with the receptionist under a `Key`. A key is a name together with the message type,
here `Key<Command>`, so a lookup returns references of the right type. The registration is
replicated to every other member.

## Finding the device manager

The first node started the device manager's node, so it knows its address and looks the device
manager up there:

{{<example path="tellus/examples/tutorials/clustered/02_remotable_messages.rs" anchor="lookup-manager"/>}}

`lookup_at` answers from the registrations replicated to this node, without asking the other
node. Right after bootstrap it can still answer empty, because the registration may not have
arrived yet. So `lookup_manager` retries, bounded by one timeout.

## The first node

{{<example path="tellus/examples/tutorials/clustered/02_remotable_messages.rs" anchor="first-node"/>}}

`first_node` picks the addresses of both nodes, starts the device manager's node and joins the
cluster, then looks the device manager up. It needs no actor system of its own, since the device
manager is a remote reference now. The readings and the questions are those of the getting started
tutorial's `main`, with the same `tell` and `ask`.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example clustered_02_remotable_messages
```

It prints:

```txt
Average temperature in attic: 21.50
No readings in cellar
No readings in garage
```

The averages are those of the getting started tutorial. The boiler still fails on its invalid
reading, and the device manager's node logs that to stderr.

## What you learned

Messages that cross the wire derive serde, and those looked up under a key also implement
`Manifest`. `register` and `lookup_at` connect two nodes through a key, and `tell` and `ask` work
on a remote reference as on a local one. Next, the first node finds the device manager without
knowing where it runs.
