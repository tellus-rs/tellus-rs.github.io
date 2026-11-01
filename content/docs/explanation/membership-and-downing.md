+++
title       = "Membership and downing"
description = "How tellus nodes agree on who belongs to the cluster, decide that a node is gone, and where that agreement ends."
weight      = 5
+++

A cluster has no leader that decides who belongs to it. Every node keeps its own list of members,
and the nodes agree by exchanging those lists. This page explains how a cluster comes into being,
how its nodes learn about each other, how they decide that a node is gone, and what no design can
decide for you.

## Members and incarnations

A member is a node at an address, together with its incarnation: an ID that the process mints when
it starts. A restarted process at the same address is hence a new member, never the old one coming
back. A member is in one of three states, and it only ever moves forward:

- **Up**: a member of the cluster.
- **Left**: it announced its own departure.
- **Down**: the cluster decided that it is gone.

Left and Down are final for that incarnation. Because states only move forward, two member lists
can always be merged: for every member, the later state wins. Merging lists in any order, twice or
crossed in transit, yields the same result, so the nodes need no further coordination to agree.

## Forming a cluster

A cluster comes into being by a decision, never by accident. `cluster::form` makes a node a cluster
of one. `cluster::bootstrap` decides on its own: it resolves the seeds, the addresses of all nodes
that may form the cluster, and joins through any of them that is already a member. While none is,
it waits until the set of seeds has stayed unchanged for the settle window, and then lets a
formation provider decide. The default provider, `Majority`, lets only the node at the lowest
address of the set form the cluster, and only once a strict majority of the set is known to be no
cluster yet. The other nodes join it.

Why both conditions? The lowest address ensures that nodes sharing a set of seeds form one cluster,
not several. The majority keeps a node that is cut off from the others from forming a cluster of
its own when it restarts. Both make formation fail closed: while the lowest address does not
answer, nothing forms. So discovery has to stop resolving nodes that are gone, or a cold start
never finishes.

## One cluster, one identity

The node that forms a cluster mints its ID, and every node that joins adopts it. Every connection
between two nodes starts with a handshake that names the cluster, and a node refuses a peer of
another cluster. So once a node is a member, no other cluster can admit it. Two clusters never
merge, either. If discovery shows the nodes different sets of seeds, two clusters can form side by
side. Each node keeps probing its seeds and lists the addresses that
answer as members of another cluster in `ClusterState::foreign_clusters`. That is a split for an
operator to resolve. Cluster IDs order by formation time, so the older cluster, the one with the
smaller ID, is usually the one to keep. First repair what caused the split: discovery has to give
the younger cluster's nodes the seeds of the older one, and the older one has to be reachable from
them. Only then stop every node of the younger cluster and start them again. Otherwise they may
form yet another cluster of their own. Afterwards, check that every node reports the older
cluster's ID in `ClusterState::cluster`.

## Spreading the membership

Every node sends a heartbeat to every other member once per heartbeat interval. A heartbeat carries
the member list only if the receiver has not been sent its current version yet, and every tenth
round regardless. When a node's list changes, it sends the new list right away. Membership updates
propagate along working connections. Each forwarding hop normally takes one gossip round, and
convergence is eventual: for a moment, two members may list different states for a third one.
Nothing in tellus waits for all members to agree, since a node that waited for every other one could
not decide anything while one of them was silent.

## Detecting a failure

Each node runs a failure detector for every other member. The default, phi accrual, learns how
regularly a member's heartbeats arrive and marks the member unreachable once its silence becomes
unlikely for that rhythm. The nodes share these observations, so every node can tell which
members it cannot reach, neither directly nor through others. Those are the members outside its
part of the cluster.

Not every failed connection splits the cluster. If two members cannot reach each other but both
still reach the others, the link between them is broken, not the cluster. No node is downed for
it, and the link lasts until it heals or an operator downs one of its ends; the nodes list it in
`ClusterState::broken_links`.

## Downing

A node that cannot reach a member cannot tell whether the member has crashed or whether only the
network between them has failed. So the decision to remove a member is not made by the failure
detector, but by a downing provider. The default, `KeepMajority`, waits until the unreachable
members have been unreachable for ten seconds. Then the side of the cluster that sees a strict
majority of the members downs the others, and every other side downs itself. An even split goes to
the side holding the member with the lowest address.

So at most one side of a partition survives, but only under a condition: the member lists agreed
before the partition. Two sides that never told each other about a new member can both count
themselves the majority. That is why a member holds back joins while any member is unreachable:
neither side of a partition can grow into a majority by admitting new nodes.

The rule has consequences that depend on the size of the cluster:

- In a cluster of two, every failure is an even split. The node at the lower address survives the
  other one failing, but when the lower one crashes, the survivor downs itself. Two nodes cannot
  guarantee surviving either one failing, so a cluster that must survive one failure needs three.
- A partition into more than two sides can leave none: when no side holds a strict majority, nor
  exactly half with the lowest address, every side downs itself.

## Why down is final

A downed member may still be running: the minority side of a partition keeps working until its own
deadline passes and it downs itself. Meanwhile the majority has already downed it. Watchers on the
majority side get a synthesized terminated signal for every actor they watched on the downed
members, which promises only that no message from those actors will be delivered there again, see
[the death watch ordering guarantee](@/docs/explanation/death-watch-ordering.md#across-nodes).

That promise holds because being downed is final. A downed node never comes back as the same
member: it severs its connections, and the process is expected to exit. A restarted process joins
again, as a new incarnation. The cluster remembers dead incarnations for a while and refuses them,
so a node that did not notice it was downed cannot sneak back in.

## Leaving versus dying

A node can also leave on its own. It announces its departure, the others list it as left as soon as
they receive the departure, and it tries to drain what it still has queued for them. No failure
detection and no downing are involved, so a departure is fast. That is why a node that is stopped on
purpose should leave, see [Shut down gracefully](@/docs/how-to/shut-down-gracefully.md). Downing is
for the nodes that cannot say goodbye.

`cluster::leave_on_terminated` leaves only once the node's actors have terminated. Their terminated
signals are hence queued before the departure, and they normally reach the watchers as real
terminations. That is the normal case, not a promise. A member may not finish reading the drain
within its leave timeout, or it may down the leaving node meanwhile. It then turns what it has not
read yet into synthesized signals. The `Departure` the leaving node gets lists the members that did
not acknowledge the drain. Plain `cluster::leave` does not stop any actor, so whatever still runs on
the node afterwards is cut off from the cluster.

## What this means for your deployment

- Run at least three nodes if the cluster has to survive one of them failing.
- Let discovery stop resolving nodes that are gone, so that bootstrap can finish.
- Size `BootstrapConfig::min_peers` to more than half the deployment where you can. Then no two
  nodes settle on disjoint views, but two views with different lowest addresses can still form two
  clusters.
- Treat a non-empty `foreign_clusters` and a lasting broken link as alarms for an operator, see
  [Observe a cluster](@/docs/how-to/observe-a-cluster.md).
- Exit when your node is downed, and let the process be restarted.
- Keep in mind that a downed member may still be running for a while, so two nodes may briefly act
  on the same state. An event-sourced actor's store rejects conflicting appends, but keeping a
  single writer per stream is still up to you, see
  [two incarnations of one actor](@/docs/explanation/event-sourcing.md#two-incarnations-of-one-actor).

For the protocol behind all of this, see
[Membership](https://github.com/tellus-rs/tellus/blob/main/docs/cluster.md#membership) and
[Failure detection and node death](https://github.com/tellus-rs/tellus/blob/main/docs/cluster.md#failure-detection-and-node-death)
in the internals documentation.
