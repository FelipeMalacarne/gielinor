# Argo CD On Zamorak

`zamorak` is reconciled by Argo CD from the public `main` branch of
`https://github.com/FelipeMalacarne/gielinor.git`. Do not use `make apply` or
`make delete` with `CLUSTER=zamorak`; those targets fail before contacting the
cluster. `saradomin` remains manually deployed through the existing Makefile
targets.

## Bootstrap

Bootstrap requires a local SOPS age private-key file. The key is placed in the
unmanaged `argocd-ksops-age-key` Secret and is never committed to this
repository.

```sh
make bootstrap-argocd CLUSTER=zamorak AGE_KEY_FILE="$SOPS_AGE_KEY_FILE"
```

The command installs Argo CD, waits for its CRDs and repo server, and creates
the `zamorak-root` Application. Afterwards, Argo CD polls `main` every three
minutes, syncs changes automatically, repairs drift, and prunes resources that
are removed from their managed component paths.

## Status

```sh
make argocd-apps CLUSTER=zamorak
make argocd-status CLUSTER=zamorak ARGOCD_APP=zamorak-root
```

Applications with encrypted manifests use the `kustomize-ksops` plugin. A
render failure or missing age-key Secret leaves the existing workload resources
unchanged and is reported in the relevant Application status.

## UI Access

The Argo CD server is intentionally a `ClusterIP` Service. Access it from an
authorized machine with:

```sh
kubectl --context=zamorak -n argocd port-forward service/argocd-server 8080:443
```

Retrieve the generated initial password only when an administrator needs to log
in, then change it immediately through the Argo CD UI or CLI:

```sh
kubectl --context=zamorak -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}{{"\n"}}'
```

## Recovery

If KSOPS reports an age-key error, rerun the idempotent bootstrap target with the same local key:

```sh
make bootstrap-argocd CLUSTER=zamorak AGE_KEY_FILE="$SOPS_AGE_KEY_FILE"
```
