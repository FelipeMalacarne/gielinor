# OpenClaw on saradomin — design

Date: 2026-06-22
Status: Approved (pending user spec review)
Cluster: saradomin
Namespace: `ai` (existing)
App: openclaw gateway, image `ghcr.io/openclaw/openclaw:slim`

## Goal

Run the openclaw gateway on the saradomin cluster, using an OpenCode Go catalog
model (`opencode-go/<model>`) authenticated with an `OPENCODE_API_KEY`. Expose
the gateway's Control UI through Traefik so it is reachable from the local
network, matching the existing n8n / vaultwarden / whoami patterns in this repo.

## Non-goals

- Wiring any messaging channels (WhatsApp/Telegram/etc.). Gateway + Control UI only.
- Multi-agent routing beyond the upstream default `default` agent.
- Sandboxed/non-main sessions. The single main session runs with default tools.
- Public-domain exposure. The ingress uses an internal `*.saradomin` hostname.
- Tracking upstream `scripts/k8s/manifests` via remote kustomize resources. The
  manifests are copied into this repo and patched, so future upstream changes are
  merged manually.

## Approach

Single-overlay layout under `apps/openclaw/overlays/saradomin/`, mirroring the
shape of `apps/n8n/overlays/zamorak/`. Secrets are sops-encrypted (`secrets.yaml`)
and materialised at build time by ksops, exactly like n8n/vaultwarden. The openclaw
deployment is derived from upstream `scripts/k8s/manifests/{deployment,configmap,
pvc,service,kustomization}.yaml` with the patches described below.

## Layout

```
apps/openclaw/overlays/saradomin/
  kustomization.yaml      # namespace: ai; resources + ksops generator
  configmap.yaml          # openclaw.json + AGENTS.md
  deployment.yaml         # upstream + OPENCODE_API_KEY env + standard labels
  service.yaml            # ClusterIP :18789  (unchanged from upstream)
  ingress.yaml            # traefik, host openclaw.saradomin
  pvc.yaml                # 10Gi openclaw-home-pvc (upstream size)
  ksops.yaml              # generator referencing secrets.yaml
  secrets.dec.yaml        # gitignored; plaintext source for sops -e
  secrets.yaml            # sops-encrypted; committed

clusters/saradomin/namespaces.yaml      # unchanged (ai namespace already exists)
clusters/saradomin/kustomization.yaml   # + - ../../apps/openclaw/overlays/saradomin
```

`secrets.dec.yaml` is already covered by the repo-wide `.gitignore` rule
`**/secrets.dec.yaml`. Committed encrypted file is `secrets.yaml`.

## Patched `openclaw.json` (ConfigMap)

```jsonc
{
  "gateway": {
    "mode": "remote",
    "bind": "0.0.0.0",
    "port": 18789,
    "auth": { "mode": "token" },
    "controlUi": { "enabled": true }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": { "primary": "opencode-go/deepseek-v4-flash" }
    },
    "list": [
      {
        "id": "default",
        "name": "OpenClaw Assistant",
        "workspace": "~/.openclaw/workspace"
      }
    ]
  },
  "cron": { "enabled": false }
}
```

Differences from upstream defaults:
- `gateway.mode`: `local` → `remote` (required for non-loopback reach).
- `gateway.bind`: `loopback` → `0.0.0.0` (required for Service/Ingress).
- `agents.defaults.model.primary`: added, set to `opencode-go/deepseek-v4-flash`.

`AGENTS.md` is copied verbatim from upstream. Model ref can be changed later via
`openclaw config set agents.defaults.model.primary "opencode-go/<model>"` from
inside the pod, or by patching the ConfigMap.

## Patched `deployment.yaml` (deltas vs upstream)

1. Replace pod-level labels and selectors with the gielinor convention (also
   applied to `includeSelectors: false` via the cluster kustomization labels):
   - `app: openclaw`
   - `app.kubernetes.io/name: openclaw`
   - `app.kubernetes.io/part-of: openclaw`
