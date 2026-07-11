# Repository Guide

## Repository

- This is infrastructure as code for two K3s clusters: `saradomin` (home) and `zamorak` (Oracle Cloud). Kubernetes resources use Kustomize and KSOPS/SOPS; Terraform manages Cloudflare tunnels and DNS.
- `zamorak` runs on Oracle Cloud with 4 vCPUs, 24 GB RAM, and 200 GB storage; `saradomin` runs on an Intel N95 mini PC with 16 GB RAM and 512 GB storage. Keep these node limits in mind when setting workload resource requests.
- Treat `clusters/<cluster>/kustomization.yaml` as the deployment roots. A component is inactive unless it is transitively referenced there; for example, the `docling` resource is currently commented out.
- `README.md` describes a proposed structure that has drifted from the repository. Trust current kustomizations and the `Makefile`, not absent README entries or its `justfile` reference.
- Apps and infrastructure do not all have identical `base/` and `overlays/` layouts. Follow the nearest working component instead of creating a presumed directory pattern.

## Render And Deploy

- There is no configured CI, test suite, linter, or formatter. Verify a manifest change by rendering its focused kustomization, then the affected cluster root:

  ```sh
  kustomize build --enable-alpha-plugins --enable-exec <component-or-overlay>
  kustomize build --enable-alpha-plugins --enable-exec clusters/<cluster>/
  ```

- Keep both Kustomize flags: overlays use executable KSOPS generators, so plain `kubectl kustomize` is not equivalent.
- `make apply` and `make delete` are manual-only for `saradomin`, default to `saradomin`, and reject `CLUSTER=zamorak` before cluster contact. For any requested live deployment, always name the target explicitly: `make apply CLUSTER=saradomin` or `make delete CLUSTER=saradomin`.
- `zamorak` is reconciled by Argo CD; live setup uses exactly `make bootstrap-argocd CLUSTER=zamorak AGE_KEY_FILE=<path-to-age-key>` once or idempotently for recovery. Never run bootstrap merely to validate manifests; rendering remains the manifest validation method.
- Helm-managed infrastructure uses the K3s `helm.cattle.io/v1` `HelmChart` CRD, not direct `helm install` commands.

## Secrets And Terraform

- For a secret-bearing overlay, locate its active `ksops.yaml` and edit a local `secrets.dec.yaml` beside the referenced `secrets.yaml`; do not infer the path from the component root. Commit only the SOPS-encrypted `secrets.yaml`. Rendering requires the matching age private key outside this repository.
- `.gitignore` does not protect already tracked files. Check with `git ls-files '*secrets.dec.yaml'`; never expose or stage decrypted values, and treat cleanup or credential rotation as separate security work.
- `make encrypt` and `make decrypt` process the entire repository and redirect directly to destination files, so a SOPS failure can leave a destination truncated. For one secret, encrypt to a temporary file and replace the active `secrets.yaml` only after success.
- Terraform targets source the gitignored local `r2-secrets.sh` for the R2 state backend. Use `make tf-init`, then `make tf-plan`. `make tf-apply` computes a fresh interactive plan rather than applying the prior plan output; review it again before approval.
- `terraform/*.tfvars`, Terraform state, `.terraform/`, and `.terraform.lock.hcl` are ignored. Keep credentials and generated state artifacts out of commits.
- Public hostname changes can span an app `Ingress` and `terraform/cloudflare/main.tf`, which owns tunnel ingress rules and DNS records; check both layers.
