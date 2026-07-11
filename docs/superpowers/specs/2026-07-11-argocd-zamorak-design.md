# Argo CD for Zamorak Design

## Goal

Replace routine imperative deployment of the `zamorak` cluster with Argo CD GitOps.
After a single local bootstrap, Argo CD must reconcile the public `gielinor`
repository automatically, correct drift, and prune resources removed from Git.

The initial migration is limited to `zamorak`. `saradomin` remains on its
existing deployment flow.

## Constraints

- Use the K3s `helm.cattle.io/v1` `HelmChart` CRD for Argo CD, matching the
  repository's existing Helm-managed infrastructure.
- Preserve the current Kustomize and KSOPS/SOPS workload layouts. No decrypted
  secrets may be committed.
- The SOPS age private key must be supplied locally at bootstrap time and kept
  outside Git and Argo ownership.
- The repository is public for this migration, so Argo CD does not need a Git
  repository credential. A future private-repository migration can add a
  bootstrap-managed SSH deploy-key Secret.
- Existing `zamorak` resources must be adopted in place; this migration does
  not recreate workloads or migrate persistent data.

## Architecture

### Argo CD Installation

Add `infrastructure/argocd/overlays/zamorak/` containing the pinned Argo CD
Helm chart configuration and its K3s `HelmChart` resource. The chart targets a
dedicated `argocd` namespace.

The repo server includes a pinned config-management plugin sidecar with
Kustomize, KSOPS, and SOPS. The sidecar receives the age key through a mounted
Secret in the `argocd` namespace. The Secret is not part of any Kustomization
or Argo Application.

### App Of Apps

Add a non-secret app-of-apps directory under `clusters/zamorak/argocd/`. Its
`zamorak-root` Application is the initial GitOps entry point and owns:

- The restricted `zamorak` Argo project.
- Its own Application manifest.
- An Argo CD self-management Application pointing at the HelmChart overlay.
- A namespaces Application.
- One child Application per active `zamorak` component.

The child Application paths use small cluster-local Kustomize wrappers around
the current component paths. The wrappers retain the `gielinor.felipe/cluster`
and `gielinor.felipe/site` labels while excluding selectors, matching the
current cluster-root behavior.

Children that reference KSOPS generators explicitly select the KSOPS plugin.
Children without encrypted secrets use Argo CD's native Kustomize rendering.

### Component Ownership

The initial child Applications cover the current active `zamorak` inputs:

- `namespaces.yaml`
- `infrastructure/cloudflared`
- `infrastructure/whoami/overlays/zamorak`
- `infrastructure/cnpg/base`
- `apps/postgres/overlays/zamorak`
- `apps/redis/overlays/zamorak`
- `apps/vaultwarden/overlays/zamorak`
- `apps/n8n/overlays/zamorak`

The namespace and Argo CD Applications are created before dependent workload
Applications through stable Application sync waves. All children enable
automated sync, self-healing, and pruning, with five retries using a five-second
initial backoff, a factor of two, and a three-minute maximum backoff.
CRD-dependent Applications retry while their controllers are being installed.

## Bootstrap And Reconciliation

`make bootstrap-argocd CLUSTER=zamorak AGE_KEY_FILE=/path/to/age-key` performs
the one-time imperative setup:

1. Validate the cluster name and local age-key file.
2. Apply the pinned Argo CD HelmChart resources only.
3. Wait for the Argo CD namespace and CRDs.
4. Create or update the age-key Secret from the supplied local file.
5. Wait for Argo CD to become available.
6. Apply the `zamorak` project and root Application.

The root Application subsequently owns its own definition, project, child
Applications, and Argo CD HelmChart configuration. The bootstrap command is
not a general deployment command.

Argo CD polls the public repository every three minutes. A commit is rendered
through native Kustomize or the KSOPS plugin and then automatically
synchronized. Its resource tracking adopts matching live resources on the first
sync without a planned replacement.

## Operations And Failure Handling

Retire routine full-cluster `make apply` and `make delete` for `zamorak`.
Retain the existing manual deployment flow for `saradomin`, and make a
`zamorak` value fail clearly with guidance to use Argo CD instead. Add focused
Argo CD targets for bootstrap, status, refresh or sync, and Application
listing.

The Argo project permits only this repository and the in-cluster API
destination. Its namespace allowlist is `argocd`, `automation`, `databases`,
`networking`, and `security`; its cluster-scoped resource allowlist includes
`Namespace`. This constrains future Applications from targeting unrelated
clusters, namespaces, or Git sources.

Git fetch, Kustomize, or SOPS failures do not change live resources. Argo CD
reports the affected Application as out of sync or degraded and retries
transient failures. A missing age-key Secret fails closed: it prevents the repo
server from rendering secret-backed resources rather than deploying incomplete
configuration.

Pruning is limited to resources tracked by each Application. The bootstrap age
key remains unmanaged and cannot be pruned by Argo CD.

## Verification

Before rollout:

- Render each changed Kustomize wrapper and the app-of-apps directory.
- Render the affected component paths with
  `--enable-alpha-plugins --enable-exec` where KSOPS is involved.
- Render `clusters/zamorak/` while it remains a useful compatibility check
  during the transition.

After bootstrap:

- Confirm every child Application is `Synced` and `Healthy`.
- Confirm the root and Argo CD self-management Applications are `Synced` and
  `Healthy`.
- Make a harmless Git-managed change and confirm automatic reconciliation,
  then verify a subsequent drift correction.

## Out Of Scope

- Migrating `saradomin`.
- Making the repository private or adding private-repository credentials.
- Introducing an external secret manager.
- Reorganizing inactive components or unrelated infrastructure.
