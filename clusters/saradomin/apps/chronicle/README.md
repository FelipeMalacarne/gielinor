# Chronicle no saradomin

Este diretório é o lado do cluster do Chronicle, o planner do Ironman
([FelipeMalacarne/chronicle](https://github.com/FelipeMalacarne/chronicle), privado):

- a `Application` do Argo CD, apontando para `deploy/k8s/overlays/saradomin` do repositório do planner;
- em `secrets.yaml` (SOPS): `chronicle-secrets` (o ambiente do app) e `repo-chronicle` no
  `argocd` (deploy key só de leitura, para o Argo ler o repositório privado).

O banco não fica aqui: é o `chronicle` do `postgres-main` (`../postgres`), com o role, o `Database` e a
senha em `../postgres/chronicle-db-secrets.yaml`. A mesma senha está na `DATABASE_URL` de
`chronicle-secrets`: não mude uma sem a outra.

Como o app roda está no `docs/07-ambiente-e-ferramental.md` (seção 3.3) do planner. O CI de lá publica
`ghcr.io/felipemalacarne/chronicle:<sha>` (uma imagem: o servidor e, no initContainer, `chronicle
migrate`) a cada push na `main` e grava o tag no overlay, então o Argo sobe a versão nova sozinho. O
pacote é público, como os dos outros apps daqui, então não há `imagePullSecret`; o repositório continua
privado.

Endereço: `https://chronicle.saradomin.ftm.dev.br`, só pela tailnet (Ingress do Traefik no `websecure`,
certificado curinga). O login é o Zitadel de `../zitadel`, público em `auth.ftm.dev.br`.

## Ativar (uma vez)

1. **Zitadel.** O projeto "Chronicle", as roles (`owner`, `ingest`, `items:bank`, `items:inventory`,
   `items:equipment`, `marks:write`), a aplicação Web (PKCE) e a nativa (device code, JWT), como no doc 07,
   seção 3.3, do planner.
2. **Segredos.** `sops clusters/saradomin/apps/chronicle/secrets.yaml`: em `chronicle-secrets`,
   `OIDC_CLIENT_ID` (app Web), `OIDC_NATIVE_CLIENT_ID` (app nativa), `OIDC_PROJECT_ID` e
   `OIDC_ALLOWED_SUBJECTS` (o id do usuário do dono). `DATABASE_URL` e `SESSION_SECRET` já foram
   gerados.
   **Imagem.** Depois do primeiro push do planner, o pacote `chronicle` do GHCR em Public (Package
   settings → Change visibility).
3. **Banco.** Com `apps/postgres` aplicado, o role e o banco `chronicle` existem. Antes de ligar o app,
   restaure nele o banco do zaros (`pg_dump --no-owner --no-acl`, restaurado como o role `chronicle`): o
   primeiro login web herda as contas.
4. **Ligar.** Descomente `apps/chronicle` em `clusters/saradomin/kustomization.yaml`. O `saradomin-root`
   cria a `Application` e os Secrets, e a `Application` sobe o app.
5. **Conferir.** `kubectl --context=saradomin -n chronicle get pods` com o `chronicle-…` pronto (o
   initContainer `migrate` termina antes); `https://chronicle.saradomin.ftm.dev.br` leva ao login do
   Zitadel e volta com a sessão.

## Pendências

- **Microbot:** `MICROBOT_CONTROL=off` aqui; o agent do zaros precisa de uma conta de máquina no Zitadel
  (doc 08 do planner) antes de ligar.
