+++
title       = "Secure with mutual TLS"
description = "Authenticate every node with a certificate from the cluster's own certificate authority, bound to its address."
weight      = 9
+++

The `cluster-dev` transport checks no certificates, so anyone who can reach a node's port can talk
to it. A production cluster uses mutual TLS instead: every node presents a certificate from the
cluster's own certificate authority, and accepts only peers that do the same. The examples on this
page come from two nodes that form a cluster over mutual TLS. The first one creates the
certificates, builds its transport in code and starts the second one with a config file, the way a
deployed node reads its certificates.

## Issue the certificates

{{<example path="tellus/examples/how_to/secure_with_mutual_tls.rs" anchor="certificate-authority"/>}}

A node's certificate needs two things:

- The name every node validates its peers against, here `tellus` as a DNS name. All nodes share it.
- The address the node advertises, as a `tellus://<ip:port>` URI SAN. A node is admitted to the
  cluster only at an address its certificate covers, so an authenticated node cannot claim another
  member's address. Without such a URI, the advertised IP has to be among the certificate's IP
  address SANs, which then covers every port of that IP. That is enough as long as every IP hosts at
  most one node, as with one pod per IP on Kubernetes. A replaced pod gets a new IP and hence needs
  a new certificate, see
  [Run on Kubernetes](@/docs/how-to/run-on-kubernetes.md#mount-a-certificate-per-pod).

If a certificate lists extended key usages, it needs both server auth and client auth, since its
node presents it in both roles.

The example uses rcgen. In production, your certificate authority issues them, e.g. through
cert-manager, whose `Certificate` resource requests `uris` and `ipAddresses`. Set its `usages` to
include both `server auth` and `client auth`. SPIRE cannot issue either form of address.

## Build the transport in code

{{<example path="tellus/examples/how_to/secure_with_mutual_tls.rs" anchor="first-node"/>}}

`QuicTransport::mutual_tls` takes the address to bind to, the node's certificate chain and key, the
roots its peers' certificates must verify against, and the shared name. The node presents its
certificate as both server and client, so both sides of every connection are authenticated. A node
without a certificate from the cluster's authority cannot complete a connection, so it reaches
neither the protocol nor anybody's failure detection.

## Read the certificates from a config file

With the `serde` feature, `QuicConfig` names the PEM files, so it can come from your configuration:

{{<example path="tellus/examples/how_to/secure_with_mutual_tls.rs" anchor="second-node"/>}}

The second node reads a TOML file like this one, which the example writes next to the PEM files.
Only its `[transport]` table is a `QuicConfig`; `seeds` belongs to the example's own configuration:

```toml
seeds = ["127.0.0.1:41000", "127.0.0.1:41001"]

[transport]
bind_addr   = "127.0.0.1:41001"
cert_chain  = "/etc/tellus/tls/node-cert.pem"
key         = "/etc/tellus/tls/node-key.pem"
roots       = "/etc/tellus/tls/roots.pem"
server_name = "tellus"
```

`QuicTransport::from_config` reads and validates the files. It reads them once, so renewing a
certificate takes a restart of the node.

## Run it

From a clone of the tellus repository:

```sh
cargo run --quiet -p tellus --features cluster,serde --example how_to_secure_with_mutual_tls
```

```txt
Members up over mutual TLS: 2
```
