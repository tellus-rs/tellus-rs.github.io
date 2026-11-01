+++
title       = "PostgreSQL"
description = "Store the device's events and snapshots in PostgreSQL and recover them across processes."
weight      = 4
+++

The in-memory store forgets everything when the process ends. For real persistence, the
[`tellus-persistence-postgres`](https://crates.io/crates/tellus-persistence-postgres) crate stores
events and snapshots in PostgreSQL. The device stays as in the previous step, apart from its
persistence ID. The store and `main` change.

## Using the PostgreSQL store

{{<example path="tellus-persistence-postgres/examples/tutorials/event_sourced/04_postgres.rs" anchor="main"/>}}

`PostgresStore` wraps a `sqlx` connection pool. `migrate` creates the tables for events and
snapshots if they do not exist yet. The same store serves as event store and snapshot store.

Every run of this program records one reading and then asks for the readings. Since the device
recovers all earlier readings from the database, the count grows from run to run.

## Run it

From a clone of the tellus repository, start PostgreSQL with Docker and run the example twice:

```sh
docker compose up -d --wait postgres
cargo run --quiet -p tellus-persistence-postgres --example event_sourced_04_postgres
cargo run --quiet -p tellus-persistence-postgres --example event_sourced_04_postgres
```

It prints:

```txt
Readings so far: 1
Readings so far: 2
```

The `postgres` service of the repository's `docker-compose.yaml` listens on port 5432, which must
be free. The example connects to `postgres://tellus:tellus@localhost:5432/tellus` unless the
environment variable `DATABASE_URL` names another database. The counts start at 1 only if the
database holds no events of this device yet, as after the first start of the service.

`docker compose down -v postgres` stops the database and deletes its volume, which resets the
readings.

## What you learned

Moving from memory to PostgreSQL changes the store, not the device, apart from its persistence ID.
With a database behind it, the device's events survive the process.

## Where to go from here

You have seen the core of event sourcing in tellus: commands, events, `handle` and `apply`,
recovery by replay, supervision and snapshots, in memory and in PostgreSQL. The explanation
[Event sourcing](@/docs/explanation/event-sourcing.md) covers the guarantees behind it, and the
how-to [Unit test an actor](@/docs/how-to/unit-test.md) shows how to test `handle` and `apply`
without a store.
