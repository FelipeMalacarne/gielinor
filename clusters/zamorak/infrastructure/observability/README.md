# Zamorak Observability

Zamorak runs one Alloy StatefulSet, kube-state-metrics, node-exporter and a
Tailscale egress proxy. Saradomin hosts Prometheus, Loki and Grafana.

```text
Alloy -> saradomin-telemetry.observability.svc.cluster.local:80
      -> Tailscale egress -> saradomin-telemetry.osiris-fish.ts.net:80
      -> ingestion-only gateway on Saradomin -> Prometheus / Loki
```

The HTTP hop between clusters is encrypted by Tailscale. The gateway exposes
only `/api/v1/write`, `/loki/api/v1/push` and `/healthz`; it has no public
Ingress or Cloudflare route. The tailnet policy must permit the egress
device (`tag:k8s`) to reach the gateway device (`tag:k8s`) on TCP port 80.

## Collection

- Node CPU, memory, disk and network through node-exporter.
- Container usage and volume statistics through kubelet/cAdvisor.
- Pod, Deployment, StatefulSet, node and PVC state through kube-state-metrics.
- API server, CoreDNS and Alloy's own metrics.
- Pod logs from all namespaces through the Kubernetes logs API.
- Opt-in application metrics for Pods annotated with `prometheus.io/scrape:
  "true"` and `prometheus.io/port: "<declared container port>"`. An optional
  `prometheus.io/path` selects a path other than `/metrics`.

All telemetry carries `cluster="zamorak"`. Job names and `metrics_path`
labels match Saradomin's kube-prometheus-stack recording rules and dashboards.
Alloy is deliberately a singleton: multiple replicas would duplicate these
cluster-wide scrapes and logs unless collection is explicitly sharded.

## Buffering And Resources

The 5 GiB local-path PVC stores Alloy's metrics WAL and log WAL across Pod
restarts. Metrics have an 8-hour maximum WAL age and logs a 4-hour maximum
segment age. These are bounded, best-effort buffers, not a guarantee of
lossless recovery: disk exhaustion, node loss, retention and non-retryable
ingestion errors can discard data. Saradomin must be reachable to query data.

The pinned Alloy v1.19.2 requires `stabilityLevel: experimental` for Loki's
WAL. Validate upgrades with both WALs enabled. Metrics queues are limited to
two remote-write shards to bound memory usage and recovery load.

New CPU requests total 140m including the Tailscale operator: Alloy 50m,
its config reloader 10m, exporters 10m each, egress 10m and operator 50m.
n8n is disabled in the cluster root to make room; its PVC remains explicitly
referenced so Argo CD preserves its data.

## Deployment

Render this component and both affected cluster roots with
`kustomize build --enable-alpha-plugins --enable-exec`. Render the individual
Helm charts too: Kustomize only renders the K3s HelmChart objects.

Deploy Saradomin with `make apply CLUSTER=saradomin`. Zamorak is deployed
through Argo CD after changes reach `main`.

The root Application is managed separately from its resources. Apply
`clusters/zamorak/argocd/root-application.yaml` to the `zamorak` context when
changing its `ignoreDifferences` configuration. Its scoped
`/spec/externalName` exception and `RespectIgnoreDifferences=true` preserve
the DNS target managed by Tailscale for the egress Service.

## Verification

Confirm the Tailscale operator and both telemetry proxies are online, the
Alloy PVC is Bound, and all collector/exporter Pods are Ready. Check these
queries in Saradomin's Grafana Explore with its Prometheus datasource:

```promql
up{cluster="zamorak"}
count by (cluster) (kube_node_info)
count by (cluster) (node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate5m)
max(time() - prometheus_remote_storage_queue_highest_sent_timestamp_seconds{cluster="zamorak"})
```

All expected scrapes should be up. Recording rules need at least two scrapes
and an evaluation cycle; rate panels normally settle within five minutes.
In Loki, query `{cluster="zamorak"}` and confirm recent entries from multiple
namespaces. Use **Gielinor Cluster Overview**, the stock Kubernetes dashboards,
**Kubernetes Logs**, and **Kubernetes Log Volume** with the cluster selector.

For a restart check, restart `statefulset/alloy` on Zamorak and confirm the
same PVC is mounted and fresh samples/logs resume without duplicate collectors.
For a connectivity interruption, check the remote-write queue and retries;
verify recovery and absence of dropped samples/entries after connectivity
returns. The Kubernetes resources, data stores and dashboards are monitored;
notification destinations are not configured by this component.
