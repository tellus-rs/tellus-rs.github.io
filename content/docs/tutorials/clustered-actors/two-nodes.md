+++
title       = "Two nodes"
description = "Start two nodes that find each other through a list of seeds and form a cluster."
weight      = 1
+++

A cluster is a set of nodes, and a node is a process with a remoting endpoint. Before any actor
can talk to another node, the nodes have to find each other and agree that they form one cluster.
In this step two nodes do just that.

## Starting a node

Every node runs the same function to become a member of the cluster:

{{<example path="tellus/examples/tutorials/clustered/01_two_nodes.rs" anchor="join-cluster"/>}}

`QuicTransport::dev` binds a QUIC socket to the given address. It skips every certificate check,
so use it only on a network you trust, such as your own machine. `start_endpoint` starts the
endpoint, which owns the connections to the other nodes. There is one endpoint per process, and
`EndpointConfig::new` takes the address the other nodes reach this one at.

`bootstrap` then makes the node a member. It resolves the seeds, the addresses of all nodes that
may form the cluster, and tries to join through every one of them but its own. As long as none of
them is a member yet, there is no cluster to join. The seeds have to stay unchanged for the settle
window (`BootstrapConfig::settle`, three seconds by default). Then the node at the lowest
address forms the cluster, and the other node joins it. `bootstrap` returns once this node is a
member, so it is wrapped in a timeout.

## Two processes

The program plays both nodes, and its first argument decides which one runs:

{{<example path="tellus/examples/tutorials/clustered/01_two_nodes.rs" anchor="main"/>}}

Started without arguments, it is the first node. The first node picks two free ports with the
`reserved_addrs` helper, which lets the operating system choose them. Nothing holds the ports
until the nodes bind them, so another process could take one in between. The first node then
starts the second node with the `spawn_node` helper, which runs this program again with `node`,
the second node's address and the seeds as arguments:

{{<example path="tellus/examples/tutorials/clustered/01_two_nodes.rs" anchor="first-node"/>}}

`cluster_state` returns a `tokio::sync::watch::Receiver` of the `ClusterState`, which changes
whenever this node learns something new about the members. The first node waits until both
members are up and prints how many there are.

The second node reads exactly these arguments, joins and then waits:

{{<example path="tellus/examples/tutorials/clustered/01_two_nodes.rs" anchor="second-node"/>}}

It never stops on its own. `spawn_node` returns the second node's `Child`, configured to kill the
process when it is dropped, so the second node ends together with the first.

## Run it

Like those of the other tutorials, every step is an example in the tellus repository, and the
pages show its relevant parts. If you have not cloned the repository yet, clone it once, at the
release these pages show, and run the examples from there:

```sh
git clone --branch {{<tellus_tag/>}} https://github.com/tellus-rs/tellus
cd tellus
cargo run --quiet -p tellus --features cluster-dev --example clustered_01_two_nodes
```

It prints:

```txt
Members up: 2
```

The run takes a few seconds, most of them the settle window. Only the first node prints to
stdout; set `RUST_LOG=tellus=debug` to watch both nodes bootstrap in the logs on stderr.

## What you learned

A node is a process with a remoting endpoint. `bootstrap` turns a list of seeds into a cluster:
the node at the lowest address forms it, the others join. `cluster_state` shows a node's view of
the members. Next, the device manager moves to a node of its own, and its messages have to cross
the wire.
