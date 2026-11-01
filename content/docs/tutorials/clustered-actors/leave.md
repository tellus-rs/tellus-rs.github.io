+++
title       = "Leaving gracefully"
description = "Stop a device manager on request and let its node leave the cluster instead of being killed."
weight      = 5
+++

Most nodes do not crash. They are stopped, for a deployment, a scale down or a restart. A node
that stops on purpose can tell the cluster so, which spares everyone the failure detection of the
previous step. In this step the device manager stops on request, and its node leaves the cluster.

## Stopping the device manager

`Command` gets one more variant:

{{<example path="tellus/examples/tutorials/clustered/05_leave.rs" anchor="command"/>}}

The device manager answers `Stop` with `Control::Stop`. It is the root actor of its node's actor
system, so the actor system terminates with it.

## Leaving the cluster

{{<example path="tellus/examples/tutorials/clustered/05_leave.rs" anchor="manager-node"/>}}

`leave_on_terminated` waits until the actor system has terminated and then leaves. The node
announces its departure to every member and tries to drain what it still has queued for them,
within its `leave_timeout`. A member acknowledges once those frames have reached its delivery path,
a mailbox or a logged dead letter. That does not prove an actor has handled them. The call returns
a `Departure`, which lists the members that acknowledged and those that did not. A member may not
acknowledge, for example, because its connection ended first or the timeout passed. tellus logs a
warning for every member that did not acknowledge. Leaving is final, like being downed: the node
sends and admits nothing afterward. tellus does not end the process, so `manager_node` returns and
the program exits. Only a restarted process joins again, as a new node.

## Watching a departure

{{<example path="tellus/examples/tutorials/clustered/05_leave.rs" anchor="await-left"/>}}

`await_left` waits until this node lists the given member as left.

## The first node

{{<example path="tellus/examples/tutorials/clustered/05_leave.rs" anchor="first-node"/>}}

The first node spawns the watcher before it records the readings, so the watch is on its way long
before anything stops. Instead of killing the second node, it then tells the device manager to
stop. It waits for the watcher, then for the second node to be listed as left, and for its process
to exit. Finally, it finds the remaining device manager and asks it for the average again.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example clustered_05_leave
```

It prints:

```txt
Average temperature in attic: 20.30
The device manager has terminated
State of the second node: left
No readings in attic
```

The second node is listed as left, not as down, without any failure detection: that is why this
step needs no faster configuration than the defaults.

## A real termination

This time the terminated signal is normally real. The device manager's node sends it over the wire
as part of the device manager's termination. So it arrives behind every message the device manager
sent the watcher, exactly as within one process. In two cases the watcher gets a synthesized
signal instead, as in the previous step. One is a device manager which is already gone when the
watch arrives. The other is a first node which cannot finish reading what the second node sent
before its leave timeout. The API does not tell the two apart, and tellus offers no way to wait
until a remote watch is in place.

## What you learned

A node that stops on purpose leaves the cluster: `leave_on_terminated` waits for its actors to
terminate, announces the departure and drains what is queued. The others list the node as left as
soon as they receive the departure, and its actors' terminated signals normally arrive as real
terminations.

## Where to go from here

You have spread the device manager over a cluster. The nodes bootstrap from a list of seeds, and
messages and references cross the wire. The receptionist finds actors by key, and the cluster
handles both ways out of it, a crash and a departure.

For production, the how-to guides show how to
[run on Kubernetes](@/docs/how-to/run-on-kubernetes.md),
[shut down gracefully](@/docs/how-to/shut-down-gracefully.md),
[observe a cluster](@/docs/how-to/observe-a-cluster.md) and
[secure it with mutual TLS](@/docs/how-to/secure-with-mutual-tls.md).
[Membership and downing](@/docs/explanation/membership-and-downing.md) explains how the nodes agree
on who belongs to the cluster, and
[Message delivery](@/docs/explanation/message-delivery.md#across-nodes) and
[the death watch ordering guarantee](@/docs/explanation/death-watch-ordering.md#across-nodes) what
holds across nodes.
