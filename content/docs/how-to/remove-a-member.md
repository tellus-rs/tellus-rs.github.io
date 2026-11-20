+++
title       = "Remove a member"
description = "Take a node out of a cluster: let it leave on its own, or down it from another member and let it exit."
weight      = 67
+++

There are two ways out of a cluster. A node which can still say goodbye leaves: it announces its
departure, and the others list it as left without detecting a failure. A node which cannot, or
should not, is downed by another member: `cluster::down` decides that it is gone. Either way the
node's incarnation is out for good, and only a restarted process joins again.

The examples on this page come from a cluster of three nodes. The second node leaves, and the first
node downs the third. The program plays all three nodes, as in the
[clustered actors tutorial](@/docs/tutorials/clustered-actors/two-nodes.md).

## Leave and drain outgoing messages

{{<example path="tellus/examples/how_to/remove_a_member.rs" anchor="leaving-node"/>}}

The second node first waits until the receptionist has settled, so every peer knows it before it
leaves. Then it waits until its stdin closes, which is how the first node tells it to leave in this
example. `cluster::leave` announces the departure to every member and drains what the node still
has queued for them, within `EndpointConfig::leave_timeout`. It answers a `Departure`, which lists
the members that acknowledged the drain and those that did not. The example treats a missing
acknowledgment as an error.

`leave` stops no actor, so whatever still runs on the node is cut off from the cluster afterward. A
node with actors leaves with `cluster::leave_on_terminated` instead, which waits for its actor
system to terminate first, see
[Leaving gracefully](@/docs/tutorials/clustered-actors/leave.md).

## Down a member from another node

{{<example path="tellus/examples/how_to/remove_a_member.rs" anchor="first-node"/>}}

The first node waits until all three nodes are up. It closes the stdin of the second node and waits
until it lists that node as left. Then it calls `cluster::down` with the address of the third node.
That runs the node death sequence on the first node: pending asks toward the third node fail, its
watchers receive synthesized terminated signals, and its incarnation is refused from then on. `down`
fails if no up member advertises the address, and for this node's own address, which `leave` is
for.

Both waits use the cluster state, the same way:

{{<example path="tellus/examples/how_to/remove_a_member.rs" anchor="await-member-state"/>}}

## Exit when downed

{{<example path="tellus/examples/how_to/remove_a_member.rs" anchor="downed-node"/>}}

The third node waits until `cluster::lifecycle` reports `Lifecycle::Downed` and exits. A node
that has left also reports `Downed`.

## What to keep in mind

**Leave when you can.** A departure needs no failure detection and no downing, so the others list
the node as left as soon as they receive it. With `leave_on_terminated`, the terminated signals of
its actors normally arrive as real terminations. A node which is stopped on purpose should therefore
leave, see [Shut down gracefully](@/docs/how-to/shut-down-gracefully.md).

**Down a member only when it is gone or must go.** A downed member may still be running, for
example on the other side of a partition. Watchers receive synthesized terminated signals for its
actors, which promise only that no message from those actors is delivered again, see
[the death watch ordering guarantee](@/docs/explanation/death-watch-ordering.md#across-nodes).
`cluster::down` is also how an operator ends a broken link, by downing one of its ends, see
[Observe a cluster](@/docs/how-to/observe-a-cluster.md).

## Run it

{{<example path="tellus/examples/how_to/remove_a_member.rs" anchor="main"/>}}

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_remove_a_member
```

```txt
The second node has left
The third node is down
Up members: 1
```

The second node is listed as left, the third as down, and both processes exit successfully. The
first node remains as the only member which is up.
