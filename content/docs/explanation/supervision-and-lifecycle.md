+++
title       = "Supervision and lifecycle"
description = "How actors start, fail, restart and terminate, and in which order their resources are released."
weight      = 5
+++

Every actor runs through the same lifecycle: it starts with `init`, handles messages with
`receive`, and terminates. In between, it can fail. This page explains what tellus does at each of
these points, and why.

## The actor tree

Every actor except the root has a parent, the actor which spawned it. The actors of a system form
a tree, and the tree defines responsibility. When an actor stops, its children stop first. When an
actor restarts, its children stop as well, since they belong to the failed state. No actor
outlives its parent.

## Failing

An actor fails when `init` or `receive` returns an error or panics. tellus catches the panic, so
the two cases are handled the same way. The actor's supervision strategy decides what happens next.

`Stop`, the default, terminates the actor. Its watchers receive a terminated signal and decide
what to do. The group of the getting started tutorial, for example, forgets a device when it
terminates, from the [watching step](@/docs/tutorials/getting-started/watch.md) on.

`Restart` keeps the actor alive with a new state:

1. The children stop, and tellus waits until they have terminated.
2. A backoff delay passes.
3. `init` runs again, on the same actor value, and produces a fresh state.

The mailbox survives. Messages which arrived behind the failing message, or arrive during the
backoff, are handled by the restarted actor. The failing message itself is not delivered again.
Watches survive, too. Timers do not: a restart cancels all of the actor's timers.

## Restarts are limited

A failure which a restart cannot fix, such as a misconfiguration, would otherwise restart the
actor forever. The `RestartPolicy` therefore limits the number of consecutive restarts with
`max_restarts`. When the actor fails once more after `max_restarts` restarts, it stops, and its
watchers learn about it. The count resets once the actor has run for `reset_after` without
failing.

The backoff delay doubles with every consecutive restart, from the backoff's minimum up to its
maximum. By default the backoff grows from 250 ms to 4 s, and `reset_after` is 30 s. A failing
dependency, for example a database which is down, is then retried less and less often instead of
in a tight loop. A failing `init` counts like a failing `receive`, including the very first one at
spawn.

## Stopping

An actor stops when `receive` returns `Control::Stop`, when it fails under `Stop` or after its
last allowed restart, or when its parent stops. For the root, `ActorSystem::stop` takes the
parent's role. A stop never interrupts `receive`: the message being handled is finished first.

## Terminating, in order

Termination releases the actor's resources in a fixed order:

1. The state is dropped, so its destructors run.
2. The mailbox is closed, and the queued messages are dropped. An `ask` among them fails with
   `AskError::NoReply`.
3. The children stop, recursively, and the actor waits until all of them have terminated.
4. The actor value is dropped.
5. The watchers receive the terminated signal.

The order matters for what a terminated signal proves. When the signal arrives, the actor's state,
its actor value and all its descendants are gone, with their destructors run. A resource that must
be released before anybody learns about the termination, such as a file lock, is released by
then. A resource which the children use belongs in the actor value, because the state is dropped
while the children may still be running.

## Configuration

The supervision strategy and the mailbox capacity form an actor's `ActorConfig`. It is set in code
or loaded from a file, as shown in
[Configure an actor from a file](@/docs/how-to/configure-supervision.md).
