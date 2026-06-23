# OpenClaw on saradomin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the openclaw gateway on the saradomin cluster using the OpenCode Go catalog model `opencode-go/deepseek-v4-flash`, exposed via Traefik at `openclaw.saradomin`.

**Architecture:** Single kustomize overlay at `apps/openclaw/overlays/saradomin/` derived from upstream `scripts/k8s/manifests/` with patches for remote bind, opencode-go model, an `OPENCODE_API_KEY` env var, an Ingress, and a ksops-managed Secret. Wired into `clusters/saradomin/kustomization.yaml`. Matches the existing `apps/n8n/overlays/zamorak/` shape.

**Tech Stack:** kustomize 5.x (with `--enable-alpha-plugins --enable-exec`), ksops, sops (age backend), Traefik ingress, coredns `*.saradomin` zone, ghcr.io/openclaw/openclaw:slim image.

**Spec:** `docs/superpowers/specs/2026-06-22-openclaw-saradomin-design.md`

**Notes for the executor:**
- This is GitOps YAML; "tests" are `kustomize build` renders + `grep` checks on the rendered output, plus a final `make apply` against the live cluster (last task only).
- Render checks use this exact command (matches the Makefile `apply` flow):
  ```bash
  kustomize build --enable-alpha-plugins --enable-exec apps/openclaw/overlays/saradomin/
  ```
  Until the cluster wiring task (Task 6), render the overlay directly; from Task 6 on, render via `clusters/saradomin/`.
- All paths are relative to repo root `/home/felipe/repos/gielinor` unless otherwise stated.
- Every task ends with a commit. Commit messages follow the existing repo style: short, lowercase, imperative (`add n8n app on zamorak`, `Adding n8n postgres database`).
- Secrets: `secrets.dec.yaml` is gitignored via `**/secrets.dec.yaml` in `.gitignore`. Only the sops-encrypted `secrets.yaml` is committed. The Makefile `encrypt` target runs `sops -e <file>.dec.yaml > secrets.yaml`.

---

## File structure

```
apps/openclaw/overlays/saradomin/
  kustomization.yaml      # namespace: ai; resources + ksops generator
  pvc.yaml                # 10Gi openclaw-home-pvc (verbatim from upstream)
  service.yaml            # ClusterIP :18789 (verbatim from upstream)
  configmap.yaml          # openclaw.json (remote bind, opencode-go model) + AGENTS.md
  deployment.yaml        # upstream + OPENCODE_API_KEY env + gielinor labels
  ingress.yaml            # traefik, host openclaw.saradomin
  ksops.yaml              # generator referencing secrets.yaml
  secrets.dec.yaml        # gitignored; plaintext source (placeholder until Task 7)
  secrets.yaml            # sops-encrypted; committed

clusters/saradomin/kustomization.yaml   # insert openclaw line into resources
```

No new namespace file is needed: the `ai` namespace already exists in
`clusters/saradomin/namespaces.yaml`.

---

### Task 1: Scaffold overlay dir + kustomization + verbatim pvc/service

**Files:**
- Create: `apps/openclaw/overlays/saradomin/kustomization.yaml`
- Create: `apps/openclaw/overlays/saradomin/pvc.yaml`
- Create: `apps/openclaw/overlays/saradomin/service.yaml`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p apps/openclaw/overlays/saradomin
```

- [ ] **Step 2: Write `kustomization.yaml`**

Path: `apps/openclaw/overlays/saradomin/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ai

resources:
  - pvc.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml

generators:
  - ksops.yaml
```

Note: `configmap.yaml`, `deployment.yaml`, `ingress.yaml`, and `ksops.yaml` are created in later tasks and will not exist yet — the render check in this task is intentionally limited to `pvc.yaml` and `service.yaml` by temporarily trimming `resources:`.

- [ ] **Step 3: Write `pvc.yaml` (verbatim from upstream)**

Path: `apps/openclaw/overlays/saradomin/pvc.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-home-pvc
  labels:
    app: openclaw
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

- [ ] **Step 4: Write `service.yaml` (verbatim from upstream)**

Path: `apps/openclaw/overlays/saradomin/service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: openclaw
  labels:
    app: openclaw
spec:
  type: ClusterIP
  selector:
    app: openclaw
  ports:
    - name: gateway
      port: 18789
      targetPort: 18789
      protocol: TCP
```

