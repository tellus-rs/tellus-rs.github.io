+++
title       = "Form without the lowest seed"
description = "Let bootstrap pass over a lowest seed which never starts, at the price of possibly forming a second cluster."
weight      = 66
+++

`cluster::bootstrap` forms a new cluster only when a formation provider decides so. The default,
`Majority`, lets only the node at the lowest address of the seeds form, and only once a strict
majority of the seeds is known to be no cluster yet. While the lowest address does not answer,
nothing forms. That is safe, but a discovery which keeps resolving a node that is gone, such as a
fixed list of seeds, then never lets a cold start finish. `MajorityWithFallback` passes over a
lowest address which has been unavailable for a while. Its price is that a lowest address which is
only unreachable, not gone, can form a second cluster.

The examples on this page come from three seeds, of which the lowest never starts. The program plays
the other two nodes, as in the
[clustered actors tutorial](@/docs/tutorials/clustered-actors/two-nodes.md).

## Choose the formation provider

{{<example path="tellus/examples/how_to/form_without_the_lowest_seed.rs" anchor="join-cluster"/>}}

`BootstrapConfig::formation_provider` creates the provider. `MajorityWithFallback::new(after)`
keeps the strict majority, but the address which may form is the lowest one of the seeds minus
every address which has answered nothing but unavailable for at least `after`, here two seconds. An
address's timer starts with the first round of join attempts in which it is unavailable. Any other
answer, or a round which did not attempt it, resets the timer.

`join_attempt_timeout` bounds how long a round waits for each attempt, five seconds by default. An
attempt which outlasts it counts as unavailable. Nothing answers at the missing seed, so its
attempts always time out, and the example lowers the timeout to one second to finish sooner.

With the `serde` feature, `BootstrapConfig` is deserializable, and the provider is chosen by name:

```yaml
formation_provider:
  majority_with_fallback:
    after: 60s
```

## Form and join

{{<example path="tellus/examples/how_to/form_without_the_lowest_seed.rs" anchor="first-node"/>}}

The first node runs at the second seed and starts the second node at the third. Nothing ever runs
at the first seed. Once it has been unavailable for two seconds, the second seed is the lowest
address left. Two of the three seeds are known to be no cluster, a strict majority, so the first
node forms the cluster. The second node joins it:

{{<example path="tellus/examples/how_to/form_without_the_lowest_seed.rs" anchor="second-node"/>}}

It waits until both nodes are up and then leaves. The first node waits until it lists the second
node as left and prints the state of every seed.

## What to keep in mind

**The price is uniqueness.** A lowest seed which is running but unreachable from the others can
form a cluster of its own beside theirs. The two clusters never merge. Each lists the other in
`ClusterState::foreign_clusters` once the probe reaches the other cluster, and an operator has to
resolve the split, see
[Membership and downing](@/docs/explanation/membership-and-downing.md#one-cluster-one-identity).

**A discovery which drops nodes that are gone needs no fallback.** Under `Majority`, the next
lowest address inherits the role once discovery no longer resolves the lowest one, as long as the
smaller set still holds `min_nodes` addresses. Only a discovery which keeps resolving nodes that
are gone, such as a fixed list of seeds, needs `MajorityWithFallback`.

**`after` sets how long an unavailable seed can block the fallback.** The timer starts when a round
of join attempts first reports the seed unavailable. A longer `after` waits longer for a lowest seed
which is only slow to start. A shorter one passes over a lowest seed sooner, including one which is
merely unreachable. Bootstrap can still join an existing cluster sooner, and forming a new cluster
still needs a settled view and a strict majority.

## Run it

{{<example path="tellus/examples/how_to/form_without_the_lowest_seed.rs" anchor="main"/>}}

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_form_without_the_lowest_seed
```

```txt
Seed 1: never a member
Seed 2: up
Seed 3: left
```

The first seed never became a member. The second one formed the cluster without it and is still
up, and the third one joined and left again. With the default `Majority`, the two nodes would wait
for the first seed until the bootstrap timeout ended them.
