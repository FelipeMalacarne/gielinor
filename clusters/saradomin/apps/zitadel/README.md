# Zitadel no saradomin

O provedor de identidade (OIDC) do cluster, começando pelo [lastro](https://github.com/FelipeMalacarne/lastro): a decisão está no ADR-0008 do lastro (`docs/adr/0008-identity-with-zitadel.md`), e o lado do lastro está no PR [FelipeMalacarne/lastro#7](https://github.com/FelipeMalacarne/lastro/pull/7). O guia de configuração do projeto e dos apps dentro do Zitadel é o `docs/zitadel.md` desse PR.

**O PR do lastro só é mergeado depois deste Zitadel estar no ar e do spike passar** (abaixo).

## Como está montado

- **Onde:** namespace `security`, no mesmo domínio de falha do lastro, o principal cliente. O Vaultwarden (zamorak) fica fora do Zitadel: é lá que vão os códigos de recuperação, a senha do admin e uma cópia da masterkey.
- **Chart:** o oficial (`https://charts.zitadel.com`), versão fixa em `helmchart.yaml` (10.4.0: Zitadel v4.19.2 e o login v2), pelo `HelmChart` do K3s, como o CNPG em `../../infrastructure/cnpg`. Os values públicos estão em `values.yaml`; os cifrados entram por cima, pelo segundo `valuesSecrets`.
- **Domínio:** `auth.ftm.dev.br`, pelo túnel do saradomin, **sem** Cloudflare Access na frente: discovery, token e device precisam ser públicos. O console se protege com o próprio Zitadel (passkey). Os dois Ingress (o core em `/` e o login em `/ui/v2/login`) saem do chart, no entrypoint `web` do Traefik, como o do lastro; o Service do core já vem com `serversscheme: h2c`.
- **Banco:** `zitadel` no `postgres-main`, com o role gerenciado `zitadel` dono do banco (`../postgres`), dentro do backup do R2. O init job roda só a fase `zitadel`, sem credencial de superusuário.
- **Primeira instância:** org `gielinor`, o admin humano `felipemalacarne012@gmail.com` com troca de senha obrigatória, registro aberto e IdPs externos desligados. Sem a conta de máquina `iam-admin` que o chart cria por padrão: um PAT de `IAM_OWNER` parado num Secret do cluster não serve para nada por enquanto.
- **Recursos:** um pod de cada; core com 512Mi de limite, login com 256Mi.

## Segredos (`secrets.yaml`, SOPS)

| Secret | O que guarda |
|---|---|
| `zitadel-secret-values` | values do chart com a senha do role `zitadel` e a senha inicial do admin |
| `zitadel-masterkey` | a chave que cifra o que o Zitadel guarda no banco. **Nunca muda**: sem ela o banco (e o backup) fica ilegível |
| `zitadel-login-session-cookie` | assina o cookie do login v2; trocar só desloga do login |

A senha do role `zitadel` também está no `zitadel-db-secret` de `../postgres/secrets.yaml`: não mude uma sem a outra.

Para ler a senha inicial do admin e a masterkey (com a chave age):

```sh
sops decrypt clusters/saradomin/apps/zitadel/secrets.yaml \
  | yq 'select(.metadata.name == "zitadel-secret-values").stringData["values.yaml"]'
sops decrypt clusters/saradomin/apps/zitadel/secrets.yaml \
  | yq 'select(.metadata.name == "zitadel-masterkey").stringData.masterkey'
```

## Ativar

O saradomin é do Argo CD (`saradomin-root`, na `main`): o merge deste branch é o deploy. O Zitadel sobe sem o DNS sem problema; só fica inalcançável até o Terraform.

1. `make tf-plan` / `make tf-apply`: a regra `auth` no túnel do saradomin e o CNAME `auth.ftm.dev.br`.
2. Merge na `main` e esperar o Argo. Acompanhar com `kubectl --context saradomin -n security get helmchart,job,pod`: o `helm-install-zitadel` roda o init e o setup (hooks do chart) antes dos Deployments.
3. Primeiro login em `https://auth.ftm.dev.br/ui/console` com a senha acima, trocar a senha, cadastrar a passkey e guardar no Vaultwarden a nova senha, os códigos de recuperação e a masterkey.
4. Criar o projeto `lastro` e os apps como no `docs/zitadel.md` do lastro#7, mais um app web de dev com redirect `http://localhost:8080/auth/callback` e post-logout `http://localhost:8080/`.

## Spike (antes de mergear o lastro#7)

Com o branch do lastro#7 rodando local (`task dev`) apontando para este Zitadel (`LASTRO_OIDC_ISSUER=https://auth.ftm.dev.br`, `LASTRO_PUBLIC_URL=http://localhost:8080`, `LASTRO_AUTH_DISABLED=false`):

- [ ] Login web em `http://localhost:8080/auth/login` termina com a sessão (o ID token traz `email` com "User info inside ID token").
- [ ] `lastro connect http://localhost:8080`: o device flow funciona e `lastro whoami` mostra `write`.
- [ ] O access token JWT traz o ID do projeto em `aud` (com o escopo `urn:zitadel:iam:org:project:id:<id>:aud`) e `azp`/`client_id` do app.
- [ ] Depois do merge e da troca: o conector do Claude com o client `lastro-claude` pré-registrado.

Se algo falhar, o ADR-0008 e o código do lastro#7 mudam antes do merge.
