# mapa-do-acerto no zamorak

Este diretório é o lado do cluster (ADR-017 do mapa): `Application` do Argo CD
apontando para `deploy/k8s/overlays/zamorak` do repositório do mapa, `Database` CNPG,
e os Secrets. Como o app roda (Deployments, migration, Ingress, ConfigMap) está no
repositório do mapa e é atualizado pelo CI dele a cada merge na `main`.

## Ativar (uma vez)

1. **Segredos.** `sops clusters/zamorak/apps/mapa/secrets.yaml` e troque todo
   `CHANGE_ME`: senha do banco (nos dois Secrets), endpoint e credenciais do R2
   (bucket `mapa-do-acerto`), `API_CURSOR_SECRET` (`openssl rand -hex 32`),
   `API_INTERNAL_TOKEN` (o mesmo vai para o Worker do web) e a deploy key só-leitura
   do repositório do mapa (`ssh-keygen -t ed25519 -f mapa-argocd -N ''`; a pública
   em Settings → Deploy keys do mapa, a privada aqui).
2. **Cloudflare.** Zona `mapadoacerto.com.br` na conta; `mapa_zone_id` no tfvars;
   `make tf-plan` / `make tf-apply` cria o CNAME `api.` para o túnel e a regra de
   ingress. Regra de WAF na zona bloqueando `api.mapadoacerto.com.br` sem o header
   `X-Internal-Token` (pelo painel por enquanto). Domínio público do R2 em
   `assets.mapadoacerto.com.br`.
3. **Ligar.** Descomente `apps/mapa` em `clusters/zamorak/kustomization.yaml`. O role
   `mapa` em `apps/postgres/cluster.yaml` e o namespace `mapa` já entram junto.
4. Confira: `argocd app get mapa`; o Job `mapa-migrate` roda como PreSync e os
   Deployments `mapa-api` e `mapa-worker` sobem com uma réplica cada.

Antes do crawl completo: aumentar o volume do `postgres-main` (10 Gi hoje) e ligar o
backup Barman para o R2 (ADR-015 e ADR-017 do mapa).
