+++
title       = "Finding the device manager"
description = "Find the device manager by its key alone, wherever it runs, through the receptionist."
weight      = 3
+++

The first node of the previous step looked the device manager up at the address of its node. In a
real cluster, the node that asks rarely knows which node runs what. In this step the first node
finds the device manager by its key alone.

## Subscribing to a key

{{<example path="tellus/examples/tutorials/clustered/03_receptionist.rs" anchor="find-manager"/>}}

`receptionist::subscribe` returns a `Subscription` to every actor registered under the key, on any
member. `current` resolves the set as of now into references, and `changed` waits until it has
changed since the last `current`. So instead of polling, `find_manager` waits for the next
registration, the termination of a registered actor or a change of membership.

The set only holds actors on members that are up. A registration disappears when its actor
terminates or its node is gone, so a subscription also tells you when an actor you found is no
longer there.

## The first node

The first node now calls `find_manager()` instead of `lookup_manager(seeds[1])`; everything else
is unchanged:

{{<example path="tellus/examples/tutorials/clustered/03_receptionist.rs" anchor="first-node"/>}}

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example clustered_03_receptionist
```

It prints:

```txt
Average temperature in attic: 21.50
No readings in cellar
No readings in garage
```

The output is the same as in the previous step, but nothing in the first node depends on where
the device manager runs anymore.

## What you learned

The receptionist finds actors by key on any member. A subscription follows the set of registered
actors as registrations, terminations and members come and go. Next, there are two device managers,
and one of them goes away for good.
