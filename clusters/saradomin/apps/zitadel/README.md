# Zitadel no saradomin

> **Estado: plano, ainda sem manifests.** Este README guarda o plano para a próxima sessão continuar. Nada aqui está referenciado em `clusters/saradomin/kustomization.yaml`.

O provedor de identidade (OIDC) do cluster, começando pelo [lastro](https://github.com/FelipeMalacarne/lastro): a decisão está no ADR-0008 do lastro (`docs/adr/0008-identity-with-zitadel.md`), e o lado do lastro está no PR [FelipeMalacarne/lastro#7](https://github.com/FelipeMalacarne/lastro/pull/7). O guia de configuração do projeto e dos apps dentro do Zitadel é o `docs/zitadel.md` desse PR.

**O PR do lastro só é mergeado depois deste Zitadel estar no ar e do spike passar** (abaixo).

## Decisões

- **Onde:** saradomin, no namespace `security` (já existe em `../../namespaces.yaml` e está vazio). Fica no mesmo domínio de falha do lastro, o principal cliente, e o banco entra no backup R2 que já existe. O Vaultwarden (zamorak) fica fora do Zitadel: é lá que vão os códigos de recuperação e o admin do Zitadel.
- **Como:** o chart oficial (`https://charts.zitadel.com`, chart `zitadel`, linha v9, que traz o Zitadel v4 e o login v2), pelo `HelmChart` CRD do K3s, com os values num Secret SOPS via `valuesSecrets`, como em `../../infrastructure/cnpg/helmchart.yaml`. Fixar a versão do chart (a 9.24.0 era a mais nova vista; conferir o `index.yaml` do repositório).
- **Domínio:** `auth.ftm.dev.br`, pelo túnel do saradomin, **sem** Cloudflare Access na frente: os endpoints OAuth (discovery, token, device) precisam ser públicos. O console é protegido pelo próprio Zitadel (passkey/MFA).
- **Banco:** `zitadel` no `postgres-main` (CNPG), com role gerenciado `zitadel` dono do banco. O init job do chart roda só a fase `zitadel` (sem criar banco nem usuário, então sem credencial de superusuário).
- **Configuração do Zitadel:** `ExternalDomain: auth.ftm.dev.br`, `ExternalPort: 443`, `ExternalSecure: true`, TLS desligado no pod (o túnel termina o TLS, como no lastro). Login v2 ligado. Primeira instância com a org `gielinor` e o usuário admin (felipemalacarne012@gmail.com) com troca de senha obrigatória no primeiro login; registro aberto desligado.
- **Recursos:** o N95 tem 16 GB. Zitadel com ~512Mi de limite, login com ~256Mi; requests bem menores.

## Arquivos a criar

- [ ] `helmchart.yaml`: `HelmChart` `zitadel` em `security`, com `valuesSecrets`.
- [ ] `secrets.yaml` (SOPS) + `ksops.yaml`: os values do chart com a masterkey (32 caracteres), a senha do role `zitadel` e a senha inicial do admin.
- [ ] `ingress.yaml`: Traefik para `auth.ftm.dev.br`, backend em h2c (o Zitadel fala gRPC; anotação `traefik.ingress.kubernetes.io/service.serversscheme: h2c` no Service, ou o que o chart expuser), e as rotas do login v2 (`/ui/v2/login`). Seguir `../lastro` / o Ingress do lastro para o entrypoint usado atrás do túnel.
- [ ] `kustomization.yaml` (namespace `security`).
- [ ] `../postgres/databases.yaml`: `Database` `postgres-main-zitadel` (`name: zitadel`, `owner: zitadel`, `databaseReclaimPolicy: retain`).
- [ ] `../postgres/cluster.yaml`: role gerenciado `zitadel` (`login: true`, `passwordSecret: zitadel-db-secret`), e o `zitadel-db-secret` em `../postgres/secrets.yaml`. A mesma senha vai nos values do chart: não mudar uma sem a outra.
- [ ] `terraform/cloudflare/main.tf`: regra `auth.${var.zone}` no túnel do saradomin (para o Traefik, como a do lastro) e o CNAME `auth`.
- [ ] `clusters/saradomin/kustomization.yaml`: `apps/zitadel` **comentado**, com um comentário dizendo para ligar depois dos passos de ativação.

Segredos: gerar valores aleatórios e cifrar direto com `sops` (a chave pública está em `.sops.yaml`), sem imprimir. Felipe lê a senha do admin com a chave age dele. Precisa de `sops` e `kustomize` no ambiente.

## Ativar (Felipe)

1. `make tf-plan` / `make tf-apply`: túnel e DNS de `auth.ftm.dev.br`.
2. `kustomize build --enable-alpha-plugins --enable-exec clusters/saradomin/` com a chave age, depois descomentar `apps/zitadel` e `make apply CLUSTER=saradomin`.
3. Primeiro login em `https://auth.ftm.dev.br/ui/console`, trocar a senha, cadastrar a passkey e guardar os códigos de recuperação no Vaultwarden.
4. Criar o projeto `lastro` e os apps como no `docs/zitadel.md` do lastro#7, mais um app web de dev com redirect `http://localhost:8080/auth/callback` e post-logout `http://localhost:8080/`.

## Spike (antes de mergear o lastro#7)

Com o branch do lastro#7 rodando local (`task dev`) apontando para este Zitadel (`LASTRO_OIDC_ISSUER=https://auth.ftm.dev.br`, `LASTRO_PUBLIC_URL=http://localhost:8080`, `LASTRO_AUTH_DISABLED=false`):

- [ ] Login web em `http://localhost:8080/auth/login` termina com a sessão (o ID token traz `email` com "User info inside ID token").
- [ ] `lastro connect http://localhost:8080`: o device flow funciona e `lastro whoami` mostra `write`.
- [ ] O access token JWT traz o ID do projeto em `aud` (com o escopo `urn:zitadel:iam:org:project:id:<id>:aud`) e `azp`/`client_id` do app.
- [ ] Depois do merge e da troca: o conector do Claude com o client `lastro-claude` pré-registrado.

Se algo falhar, o ADR-0008 e o código do lastro#7 mudam antes do merge.