- [ ] **Step 5: Temporarily trim `kustomization.yaml` resources so render succeeds**

Edit `apps/openclaw/overlays/saradomin/kustomization.yaml` to:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ai

resources:
  - pvc.yaml
  - service.yaml

generators:
  - ksops.yaml
```

This trimmed version is only for the verification in Step 6. Later tasks add the remaining resources back.

- [ ] **Step 6: Verify render**

```bash
kustomize build apps/openclaw/overlays/saradomin/ > /tmp/openclaw-render.yaml
```

Expected: exit 0, `/tmp/openclaw-render.yaml` contains a PersistentVolumeClaim named `openclaw-home-pvc` and a Service named `openclaw`, both with `namespace: ai`.

Run:
```bash
grep -c "name: openclaw-home-pvc" /tmp/openclaw-render.yaml
grep -c "name: openclaw$" /tmp/openclaw-render.yaml
grep -c "namespace: ai" /tmp/openclaw-render.yaml
```
Expected: each prints `1` (or `>=1`).

- [ ] **Step 7: Commit**

```bash
git add apps/openclaw/overlays/saradomin/kustomization.yaml \
        apps/openclaw/overlays/saradomin/pvc.yaml \
        apps/openclaw/overlays/saradomin/service.yaml
git commit -m "scaffold openclaw overlay on saradomin"
```

---

### Task 2: ConfigMap with patched openclaw.json + AGENTS.md

**Files:**
- Create: `apps/openclaw/overlays/saradomin/configmap.yaml`

This overrides upstream: `gateway.mode: remote`, `gateway.bind: 0.0.0.0`, and adds `agents.defaults.model.primary: opencode-go/deepseek-v4-flash`. `AGENTS.md` is verbatim from upstream.

- [ ] **Step 1: Write `configmap.yaml`**

Path: `apps/openclaw/overlays/saradomin/configmap.yaml`
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  labels:
    app: openclaw
data:
  openclaw.json: |
    {
      "gateway": {
        "mode": "remote",
        "bind": "0.0.0.0",
        "port": 18789,
        "auth": {
          "mode": "token"
        },
        "controlUi": {
          "enabled": true
        }
      },
      "agents": {
        "defaults": {
          "workspace": "~/.openclaw/workspace",
          "model": {
            "primary": "opencode-go/deepseek-v4-flash"
          }
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
  AGENTS.md: |
    # OpenClaw Assistant

    You are a helpful AI assistant running in Kubernetes.

    Before proposing or building a custom system, feature, workflow, tool, integration, or automation, do a brief check for open-source projects, maintained libraries, existing OpenClaw plugins, or free platforms that already solve it well enough. Prefer those when adequate. Build custom only when existing options are unsuitable, too expensive, unmaintained, unsafe, non-compliant, or the user explicitly asks for custom. Avoid paid-service recommendations unless the user explicitly approves spend. Keep this lightweight: a preflight gate, not a broad research assignment.
```

- [ ] **Step 2: Add `configmap.yaml` back to `kustomization.yaml` resources**

Path: `apps/openclaw/overlays/saradomin/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ai

resources:
  - pvc.yaml
  - configmap.yaml
  - service.yaml

generators:
  - ksops.yaml
```

- [ ] **Step 3: Verify render**

```bash
kustomize build apps/openclaw/overlays/saradomin/ > /tmp/openclaw-render.yaml
```

Expected: exit 0. Verify the ConfigMap patched values are present:
```bash
grep -c '"mode": "remote"' /tmp/openclaw-render.yaml
grep -c '"bind": "0.0.0.0"' /tmp/openclaw-render.yaml
grep -c 'opencode-go/deepseek-v4-flash' /tmp/openclaw-render.yaml
```
Expected: `1` for each.

- [ ] **Step 4: Commit**

```bash
git add apps/openclaw/overlays/saradomin/configmap.yaml \
        apps/openclaw/overlays/saradomin/kustomization.yaml
git commit -m "add openclaw configmap (remote bind + opencode-go model) on saradomin"
```

---

### Task 3: Deployment with OPENCODE_API_KEY env + gielinor labels

