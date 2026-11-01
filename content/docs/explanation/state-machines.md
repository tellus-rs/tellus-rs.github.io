+++
title       = "Actors as state machines"
description = "Why the state is passed into receive and returned from it, and how that models a state machine."
weight      = 1
+++

An actor reacts to one message at a time, and how it reacts depends on what happened before. That
is a state machine: a set of states, and for each state and input a transition to the next state.
tellus makes this explicit in the signature of `receive`. This page explains how, and why the
state is not simply a field of the actor.

## The state goes in and comes out

`receive` takes the current state by value and returns the next one inside
`Control::Continue`. The state before the call is consumed, and only the returned state exists
afterward. `init` produces the first state, and `Control::Stop` ends the machine.

Consider a device which ignores readings until it is calibrated. Its state is an enum with one
variant per state of the machine:

{{<example path="tellus/examples/explanation/state_machine.rs" anchor="types"/>}}

Its `receive` matches on the state and the message together:

{{<example path="tellus/examples/explanation/state_machine.rs" anchor="receive"/>}}

Every arm is one transition. An uncalibrated device drops readings, a calibrated one corrects
them by its offset, and a calibration moves either state to `Calibrated`. Because the state is
an enum, the compiler checks that the match covers every combination of state and message. When
a new state or message is added, every combination the match lacks is a compile error.

## Why not `&mut self`?

Many actor frameworks give the handler mutable access to the state, as `&mut self` or as a
`&mut` state argument. tellus separates two values instead. The actor value, `Device` here, is
borrowed immutably and lives as long as the actor. The state is owned by the run loop and passed
through `receive`.

Why does the separation matter? Because of failures. With mutable access, a handler which fails
halfway through a change leaves a partly changed state behind. In tellus, a handler which fails
never returns a state, so there is no partly changed one to keep. Under the `Restart` strategy,
tellus calls `init` again, on the same actor value. Whatever the actor value carries, for example
configuration or a connection pool, survives the restart. Whatever is in the state is rebuilt
from scratch.

The state's type also says which data belongs to which state. A calibrated device has an offset,
and an uncalibrated one has none. Because `receive` owns the state, a transition can move data out
of the old variant into the new one. It needs no `mem::replace` and no placeholder value, as a
transition through a `&mut` reference would.

## Changing behavior

Hewitt's actor model says an actor designates the behavior for the next message. In tellus, the
behavior is the function `receive` together with the state it receives. The function never
changes, but the returned state selects the arms which apply to the next message. Returning
`State::Calibrated` changes how the device treats its next reading, which is exactly the change
of behavior the model describes.

The state is also what the other parts of tellus build on. An event-sourced actor folds its
events into the state with `apply`, and its recovery rebuilds exactly that state. A unit test
calls `receive` with a state and compares the returned one, as shown in
[Unit test an actor](@/docs/how-to/unit-test.md).
