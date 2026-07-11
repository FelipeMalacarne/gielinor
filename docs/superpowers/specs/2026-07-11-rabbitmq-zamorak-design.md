# RabbitMQ for Zamorak Design

**Date:** 2026-07-11

## Purpose

Deploy a persistent RabbitMQ broker on zamorak for n8n crawling workflows and
future Laravel event-driven workloads. RabbitMQ is a shared service, not part of
either application.

## Architecture

Install cert-manager `v1.21.0` in the `cert-manager` namespace using K3s's
`HelmChart` CRD. It issues and rotates the RabbitMQ operators' admission-webhook
certificates only; it does not configure RabbitMQ client TLS.

Install the RabbitMQ Cluster Operator `v2.22.1` and RabbitMQ Messaging Topology
Operator `v1.19.3` as cluster-wide controllers in the `rabbitmq-system`
namespace. Vendor their pinned upstream manifests locally, define the namespace
once in the local kustomization, and patch out the duplicate Namespace objects
contained in both upstream release bundles.

Deploy a single `RabbitmqCluster` named `rabbitmq` in the existing `databases`
namespace. This keeps it with the other shared stateful services (PostgreSQL and
Redis) while leaving application namespaces independent.

The cluster has one replica, a 10 Gi `local-path` volume, a 500m CPU request and
limit, and a 1 Gi memory request and limit. This is a non-HA configuration:
RabbitMQ is unavailable while its only pod or host is unavailable. The service
remains `ClusterIP`; neither AMQP nor the management UI has an Ingress or other
public exposure.

Applications connect to:

```
rabbitmq.databases.svc.cluster.local:5672
```

Connections are internal to Kubernetes. RabbitMQ client TLS is out of scope for
this initial, cluster-local deployment; it must be added before any connection
leaves the cluster.

## Access Model

The Topology Operator declares an `events` virtual host and a non-admin `n8n`
user. It generates the username and password and writes them to its owned
Kubernetes credentials Secret; no plaintext or encrypted application credential
is committed. The account can publish to exchanges and consume from queues in
`events`, but has no configure permission and cannot create or change RabbitMQ
resources.

n8n stays in the `automation` namespace. Its dedicated AMQP credential is
entered once in the n8n Credentials UI using the endpoint above, the `events`
vhost, and the `n8n` username and password. The credential is not mounted into
the n8n Deployment and is never logged by Kustomize rendering or validation.

The Cluster Operator's generated default administrative account is not used by
applications. When Laravel is deployed, it receives a distinct non-admin user
and password in the same `events` vhost. Application identities and credentials
are never shared.

## Event Topology

This deployment creates only the broker, `events` vhost, and application access.
It intentionally does not predefine business exchanges, queues, bindings, or
routing keys before an event contract exists. Kubernetes manifests owned by the
Topology Operator are the single source of truth for shared topology.

Future event topology is declared with the Topology Operator. Publishers send
messages to a `topic` exchange using routing keys such as `crawl.completed`.
Every consuming application owns a queue and binding:

- A queue bound to `crawl.*` receives crawling events.
- A queue bound to `#.completed` receives completion events.
- Multiple consumers that must each receive an event use separate queues.
- Consumers attached to the same queue compete for messages.

Durability, dead-lettering, retry policy, and routing-key ownership are defined
with each event contract rather than assumed by the broker bootstrap. An
application may receive narrowly scoped configure permission only for a private
queue it owns; it must not declare shared exchanges or bindings.

## Verification

Render the cert-manager kustomization, the RabbitMQ operator kustomization, the
RabbitMQ zamorak overlay, and the full `clusters/zamorak` root with both KSOPS
flags. Do not apply manifests as part of validation.

After a requested deployment, verify that cert-manager and both operators are
ready, their webhook Certificates are ready, the `RabbitmqCluster` reports a
ready status, its PVC is bound, and its ClusterIP service is available. Configure
the n8n credential manually without exposing its password in shell history,
logs, or repository files. A publish-and-consume test belongs with the first
concrete exchange and queue definition.

## Scope

Included: cert-manager, operators, a single persistent broker, internal service
access, the `events` vhost, and the n8n identity.

Excluded: high availability, public management access, RabbitMQ client TLS,
monitoring stacks, and application-specific messaging topology.