**Files:**
- Create: `apps/openclaw/overlays/saradomin/deployment.yaml`

The Deployment is the upstream `scripts/k8s/manifests/deployment.yaml` with three changes:
1. Pod-level labels and selector include the gielinor convention.
2. The `initContainers[0].command` and `gateway` container keep upstream content untouched; only labels and env change.
3. A new `OPENCODE_API_KEY` env var is added to the `gateway` container, sourced from the `openclaw-secrets` Secret (non-optional).

- [ ] **Step 1: Write `deployment.yaml`**

Path: `apps/openclaw/overlays/saradomin/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw
  labels:
    app: openclaw
    app.kubernetes.io/name: openclaw
    app.kubernetes.io/part-of: openclaw
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openclaw
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: openclaw
        app.kubernetes.io/name: openclaw
        app.kubernetes.io/part-of: openclaw
    spec:
      automountServiceAccountToken: false
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: init-config
          image: busybox:1.37
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              cp /config/openclaw.json /home/node/.openclaw/openclaw.json
              mkdir -p /home/node/.openclaw/workspace
              cp /config/AGENTS.md /home/node/.openclaw/workspace/AGENTS.md
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
          resources:
            requests:
              memory: 32Mi
              cpu: 50m
            limits:
              memory: 64Mi
              cpu: 100m
          volumeMounts:
            - name: openclaw-home
              mountPath: /home/node/.openclaw
            - name: config
              mountPath: /config
      containers:
        - name: gateway
          image: ghcr.io/openclaw/openclaw:slim
          imagePullPolicy: IfNotPresent
          command:
            - node
            - /app/dist/index.js
            - gateway
            - run
          ports:
            - name: gateway
              containerPort: 18789
              protocol: TCP
          env:
            - name: HOME
              value: /home/node
            - name: OPENCLAW_CONFIG_DIR
              value: /home/node/.openclaw
            - name: NODE_ENV
              value: production
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: OPENCODE_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENCODE_API_KEY
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: ANTHROPIC_API_KEY
                  optional: true
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENAI_API_KEY
                  optional: true
            - name: GEMINI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: GEMINI_API_KEY
                  optional: true
            - name: OPENROUTER_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENROUTER_API_KEY
                  optional: true
          resources:
            requests:
              memory: 512Mi
              cpu: 250m
            limits:
              memory: 2Gi
              cpu: "1"
          livenessProbe:
            exec:
              command:
                - node
                - -e
                - "require('http').get('http://127.0.0.1:18789/healthz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 10
          readinessProbe:
            exec:
              command:
                - node
                - -e
                - "require('http').get('http://127.0.0.1:18789/readyz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
          volumeMounts:
            - name: openclaw-home
              mountPath: /home/node/.openclaw
            - name: tmp-volume
              mountPath: /tmp
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
      volumes:
        - name: openclaw-home
          persistentVolumeClaim:
            claimName: openclaw-home-pvc
        - name: config
          configMap:
            name: openclaw-config
        - name: tmp-volume
          emptyDir: {}
```

- [ ] **Step 2: Add `deployment.yaml` to `kustomization.yaml` resources**

Path: `apps/openclaw/overlays/saradomin/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ai

resources:
  - pvc.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml

generators:
  - ksops.yaml
```

- [ ] **Step 3: Verify render**

```bash
kustomize build apps/openclaw/overlays/saradomin/ > /tmp/openclaw-render.yaml
```

Expected: exit 0. Verify the patched bits are present:
```bash
grep -c "name: OPENCODE_API_KEY" /tmp/openclaw-render.yaml
grep -c "name: openclaw-secrets" /tmp/openclaw-render.yaml
grep -c "app.kubernetes.io/name: openclaw" /tmp/openclaw-render.yaml
```
Expected: `>=1` for each.

- [ ] **Step 4: Commit**

```bash
git add apps/openclaw/overlays/saradomin/deployment.yaml \
        apps/openclaw/overlays/saradomin/kustomization.yaml
git commit -m "add openclaw deployment with opencode-go api key on saradomin"
```

---

### Task 4: Traefik Ingress at openclaw.saradomin

**Files:**
- Create: `apps/openclaw/overlays/saradomin/ingress.yaml`

