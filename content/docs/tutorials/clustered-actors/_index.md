+++
title         = "Clustered actors"
description   = "Run the device manager on several nodes: bootstrap, the receptionist, remote ask and remote watch."
weight        = 3
template      = "docs.html"
page_template = "docs-page.html"
sort_by       = "weight"
+++

The device manager of the [getting started tutorial](@/docs/tutorials/getting-started/_index.md)
runs in one process. In this tutorial it moves to its own node, and the other nodes find it, send
it readings, ask it for averages and learn when its node is gone. Every node is a process of its
own, but each step is still a single program: it starts the other nodes as child processes on
your machine. You need the `cluster-dev` feature, which adds a transport without certificate
checks for exactly this kind of local use. A production cluster authenticates its nodes with
mutual TLS instead, see [Secure with mutual TLS](@/docs/how-to/secure-with-mutual-tls.md). Besides
the crates of the getting started tutorial, the programs use serde with its `derive` feature.