2. Add env var to the `gateway` container, sourced from the ksops Secret:
   ```yaml
   - name: OPENCODE_API_KEY
     valueFrom:
       secretKeyRef:
         name: openclaw-secrets
         key: OPENCODE_API_KEY
         optional: false
   ```
   (Upstream's `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` /
   `OPENROUTER_API_KEY` `optional: true` slots are kept unchanged for future use.)
3. Everything else from upstream is kept: `apps/v1` Deployment, `Recreate`
   strategy, init-container that copies `openclaw.json` and `AGENTS.md` into
   `/home/node/.openclaw`, `automountServiceAccountToken: false`, non-root
   `securityContext` with `readOnlyRootFilesystem: true` and `capabilities.drop:
   [ALL]`, liveness/readiness probes hitting `/healthz` and `/readyz` on
   `127.0.0.1:18789`, resource requests/limits (512Mi/250m → 2Gi/1), `tmp-volume`
   emptyDir, `openclaw-home` PVC mount.

## `service.yaml`

Unchanged from upstream: ClusterIP, selector `app: openclaw`, port `18789`.

## `ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: openclaw
  namespace: ai
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: openclaw.saradomin
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: openclaw
                port:
                  number: 18789
```

Resolves via the existing saradomin coredns zone (`*.saradomin`), same as
`whoami.saradomin`. Not exposed publicly; access from inside the home network.

## `pvc.yaml`

Unchanged from upstream: `openclaw-home-pvc`, `ReadWriteOnce`, 10Gi.

## Secrets (`secrets.dec.yaml` → `secrets.yaml`)

`secrets.dec.yaml` (gitignored):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-secrets
  namespace: ai
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: "<openssl rand -hex 32>"
  OPENCODE_API_KEY: "<user-provided OpenCode/Zen API key>"
```

Encrypted with `sops -e secrets.dec.yaml > secrets.yaml` using the age key in
`.sops.yaml`. Built at kustomize-build time by the existing ksops generator
pattern (`apps/n8n/overlays/zamorak/ksops.yaml` shape).

Token generation, before applying:
```bash
openssl rand -hex 32
```

Both values are pasted into `secrets.dec.yaml`, then `make encrypt` writes
`secrets.yaml`. The Makefile `apply` target already passes
`--enable-alpha-plugins --enable-exec` to kustomize, which is required for ksops.

## Cluster wiring

`clusters/saradomin/namespaces.yaml`: no change (`ai` namespace already exists).

`clusters/saradomin/kustomization.yaml`:
```yaml
resources:
  - namespaces.yaml
  - infrastructure
  - ../../apps/openclaw/overlays/saradomin
```
(Uncomments/inserts the openclaw line; leaves docling commented as is.)

## Apply

```bash
make encrypt
make apply CLUSTER=saradomin
```

Verify:
```bash
kubectl -n ai rollout status deploy/openclaw
kubectl -n ai port-forward svc/openclaw 18789:18789
# Control UI: http://127.0.0.1:18789  (token = OPENCLAW_GATEWAY_TOKEN)
```

And on the LAN once coredns/traefik routing is in place:
```
http://openclaw.saradomin
```

## Verification

- `kustomize build --enable-alpha-plugins --enable-exec clusters/saradomin/`
  renders with no errors and contains the `openclaw` Deployment, Service,
  Ingress, PVC, ConfigMap, and a `Secret` named `openclaw-secrets`.
- `make apply CLUSTER=saradomin` creates all of the above in-cluster.
- `kubectl -n ai rollout status deploy/openclaw` reaches `successfully rolled
  out`.
- `kubectl -n ai exec deploy/openclaw -- openclaw models list --provider
  opencode-go` returns the Go catalog (proves `OPENCODE_API_KEY` is wired and
  reachable from inside the pod).
- `curl -H "Authorization: Bearer $TOKEN" http://openclaw.saradomin/healthz`
  from a machine on the LAN returns 200.

## Open questions / follow-ups (not in this spec)

- Channels (Telegram/Discord/etc.) — when needed, patch deployment with channel
  secrets and `agents.list`.
- Sandbox for non-main sessions — set `agents.defaults.sandbox.mode: "non-main"`
  when channels are wired.
- Public exposure — switch host to a public domain and add TLS via cert-manager
  when needed. Spec out a runup before that change.