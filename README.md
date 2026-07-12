# Gielinor

Infrastructure as code for two K3s clusters:

- `saradomin`: home cluster, deployed manually with Kustomize.
- `zamorak`: Oracle Cloud cluster, reconciled by Argo CD.

## Structure

Each cluster owns all manifests deployed to it. This intentionally favors a
small amount of duplication over shared bases and cross-directory overlays.

```text
clusters/
  saradomin/
    apps/
    infrastructure/
    kustomization.yaml
    namespaces.yaml
  zamorak/
    apps/
    infrastructure/
    argocd/
    components/
    kustomization.yaml
terraform/
```

`clusters/<cluster>/kustomization.yaml` is the deployment root and the
authoritative inventory of active components. A component is inactive unless
it is referenced there.

Each component is a self-contained Kustomize package:

```text
apps/n8n/
  kustomization.yaml
  deployment.yaml
  service.yaml
  ingress.yaml
  ksops.yaml
  secrets.yaml
```

## Render

Render a component first, then its cluster root:

```sh
kustomize build --enable-alpha-plugins --enable-exec clusters/zamorak/apps/n8n
kustomize build --enable-alpha-plugins --enable-exec clusters/zamorak
```

The KSOPS generators require access to the matching SOPS age private key.

## Deploy

Deploy `saradomin` manually:

```sh
make apply CLUSTER=saradomin
```

`zamorak` is reconciled by Argo CD. Bootstrap or recover Argo CD with:

```sh
make bootstrap-argocd CLUSTER=zamorak AGE_KEY_FILE=/path/to/age-key
```

Do not bootstrap Argo CD merely to validate manifests; use `kustomize build`.

## Terraform

Terraform manages Cloudflare tunnels and DNS:

```sh
make tf-init
make tf-plan
```

The Terraform targets require the local, gitignored `r2-secrets.sh` file.
