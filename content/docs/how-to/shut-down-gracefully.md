+++
title       = "Shut down gracefully"
description = "Take a node out of the load balancer's rotation, drain its requests, leave the cluster and exit."
weight      = 7
+++

A node that is stopped should neither fail the requests a load balancer still sends it nor leave the
other nodes to detect its absence. So on a shutdown signal it reports itself unhealthy and keeps
serving until the load balancer has taken it out of rotation. Then it drains the requests still in
flight, and only then stops its actors and leaves the cluster. The examples on this page come from a
node that serves a health endpoint and an application endpoint backed by an actor.

## Serve requests and health

{{<example path="tellus/examples/how_to/shut_down_gracefully.rs" anchor="app"/>}}

`/count` asks the counter actor, so it only works while the actors run. `/health` answers 200
while the node is healthy and 503 once it is not. A load balancer, or a Kubernetes readiness probe,
checks it periodically and stops sending requests to a node that fails it.

## Wait for the signal

{{<example path="tellus/examples/how_to/shut_down_gracefully.rs" anchor="shutdown-signal"/>}}

Kubernetes, Docker and systemd stop a process with SIGTERM; Ctrl-C sends SIGINT. The node treats
both alike.

## Shut down in order

{{<example path="tellus/examples/how_to/shut_down_gracefully.rs" anchor="shut-down"/>}}

1. The node reports itself unhealthy, so the load balancer starts taking it out of rotation.
2. It lingers, still serving every request with its actors running. The linger has to exceed the
   time the load balancer needs to drop a node that fails its health check. For a load balancer
   that checks every two seconds and drops a node after one failure, that is two seconds. On
   Kubernetes, the readiness probe is not what takes a terminating pod out of rotation: as soon as
   its deletion starts, Kubernetes marks its endpoints not ready. There the linger covers the time
   kube-proxy, ingresses and external load balancers need to stop routing to the pod. The example
   lingers for five.
3. It tells the HTTP server to shut down gracefully: the server accepts no new connections and
   waits for the requests in flight, bounded by a drain timeout.
4. It stops its actor system and leaves the cluster. `leave_on_terminated` first waits for the actor
   system to terminate, without a deadline of its own, and then tries to drain what the node still
   has queued for the other members, within `EndpointConfig::leave_timeout`. The other members list
   the node as left as soon as they receive the departure, and the `Departure` tells which of them
   acknowledged the drain. The outer timeout bounds both parts: a termination timeout for the actors
   plus the leave timeout.

The HTTP server runs in a task of its own, and the drain signal shuts it down:

{{<example path="tellus/examples/how_to/shut_down_gracefully.rs" anchor="main"/>}}

## Budget the shutdown

Whatever stops the process waits only so long before it kills it: Kubernetes waits
`terminationGracePeriodSeconds`, thirty by default. That has to cover all four steps: the linger,
the drain timeout, the termination timeout and the leave timeout. In the example, these are five,
five, five and three seconds, eighteen in all. A node killed before it is done has not left: the
others detect its absence and down it, as for a crash.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster-dev --example how_to_shut_down_gracefully
```

In a second terminal, `curl -i localhost:8080/health` answers 200 and `curl localhost:8080/count`
counts. Press Ctrl-C in the first one. For the five seconds of the linger, `/health` answers 503,
while `/count` keeps counting. Then the node drains, leaves and exits:

```txt
Serving, press Ctrl-C to shut down
Unhealthy, still serving
Drained, leaving the cluster
Left the cluster
```
