+++
title       = "Publish to a topic"
description = "Subscribe actors on several nodes to a topic and tell all of them with one publish."
weight      = 65
+++

A topic tells one message to every actor subscribed to it, on any member of the cluster.
`pubsub::subscribe` subscribes an actor of this node, and `pubsub::publish` tells every subscriber
the receptionist knows of. There is no mediator: a topic is a key at the receptionist under another
name.

The examples on this page come from two nodes. Each subscribes a listener to the topic `notices`
before it bootstraps. The first node then publishes one notice and collects a receipt from every
listener. The program plays both nodes, as in the
[clustered actors tutorial](@/docs/tutorials/clustered-actors/two-nodes.md).

## Define the message

{{<example path="tellus/examples/how_to/publish_to_a_topic.rs" anchor="listener"/>}}

A published message crosses the wire like any remote message: `Notice` derives serde's `Serialize`
and `Deserialize` and implements `Schema` and `Manifest`, see
[Messages that travel](@/docs/tutorials/clustered-actors/remotable-messages.md). `publish` tells
each subscriber of this node a clone of the message, so it also needs `Clone`. That rules out a
`ReplyTo` in a published message, so `Notice` carries an `ActorRef<Receipt>` for the answers. The
listener tells it a receipt and stops.

## Subscribe

{{<example path="tellus/examples/how_to/publish_to_a_topic.rs" anchor="subscriber-node"/>}}

`subscribe` registers an actor of this node under the topic, so it needs a started endpoint. Both
nodes subscribe before they bootstrap. There is no unsubscribe: a subscription lasts as long as its
actor. An actor which should leave a topic while it keeps running subscribes a child, which it can
stop. The second node waits until its listener has stopped, then leaves the cluster.

## Wait for the subscriptions

A publish tells only the subscribers whose registration has reached this node. Right after
bootstrap, the registrations of the other node may still be on their way:

{{<example path="tellus/examples/how_to/publish_to_a_topic.rs" anchor="await-settled"/>}}

`receptionist::settled(version)` is true when `version` is the current cluster state version and
every other up member in that view has delivered its first set of registrations. The receptionist
can settle between cluster state changes, so `await_settled` also checks every 100 ms. Both
listeners subscribed before bootstrap and are in that first delivery. Later subscriptions can
still be in transit.

## Publish

{{<example path="tellus/examples/how_to/publish_to_a_topic.rs" anchor="first-node"/>}}

`receptionist::lookup(topic.key())` lists the subscribers of the topic. A discovery key of the same
name is a different key, so `Key::new("notices")` would not list them. `publish` tells the
subscribers of this node first, each a clone. It encodes the message once per other node with
subscribers, rather than once per subscriber. It answers how many subscribers it told. That is not
the number of deliveries: as with `tell`, the message is a dead letter for every subscriber on a
node which cannot be reached.

## What to keep in mind

**The guarantee is that of `tell`, per subscriber.** Every subscriber gets a publish at most once.
Publishes from one node reach a subscriber in the order they were made, in order with the node's
direct tells to it. Concurrent publishes can reach two subscribers in different orders.

**A publish fails once this node is out.** On a node whose own entry is left or down, `publish`
tells nobody and fails, rather than answer 0 as if the topic had no subscribers. It also fails if
the topic has subscribers only for another message type.

## Run it

{{<example path="tellus/examples/how_to/publish_to_a_topic.rs" anchor="main"/>}}

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_publish_to_a_topic
```

```txt
Subscribers: 2
Told: 2
Node 1 received: maintenance at noon
Node 2 received: maintenance at noon
```

The lookup on the first node lists both listeners once the receptionist has settled, and the
publish tells both. The receipts arrive in any order; the first node sorts them by node before it
prints them.
