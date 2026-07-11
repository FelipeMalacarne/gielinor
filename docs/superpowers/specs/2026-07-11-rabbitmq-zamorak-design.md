# RabbitMQ for Zamorak Design

**Date:** 2026-07-11

## Purpose

Deploy a persistent RabbitMQ broker on zamorak for n8n crawling workflows and
future Laravel event-driven workloads. RabbitMQ is a shared service, not part of
either application.

## Architecture

Install the RabbitMQ Cluster Operator and RabbitMQ Messaging Topology Operator
as cluster-wide controllers in the `rabbitmq-system` namespace. Version their
pinned upstream manifests locally and include them from the zamorak deployment
root.

Deploy a single `RabbitmqCluster` named `n8n-rabbitmq` in the existing
`databases` namespace. This keeps it with the other shared stateful services
(PostgreSQL and Redis) while leaving application namespaces independent.

The cluster has one replica, a 10 Gi `local-path` volume, a 500m CPU request and
limit, and a 1 Gi memory request and limit. This is a non-HA configuration:
RabbitMQ is unavailable while its only pod or host is unavailable. The service
remains `ClusterIP`; neither AMQP nor the management UI has an Ingress or other
public exposure.

Applications connect to:

```
n8n-rabbitmq.databases.svc.cluster.local:5672
```

Connections are internal to Kubernetes. TLS is out of scope for this initial,
cluster-local deployment; it must be added before any connection leaves the
cluster.

## Access Model

The Topology Operator declares an `events` virtual host and a non-admin `n8n`
user with configure, write, and read permissions scoped to that virtual host.
The user password is stored in a KSOPS-encrypted Secret alongside the RabbitMQ
overlay; no plaintext secret is committed.

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
routing keys before an event contract exists.

Future event topology is declared with the Topology Operator. Publishers send
messages to a `topic` exchange using routing keys such as `crawl.completed`.
Every consuming application owns a queue and binding:

- A queue bound to `crawl.*` receives crawling events.
- A queue bound to `#.completed` receives completion events.
- Multiple consumers that must each receive an event use separate queues.
- Consumers attached to the same queue compete for messages.

Durability, dead-lettering, retry policy, and routing-key ownership are defined
with each event contract rather than assumed by the broker bootstrap.

## Verification

Render the RabbitMQ operator kustomization, the RabbitMQ zamorak overlay, and
the full `clusters/zamorak` root with both KSOPS flags. Do not apply manifests as
part of validation.

After a requested deployment, verify that both operators are ready, the
`RabbitmqCluster` reports a ready status, its PVC is bound, and its ClusterIP
service is available. Configure the n8n credential manually without exposing
its password in shell history, logs, or repository files. A publish-and-consume
test belongs with the first concrete exchange and queue definition.

## Scope

Included: operators, a single persistent broker, internal service access, the
`events` vhost, and the n8n identity.

Excluded: high availability, public management access, TLS, monitoring stacks,
and application-specific messaging topology.
