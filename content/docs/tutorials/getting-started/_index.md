+++
title         = "Getting started"
description   = "Your first actors: messages, a tree of actors, watch, supervision and timers."
weight        = 1
template      = "docs.html"
page_template = "docs-page.html"
sort_by       = "weight"
aliases       = [ "/guide/tutorial/" ]
+++

In this tutorial you build a small temperature monitor, from a single actor up to a device manager
with groups of devices. Along the way you meet messages, a tree of actors, watch, supervision and
timers. You write the first step in a project of your own and run the later ones as examples from
a clone of the tellus repository. The programs need tellus, Tokio and anyhow, and the last three
steps also thiserror and tracing-subscriber.
