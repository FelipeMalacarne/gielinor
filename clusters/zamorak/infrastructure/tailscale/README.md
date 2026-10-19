# Tailscale On Zamorak

This component installs the Tailscale Kubernetes Operator through a K3s
`HelmChart`. Its tailnet hostname is `zamorak-k8s-operator`.

## Credentials

Use a separate OAuth client for Zamorak in the same tailnet as Saradomin.
In the Tailscale [Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials)
page, create a client named `zamorak-k8s-operator` with write access to:

- General / Services
- Devices / Core
- Keys / Auth Keys

Select `tag:k8s-operator` for the tagged scopes. The existing tailnet policy
must allow `tag:k8s-operator` to own `tag:k8s`, which is the tag used for
operator-managed proxies.

Store the client ID and client secret in the Git-ignored `secrets.dec.yaml`
beside `ksops.yaml`, using this structure:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: operator-oauth
  namespace: tailscale
type: Opaque
stringData:
  client_id: "<client ID>"
  client_secret: "<client secret>"
```

Encrypt to a temporary file with SOPS and replace `secrets.yaml` only after
encryption succeeds. Only the encrypted `secrets.yaml` belongs in Git.

## Deployment And Verification

The component is included in `clusters/zamorak/kustomization.yaml`.
Render the component, then the cluster:

```sh
SOPS_AGE_KEY_FILE=/var/lib/sops-age/keys.txt kustomize build --enable-alpha-plugins --enable-exec clusters/zamorak/infrastructure/tailscale >/dev/null
SOPS_AGE_KEY_FILE=/var/lib/sops-age/keys.txt kustomize build --enable-alpha-plugins --enable-exec clusters/zamorak >/dev/null
```

Argo CD deploys changes after they reach `main`. Once reconciled:

```sh
kubectl --context=zamorak -n tailscale rollout status deployment/operator --timeout=5m
kubectl --context=zamorak -n tailscale get pods
```

Confirm `zamorak-k8s-operator` appears online in the Tailscale Machines page
with `tag:k8s-operator`; a running Deployment alone does not establish that
tailnet authentication succeeded.

## Observability Connectivity

The observability component defines the Alloy collector and an egress
Service/proxy targeting Saradomin's telemetry gateway. See
`../observability/README.md` for the topology and verification steps.

For an egress `ExternalName` Service, Tailscale owns `spec.externalName`.
Configure Argo CD to ignore that field for the specific Service and enable
`RespectIgnoreDifferences=true` so reconciliation does not undo the
operator's DNS routing.

See the upstream [installation guide](https://tailscale.com/docs/kubernetes-operator/install-operator)
and [egress guide](https://tailscale.com/docs/kubernetes-operator/egress).
