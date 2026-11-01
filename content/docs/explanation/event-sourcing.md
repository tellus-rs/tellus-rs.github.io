+++
title       = "Event sourcing"
description = "How event-sourced actors persist, recover and evolve, and what tellus guarantees about it."
weight      = 7
+++

An event-sourced actor stores what happened to it, not what its state is. Its state is the result
of applying all its events, in order, to an initial state. This page explains how tellus
implements that, what it guarantees, and where the guarantees end. The
[event-sourced actors tutorial](@/docs/tutorials/event-sourced-actors/_index.md) shows it in
practice.

## Commands and events

An event-sourced actor receives commands, like any actor receives messages. A command is a
request, and the actor may reject it. An event is a fact, something which has happened and cannot
be rejected anymore. `handle` turns a command into events: it validates the command against the
current state and returns an `Effect` with the events it causes. `apply` turns an event into the
next state. It is the only place where the state changes.

## Events first

tellus appends the events of an effect to the store and only then applies them. If the append
fails, the events are not applied, and the actor fails into its supervision strategy. The state in
memory therefore never contains anything the store does not have. All events of one effect are
appended atomically: after a crash the store contains all of them or none.

Writes are strict. A command is settled, with its events stored and applied and its continuation
run, before the actor takes the next message from its mailbox. Ordering per sender carries over from plain actors.

## Continuations run at most once

A reply or a message to another actor must not happen before its events are stored, otherwise the
world would learn about something which a crash could still undo. Such actions therefore go into a
continuation, attached to the effect with `then`. It runs after the events are stored and
applied.

A crash between the append and the continuation loses the continuation. It is not run again on
recovery, because recovery never runs effects. Outward-facing actions are therefore at most once,
exactly like `tell`, while the events are durable.

## Recovery

When an event-sourced actor starts or restarts, it recovers its state before it handles any
command:

1. The latest snapshot, if there is one, becomes the state through `init_from_snapshot`. Without a
   snapshot, `init` produces the initial state.
2. The events after the snapshot are read in order and applied with `apply`.
3. `recovered` runs once on the result.

Replay runs exactly the `apply` calls which the live actor ran, so it reconstructs exactly the
state the actor had. That requires `apply` to be pure: no I/O, no clock, no randomness, and no
failure. Anything which touches the world at start, such as spawning children, belongs in
`recovered`.

A restart under supervision is a recovery too. That also resolves an uncertain append: if the
events reached the store before the failure, replay applies them, and if not, they were never
applied.

## Snapshots

Replaying a long history takes time. A snapshot shortens it: `snapshot` can offer one after an
effect with events, and recovery then starts from the latest snapshot. Snapshots are never the
source of truth. A failure to save one is only logged, and a snapshot which can no longer be
decoded is discarded in favor of a full replay.

## Two incarnations of one actor

A `PersistenceId` names an event stream. Normally exactly one actor writes to it, but a
misconfiguration or a network partition can start a second incarnation. tellus protects the
stream with optimistic concurrency: every append states the sequence number it expects to write
at, and the store rejects it if another append got there first. The loser fails into its
supervision strategy. Under `Restart`, it recovers the winner's events by replay and continues on
top of them. The stream never loses events.

This is not exclusive ownership. The recovered loser can win the next append, so two live
incarnations can take turns writing to the stream. Each append is consistent with the events
before it, but keeping a single writer is up to the application.

## Evolving events

Events outlive the code which wrote them. Each stored event carries a manifest, a stable name
independent of the Rust type, and a schema version, both from `Versioned`. When an event changes,
its version increases, and `Versioned::decode` can convert old versions while reading. The stored
events themselves are never rewritten. An event with a version which the code no longer decodes
fails the recovery.
