+++
title       = "When a node dies"
description = "Watch a device manager on another node, kill its node and turn to a second device manager."
weight      = 4
+++

Nodes crash. In this step two nodes run a device manager each, the first node watches the one it
uses, and that one's node is killed. The cluster has to notice that the node is gone and agree to
down it, and the watch tells the first node when it has.

## Why three nodes

When a node falls silent, the others cannot tell whether it crashed or whether only the network
between them failed. So the cluster does not decide by who is silent, but by who is in the
majority. The `KeepMajority` downing provider, the default, keeps the side that sees a strict
majority of the members and downs the others. In a cluster of two, every failure is an even split.
`KeepMajority` gives it to the lower address, so the lower node survives a failure of the higher
one, but when the lower one is killed, the survivor downs itself. Two nodes cannot guarantee
surviving either node's failure, so this step runs three: the first node and two device manager
nodes. Whichever of them is killed, the other two are a majority. For the downing rules in full,
see [Membership and downing](@/docs/explanation/membership-and-downing.md).

A majority only means something if all nodes count the same members. So before anything is
killed, all three have to agree on the membership.

## Agreeing on the members

{{<example path="tellus/examples/tutorials/clustered/04_remote_watch.rs" anchor="await-all-up"/>}}

`await_all_up` waits until this node lists all three members as up. A device manager node
registers its device manager only after that:

{{<example path="tellus/examples/tutorials/clustered/04_remote_watch.rs" anchor="manager-node"/>}}

So once the first node sees both registrations and all three members up itself, all three nodes
agree. `find_managers` waits for a given number of registrations, like `find_manager` of the
previous step:

{{<example path="tellus/examples/tutorials/clustered/04_remote_watch.rs" anchor="find-managers"/>}}

## Detecting a failure faster

{{<example path="tellus/examples/tutorials/clustered/04_remote_watch.rs" anchor="join-cluster"/>}}

By default, a phi accrual failure detector, which adapts to how regular the heartbeats are,
decides when a node is unreachable, and `KeepMajority` decides once the unreachable members have
been unreachable for ten seconds. That suits a production network, but makes for a long wait here.
So this step configures a deadline failure detector, which counts a node as unreachable once its
last heartbeat is three seconds old, and lets `KeepMajority` decide after two seconds.

## Watching across nodes

{{<example path="tellus/examples/tutorials/clustered/04_remote_watch.rs" anchor="watcher"/>}}

The watcher watches the device manager on another node with the same `context.watch` as in the
getting started tutorial. When it gets the terminated signal, it prints that and stops.

## The first node

{{<example path="tellus/examples/tutorials/clustered/04_remote_watch.rs" anchor="first-node"/>}}

The first node records two readings with the device manager on the second node and asks for the
average. Then it spawns the watcher and kills the second node. Once the watcher has stopped, the
first node prints the second node's member state, finds the remaining device manager and asks it
for the average again.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example clustered_04_remote_watch
```

It prints:

```txt
Average temperature in attic: 20.30
The device manager has terminated
State of the second node: down
No readings in attic
```

The other device manager has no readings: they lived in the memory of the killed node. Making
state survive its node is what the
[event-sourced actors](@/docs/tutorials/event-sourced-actors/_index.md) are for.

## A synthesized signal

A killed node cannot send a terminated signal, so tellus synthesizes it on the first node, once the
cluster has downed the second node. That signal promises less than a real termination. It does not
prove that the device manager has stopped: across a network partition it could still be running.
It proves that no message from that device manager will ever be delivered on this node again, and
that is what the first node needs to stop relying on it.

## What you learned

A cluster that must survive a failure needs at least three nodes that agree on the membership.
The failure detector and the downing provider turn a node's silence into its downing, and a watch
on an actor of that node then fires with a synthesized signal. Next, a node leaves the cluster on
its own instead of being killed.
