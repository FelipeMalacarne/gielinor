DEC_SECRETS := $(shell find . -name "*.dec.yaml" 2>/dev/null)
ENC_SECRETS  := $(shell find . -name "secrets.yaml" 2>/dev/null)

CLUSTER ?= saradomin
TF_DIR := terraform
AGE_KEY_FILE ?=
ARGOCD_APP ?= zamorak-root

.PHONY: apply delete bootstrap-argocd argocd-apps argocd-status encrypt decrypt tf-init tf-plan tf-apply

apply: ## Deploy saradomin with kustomize
	@test "$(CLUSTER)" = "saradomin" || { echo "zamorak is managed by Argo CD; commit to main and wait for reconciliation" >&2; exit 2; }
	kubectx $(CLUSTER)
	kustomize build --enable-alpha-plugins --enable-exec "clusters/$(CLUSTER)/" | kubectl apply -f -

delete: ## Delete saradomin resources rendered by kustomize
	@test "$(CLUSTER)" = "saradomin" || { echo "zamorak is managed by Argo CD; remove resources from Git and let Argo CD prune them" >&2; exit 2; }
	kubectx $(CLUSTER)
	kustomize build --enable-alpha-plugins --enable-exec "clusters/$(CLUSTER)/" | kubectl delete -f -

bootstrap-argocd: ## One-time Argo CD bootstrap for zamorak; AGE_KEY_FILE is required
	@test "$(CLUSTER)" = "zamorak" || { echo "bootstrap-argocd supports only CLUSTER=zamorak" >&2; exit 2; }
	@test -n "$(AGE_KEY_FILE)" || { echo "AGE_KEY_FILE must point to the SOPS age private key" >&2; exit 2; }
	@test -r "$(AGE_KEY_FILE)" || { echo "AGE_KEY_FILE is not readable: $(AGE_KEY_FILE)" >&2; exit 2; }
	kubectl --context="$(CLUSTER)" create namespace argocd --dry-run=client -o yaml | kubectl --context="$(CLUSTER)" apply -f -
	kubectl --context="$(CLUSTER)" -n argocd create secret generic argocd-ksops-age-key --from-file=keys.txt="$(AGE_KEY_FILE)" --dry-run=client -o yaml | kubectl --context="$(CLUSTER)" apply -f -
	kustomize build clusters/zamorak/infrastructure/argocd | kubectl --context="$(CLUSTER)" apply -f -
	kubectl --context="$(CLUSTER)" wait --for=condition=Established --timeout=5m crd/appprojects.argoproj.io
	kubectl --context="$(CLUSTER)" wait --for=condition=Established --timeout=5m crd/applications.argoproj.io
	kubectl --context="$(CLUSTER)" -n argocd wait --for=create --timeout=10m deployment/argocd-repo-server
	kubectl --context="$(CLUSTER)" -n argocd wait --for=create --timeout=10m deployment/argocd-server
	kubectl --context="$(CLUSTER)" -n argocd rollout status deployment/argocd-repo-server --timeout=10m
	kubectl --context="$(CLUSTER)" -n argocd rollout status deployment/argocd-server --timeout=10m
	kubectl --context="$(CLUSTER)" apply -f clusters/zamorak/argocd/root-application.yaml

argocd-apps: ## List zamorak Argo CD Applications
	@test "$(CLUSTER)" = "zamorak" || { echo "argocd-apps supports only CLUSTER=zamorak" >&2; exit 2; }
	kubectl --context="$(CLUSTER)" -n argocd get applications.argoproj.io

argocd-status: ## Show an Argo CD Application; ARGOCD_APP defaults to zamorak-root
	@test "$(CLUSTER)" = "zamorak" || { echo "argocd-status supports only CLUSTER=zamorak" >&2; exit 2; }
	kubectl --context="$(CLUSTER)" -n argocd get application.argoproj.io "$(ARGOCD_APP)" -o yaml

# ── Terraform ────────────────────────────────────────────
tf-init:
	@. ./r2-secrets.sh && terraform -chdir=$(TF_DIR) init

tf-plan:
	@. ./r2-secrets.sh && terraform -chdir=$(TF_DIR) plan

tf-apply:
	@. ./r2-secrets.sh && terraform -chdir=$(TF_DIR) apply

# ── Secrets ──────────────────────────────────────────────
encrypt: ## Encrypt all *.dec.yaml → secrets.yaml
	@for f in $(DEC_SECRETS); do \
		out=$$(dirname "$$f")/secrets.yaml; \
		echo "Encrypting $$f → $$out"; \
		sops -e "$$f" > "$$out"; \
	done

decrypt: ## Decrypt all secrets.yaml → *.dec.yaml
	@for f in $(ENC_SECRETS); do \
		out=$$(dirname "$$f")/$$(basename "$$f" .yaml).dec.yaml; \
		echo "Decrypting $$f → $$out"; \
		sops -d "$$f" > "$$out"; \
	done
