DEC_SECRETS := $(shell find . -name "*.dec.yaml" 2>/dev/null)
ENC_SECRETS  := $(shell find . -name "secrets.yaml" 2>/dev/null)

CLUSTER ?= zamorak
TF_DIR := terraform

.PHONY: apply encrypt decrypt tf-init tf-plan tf-apply

apply: ## Deploy cluster to k8s (default: zamorak)
	kustomize build --enable-alpha-plugins --enable-exec "clusters/$(CLUSTER)/" | kubectl apply -f -

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