Matches the existing `apps/n8n/overlays/zamorak/ingress.yaml` annotations/structure; host is internal `openclaw.saradomin` (resolved by coredns's `*.saradomin` zone, same as `whoami.saradomin`).

- [ ] **Step 1: Write `ingress.yaml`**

Path: `apps/openclaw/overlays/saradomin/ingress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: openclaw
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

- [ ] **Step 2: Add `ingress.yaml` to `kustomization.yaml` resources**

Path: `apps/openclaw/overlays/saradomin/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ai

resources:
  - pvc.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml

generators:
  - ksops.yaml
```

- [ ] **Step 3: Verify render**

```bash
kustomize build apps/openclaw/overlays/saradomin/ > /tmp/openclaw-render.yaml
```

Expected: exit 0. Verify:
```bash
grep -c "host: openclaw.saradomin" /tmp/openclaw-render.yaml
grep -c "ingressClassName: traefik" /tmp/openclaw-render.yaml
```
Expected: `1` for each.

- [ ] **Step 4: Commit**

```bash
git add apps/openclaw/overlays/saradomin/ingress.yaml \
        apps/openclaw/overlays/saradomin/kustomization.yaml
git commit -m "add openclaw traefik ingress at openclaw.saradomin"
```

---

### Task 5: ksops generator + placeholder secrets

**Files:**
- Create: `apps/openclaw/overlays/saradomin/ksops.yaml`
- Create: `apps/openclaw/overlays/saradomin/secrets.dec.yaml` (gitignored)
- Create: `apps/openclaw/overlays/saradomin/secrets.yaml` (sops-encrypted, committed)

Until Task 7, the secret values are placeholders — enough to render and verify, not enough to authenticate. The overlay `kustomization.yaml` already references `ksops.yaml` via `generators:`.

- [ ] **Step 1: Write `ksops.yaml` (mirror `apps/n8n/overlays/zamorak/ksops.yaml`)**

Path: `apps/openclaw/overlays/saradomin/ksops.yaml`
```yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: ksops-generator
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ksops
files:
  - secrets.yaml
```

- [ ] **Step 2: Write `secrets.dec.yaml` with placeholder values**

Path: `apps/openclaw/overlays/saradomin/secrets.dec.yaml`
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-secrets
  namespace: ai
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: "REPLACE_WITH_openssl_rand_hex_32"
  OPENCODE_API_KEY: "REPLACE_WITH_REAL_KEY"
  ANTHROPIC_API_KEY: ""
  OPENAI_API_KEY: ""
  GEMINI_API_KEY: ""
  OPENROUTER_API_KEY: ""
```

(The empty provider keys satisfy the Deployment's `optional: true` secretKeyRefs without forcing the user to fill anything in. `OPENCLAW_GATEWAY_TOKEN` and `OPENCODE_API_KEY` are the only ones used in the main path.)

- [ ] **Step 3: Confirm `secrets.dec.yaml` is gitignored**

```bash
git check-ignore apps/openclaw/overlays/saradomin/secrets.dec.yaml
```
Expected: prints the path, exit 0 (matches `.gitignore` rule `**/secrets.dec.yaml`).

- [ ] **Step 4: Encrypt `secrets.dec.yaml` → `secrets.yaml`**

```bash
sops -e apps/openclaw/overlays/saradomin/secrets.dec.yaml > apps/openclaw/overlays/saradomin/secrets.yaml
```

Expected: exit 0, `secrets.yaml` exists and contains `sops:` metadata block and `mac:`/`encrypted_regex` style fields (no plaintext values).

- [ ] **Step 5: Verify ksops render works**

```bash
kustomize build --enable-alpha-plugins --enable-exec apps/openclaw/overlays/saradomin/ > /tmp/openclaw-render.yaml
```

Expected: exit 0. Verify the encrypted secret renders as a Kubernetes Secret named `openclaw-secrets` in namespace `ai`:
```bash
grep -c "name: openclaw-secrets" /tmp/openclaw-render.yaml
grep -c "namespace: ai" /tmp/openclaw-render.yaml
```
Expected: `>=1` for each.

(ksops decrypts `secrets.yaml` at build time using the age key from `.sops.yaml`. If this step fails with permission/key errors, the age key is missing or the SOPS_AGE_KEY_FILE env var is unset — verify against how `apps/n8n/overlays/zamorak` builds.)

- [ ] **Step 6: Commit**

```bash
git add apps/openclaw/overlays/saradomin/ksops.yaml \
        apps/openclaw/overlays/saradomin/secrets.yaml
git commit -m "add openclaw ksops secret generator on saradomin"
```

`secrets.dec.yaml` is intentionally not added (gitignored) — it stays local for editing in Task 7.

---

### Task 6: Wire overlay into the saradomin cluster

**Files:**
- Modify: `clusters/saradomin/kustomization.yaml`

- [ ] **Step 1: Edit `clusters/saradomin/kustomization.yaml` to add the openclaw resource**

Current content:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespaces.yaml
  - infrastructure
  # - ../../apps/docling/overlays/saradomin
  # - apps.yaml

labels:
  - pairs:
      gielinor.felipe/cluster: saradomin
      gielinor.felipe/site: home
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: false
```

New content (one line added to `resources:`, docling stays commented):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespaces.yaml
  - infrastructure
  - ../../apps/openclaw/overlays/saradomin
  # - ../../apps/docling/overlays/saradomin
  # - apps.yaml

labels:
  - pairs:
      gielinor.felipe/cluster: saradomin
      gielinor.felipe/site: home
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: false
```

- [ ] **Step 2: Build the full cluster render**

```bash
kustomize build --enable-alpha-plugins --enable-exec clusters/saradomin/ > /tmp/saradomin-render.yaml
```

Expected: exit 0. Verify openclaw resources are present alongside the existing infrastructure:
```bash
grep -c "name: openclaw$" /tmp/saradomin-render.yaml
grep -c "name: openclaw-secrets" /tmp/saradomin-render.yaml
grep -c "host: openclaw.saradomin" /tmp/saradomin-render.yaml
grep -c "gielinor.felipe/cluster: saradomin" /tmp/saradomin-render.yaml
```
Expected: `>=1` for each.

- [ ] **Step 3: Confirm `ai` namespace already has the cluster label propagation**

The cluster kustomization applies `gielinor.felipe/cluster: saradomin` to all included resources with `includeSelectors: false`. Verify the openclaw deployment picked it up:
```bash
grep -B2 -A2 "gielinor.felipe/cluster" /tmp/saradomin-render.yaml | grep -A2 "Deployment"
```
Expected: a block containing the Deployment metadata with the cluster label.

- [ ] **Step 4: Commit**

```bash
git add clusters/saradomin/kustomization.yaml
git commit -m "wire openclaw into saradomin cluster"
```

---

### Task 7: Fill real secrets + apply to cluster

This task touches secrets and the live cluster. Requires:
- An OpenCode/Zen API key the user has obtained (per https://docs.openclaw.ai/providers/opencode-go).
- `kubectx saradomin` already set up locally (the Makefile `apply` runs `kubectx $(CLUSTER)`).
- The age private key available to sops (same setup used for n8n/vaultwarden).

- [ ] **Step 1: Generate a gateway token**

```bash
openssl rand -hex 32 | tee /tmp/openclaw-gateway-token.txt
```

Save the printed hex string (this is the token you will paste into the Control UI auth prompt later).

- [ ] **Step 2: Edit `secrets.dec.yaml` with real values**

Path: `apps/openclaw/overlays/saradomin/secrets.dec.yaml`

Replace the two placeholder values:
- `OPENCLAW_GATEWAY_TOKEN`: paste the hex string from Step 1.
- `OPENCODE_API_KEY`: paste the user's OpenCode/Zen key.

Leave the four empty provider keys as empty strings.

The file should look like (with real values in place of `<...>`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-secrets
  namespace: ai
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: "<64-char hex from step 1>"
  OPENCODE_API_KEY: "<user's opencode/zen key>"
  ANTHROPIC_API_KEY: ""
  OPENAI_API_KEY: ""
  GEMINI_API_KEY: ""
  OPENROUTER_API_KEY: ""
```

- [ ] **Step 3: Re-encrypt**

```bash
sops -e apps/openclaw/overlays/saradomin/secrets.dec.yaml > apps/openclaw/overlays/saradomin/secrets.yaml
```

Verify no plaintext leaked into the encrypted file:
```bash
grep -E "sk-|<64-char-hex>" apps/openclaw/overlays/saradomin/secrets.yaml
```
Expected: no matches.

- [ ] **Step 4: Commit the updated encrypted secret**

```bash
git add apps/openclaw/overlays/saradomin/secrets.yaml
git commit -m "rotate openclaw secrets with real values on saradomin"
```

- [ ] **Step 5: Build final cluster render and verify secret is present**

```bash
kustomize build --enable-alpha-plugins --enable-exec clusters/saradomin/ > /tmp/saradomin-render.yaml
grep -c "name: openclaw-secrets" /tmp/saradomin-render.yaml
```
Expected: `>=1`.

(Do not `cat` the rendered Secret to avoid leaking plaintext in shell history; just confirm presence.)

- [ ] **Step 6: Apply to the saradomin cluster**

```bash
make apply CLUSTER=saradomin
```

Expected: kubectx switches to `saradomin`, kustomize build succeeds (same as the Makefile `apply` target), and `kubectl apply -f -` reports resources created/updated for `openclaw` (Deployment, Service, Ingress, PVC, ConfigMap, Secret).

- [ ] **Step 7: Wait for rollout**

```bash
kubectl -n ai rollout status deploy/openclaw --timeout=5m
```
Expected: `deployment "openclaw" successfully rolled out`.

If it fails with `ImagePullBackOff`, confirm `ghcr.io/openclaw/openclaw:slim` is reachable from the cluster nodes; if it fails with `CrashLoopBackOff`, check logs:
```bash
kubectl -n ai logs deploy/openclaw --tail=100
```
Common cause: bad `OPENCLAW_GATEWAY_TOKEN` or `OPENCODE_API_KEY` (sops decrypted but value is wrong). Fix `secrets.dec.yaml`, re-encrypt, re-apply.

- [ ] **Step 8: Verify the OpenCode Go catalog is reachable from inside the pod**

```bash
kubectl -n ai exec deploy/openclaw -- openclaw models list --provider opencode-go
```
Expected: lists `glm-5`, `kimi-k2.6`, `deepseek-v4-flash`, etc. — proves `OPENCODE_API_KEY` is wired and the cluster can reach the OpenCode endpoint.

- [ ] **Step 9: Verify Ingress routes from your LAN**

From a machine on the saradomin LAN (where coredns `*.saradomin` resolves):
```bash
curl -sf -H "Authorization: Bearer $(cat /tmp/openclaw-gateway-token.txt)" \
  http://openclaw.saradomin/healthz
```
Expected: HTTP 200, exit 0.

- [ ] **Step 10: Final commit (spec/plan status, if anything drifted)**

If applying surfaced any change (e.g., a label needed tweaking), commit it now:
```bash
git status
# only if there are uncommitted changes:
git add -A
git commit -m "fix openclaw apply drift on saradomin"
```

If no drift, this step is a no-op.

---

## Post-implementation verification summary

When all tasks are done, the following should be true:

| Check | Command |
| --- | --- |
| Overlay renders standalone | `kustomize build apps/openclaw/overlays/saradomin/` exits 0 |
| Cluster renders with openclaw | `kustomize build --enable-alpha-plugins --enable-exec clusters/saradomin/` exits 0 and contains `name: openclaw` |
| Live deployment healthy | `kubectl -n ai rollout status deploy/openclaw` → rolled out |
| OpenCode Go auth works | `kubectl -n ai exec deploy/openclaw -- openclaw models list --provider opencode-go` lists models |
| Ingress reachable on LAN | `curl -H "Authorization: Bearer $TOKEN" http://openclaw.saradomin/healthz` → 200 |
| Secrets stay encrypted in git | `git show HEAD:apps/openclaw/overlays/saradomin/secrets.yaml` contains `sops:` block, no plaintext keys |

## Follow-ups (not covered by this plan)

- Message channel wiring (Telegram/Discord/etc.) — add channel secrets and `agents.list` entries when needed.
- Non-main session sandbox — set `agents.defaults.sandbox.mode: "non-main"` when channels are wired.
- Public-domain exposure — switch host to a real domain and add cert-manager TLS, per a separate spec.
- Tracking upstream `scripts/k8s/manifests` — periodic `git diff` against the upstream repo to catch patches that should be ported here.