+++
title       = "Evolve events"
description = "Change the shape of a stored event and let the new release read the old events by upcasting them while it replays."
weight      = 62
+++

Events outlive the code which wrote them. When the shape of an event changes, the events already
stored keep the old shape, since tellus never rewrites the store. Instead, the new release decodes
the old shape and converts it while it replays: it upcasts the old events.

The examples on this page come from a thermometer whose first release records its readings in
Fahrenheit and whose second release records them in Celsius. The example holds both releases in
one program.

## Version the event

{{<example path="tellus/examples/how_to/evolve_events.rs" anchor="recorded-v1"/>}}

Every event implements `Versioned`, and tellus stores its manifest and schema version alongside the
payload. The manifest is a stable name for the event type, independent of the Rust type. The schema
version is that of the code which wrote the event. Release 1 stores its readings as `recorded`
events with schema version 1.

In an application, release 1 would call this type `Recorded`. Release 2 keeps it under a new name,
`RecordedV1`, only to decode the events release 1 stored.

## Upcast the old version

Release 2 stores the reading in Celsius, under the same manifest and with schema version 2:

{{<example path="tellus/examples/how_to/evolve_events.rs" anchor="recorded"/>}}

`Versioned::decode` gets the stored schema version and payload. The default implementation decodes
the current version only. Release 2 overrides it: it decodes version 2 as it is, and version 1 as a
`RecordedV1`, which it converts to Celsius. Every other version is an
`UnsupportedSchemaVersion` error. tellus checks the manifest before it calls `decode`, so a stored
event of another type never gets this far.

The rest of release 2 knows only `Recorded`. Its `apply` gets every event in the current shape,
however old the stored one is.

## What to keep in mind

**An upcast stays as long as the old events.** The store is never rewritten, so every recovery
decodes the events of release 1 again. Release 2 and every later release keep the version 1 branch
for as long as a stream holds events of that version.

**The manifest never changes.** Once events are stored under a manifest, the type keeps it, also
through a rename or a move. tellus rejects an event whose stored manifest differs from the type's
`MANIFEST`.

**Nor does the codec.** Stored events do not name their codec, so the one an application starts
with stays. The default is CBOR; the example selects `Json` with `Persistence::with_codec`, which
makes the stored payloads readable below. `Json` fails to encode a NaN or an infinity.

**An event which cannot be decoded fails the recovery.** The actor then fails into its supervision
strategy, before it handles any command.

**Snapshots need no upcast.** A snapshot which can no longer be decoded is discarded, and recovery
replays the events from the start instead. With the default `Versioned::decode`, raising the
snapshot's schema version when its shape changes makes every older snapshot undecodable, and hence
discarded. A custom `decode` can still read them.

## Run it

{{<example path="tellus/examples/how_to/evolve_events.rs" anchor="main"/>}}

Release 1 records two readings and stops. Release 2 recovers from the same store, records a third
reading and is asked for all of them. It was told the reading before it was asked, so the answer
includes it. From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features persistence-in-memory --example how_to_evolve_events
```

```txt
Stored event 0: recorded version 1, {"fahrenheit":70.7}
Stored event 1: recorded version 1, {"fahrenheit":71.6}
Readings in Celsius: 21.5, 22.0, 22.4
Stored event 0: recorded version 1, {"fahrenheit":70.7}
Stored event 1: recorded version 1, {"fahrenheit":71.6}
Stored event 2: recorded version 2, {"celsius":22.4}
```

Release 2 answers all three readings in Celsius: the first two are the Fahrenheit readings of
release 1, upcast during its recovery. Afterward the store holds both versions side by side, and the
events of release 1 are still the ones release 1 wrote.
