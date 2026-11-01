+++
title       = "Observe a cluster"
description = "Follow the membership as it changes, and serve a node's view of its cluster over HTTP."
weight      = 8
+++

Every node has its own view of the cluster: the members with their states, the members it cannot
reach, and more. tellus offers that view as a value that changes over time, and the
`tellus-cluster-inspect` crate serves it over HTTP.

## Read the current view

`cluster::cluster_state` returns a `tokio::sync::watch::Receiver` of the `ClusterState`, or an error
if the endpoint has not been started. The receiver's current value is this node's view, and
`wait_for` waits for a view with a given property, as the
[clustered actors tutorial](@/docs/tutorials/clustered-actors/_index.md) does. A `ClusterState`
holds:

- `members`, every member with its address, incarnation and state: up, left or down. This node is
  among them from the start.
- `unreachable`, the members that are up but that this node cannot reach, neither directly nor
  through other members.
- `broken_links`, direct links one up member reports broken while both ends still reach each other
  through other members. No downing provider acts on such a link: it lasts until it heals or you
  down one end with `cluster::down`. Meanwhile, messages between the two ends are queued, asks
  between them time out and watches between them do not fire.
- `foreign_clusters`, the addresses that answered as members of another cluster. Two clusters never
  merge, so a non-empty list is a split for you to resolve. tellus logs it at error level every
  five minutes while it lasts.
- `cluster`, the ID of the cluster this node is a member of, the same on every member. It is `None`
  until this node has formed or joined a cluster.

Where the endpoint stands is not part of the view: `cluster::lifecycle` tells whether it is a
member of no cluster yet, a member, or downed for good.

## Follow the transitions

`cluster::changes` yields the current version of the view first and then every new one, in
order. `ClusterState::diff` compares two versions member by member:

{{<example path="tellus/examples/how_to/observe_a_cluster.rs" anchor="first-node"/>}}

{{<example path="tellus/examples/how_to/observe_a_cluster.rs" anchor="describe"/>}}

The first node remembers the previous version and prints what changed, while a second node joins,
stays a second and leaves. `Change::Settled` and `Change::Gap` report the receptionist's verdict and
a subscriber that fell behind; the example skips them. After a gap, the next state supersedes
everything missed, so a diff against it is still correct.

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_observe_a_cluster
```

```txt
second node: up
second node: left
```

The first node itself is listed up before it forms the cluster, so its own state yields no
transition.

## Serve the view over HTTP

The `tellus-cluster-inspect` crate is an axum `Router` that serves the view:

```sh
cargo add tellus-cluster-inspect axum
cargo add tellus --features cluster-dev
```

The `cluster-dev` feature is only for `QuicTransport::dev`, which the example uses. A production
node needs only `cluster` and uses mutual TLS, see
[Secure with mutual TLS](@/docs/how-to/secure-with-mutual-tls.md).

{{<example path="tellus-cluster-inspect/examples/how_to_serve_cluster_state.rs" anchor="main"/>}}

Call `tellus_cluster_inspect::router` after `cluster::start_endpoint`, or it fails, and inside the
Tokio runtime, since it spawns the task recording the changes. Mount the router into your own HTTP
server. It brings no authentication and binds no port of its own. It reveals the cluster's
topology, so mount it behind whatever protects the rest of your server.

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus-cluster-inspect --example how_to_serve_cluster_state
```

`GET /inspect/cluster` answers a snapshot as JSON: the `ClusterState`, the endpoint's lifecycle
(`unformed`, `formed` or `downed`) and the receptionist's settlement. `GET /inspect/events` streams
every change as server-sent events. The router keeps the latest changes since it was created, up
to `InspectConfig::events_kept`, 1024 by default. A new client gets a `hello`, then the changes the
router still keeps, oldest first, and then the current state and verdict. A client that reconnects
with the `Last-Event-ID` it saw last continues right after it, as long as the router still keeps
that position.

```sh
curl localhost:8080/inspect/cluster
curl -N localhost:8080/inspect/events
```
