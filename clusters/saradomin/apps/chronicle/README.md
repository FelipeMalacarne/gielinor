# Chronicle no saradomin

Este diretório é o lado do cluster do Chronicle, o planner do Ironman
([FelipeMalacarne/chronicle](https://github.com/FelipeMalacarne/chronicle), privado):

- a `Application` do Argo CD, apontando para `deploy/k8s/overlays/saradomin` do repositório do planner;
- em `secrets.yaml` (SOPS): `chronicle-secrets` (o ambiente do app) e `repo-chronicle` no
  `argocd` (deploy key só de leitura, para o Argo ler o repositório privado);
- o lado do cluster dos workers do Microbot (doc 11 do planner, seções 7 e 13), abaixo.

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

## Workers do Microbot

Um pod por conta (`worker-<conta>`), criado e apagado pelo próprio servidor, rodando o cliente do
Microbot headless com o `chronicle agent --worker` (doc 11 do planner). O Argo não gerencia esses
Deployments: eles não têm a etiqueta dele. O que é do cluster está aqui:

| Arquivo | O quê |
|---|---|
| `serviceaccounts.yaml` | `chronicle` (o servidor) e `chronicle-worker` (os pods worker: nenhuma permissão, `automountServiceAccountToken: false`) |
| `rbac.yaml` | Role `chronicle-workers` (Deployments: create, delete, get, list, watch, patch, update; pods: get, list, watch; nada em secrets) e `system:auth-delegator` para a TokenReview do token projetado |
| `admission.yaml` | ValidatingAdmissionPolicy: o que a SA `chronicle` escreve em Deployments só pode ser um worker (etiquetas, SA, imagem, `replicas <= 1`, `Recreate`, volumes, nada do host nem de Secrets); o Deployment do próprio app fica fora do alcance dela |
| `quota.yaml` | ResourceQuota: o app e até 3 workers (500m e 1Gi de requests cada) e 4 Deployments |
| `networkpolicy.yaml` | os workers não recebem conexão e saem só para o DNS, o servidor e a internet (sem LAN, rede do cluster nem tailnet) |
| `pvc.yaml` | `microbot-game-cache`, o cache do jogo compartilhado (`local-path`, 2Gi) |

### Ativar (uma vez)

1. **Ordem.** Este diretório (as SAs) vai para a `main` do gielinor e o `saradomin-root` sincroniza
   **antes** da versão do planner com `serviceAccountName: chronicle` no Deployment: sem a SA, o
   ReplicaSet não cria o pod e o app fica parado. Conferir com
   `kubectl --context=saradomin -n chronicle get sa,role,rolebinding,resourcequota,networkpolicy,pvc`
   e `kubectl --context=saradomin get validatingadmissionpolicy chronicle-workers`. O PVC fica
   Pending até o primeiro worker (`WaitForFirstConsumer`).
2. **Chave do cofre.** As sessões da Jagex ficam cifradas no banco com o `CHRONICLE_VAULT_KEY`
   (32 bytes em base64, AES-256-GCM). Gerar com `openssl rand -base64 32` e acrescentar a
   `chronicle-secrets` como o `AGENTS.md` manda: `sops clusters/saradomin/apps/chronicle/secrets.yaml`
   (ou um `secrets.dec.yaml` local cifrado para um arquivo temporário, que só então substitui o
   `secrets.yaml`), e commitar só o `secrets.yaml` cifrado. Guardar a chave também fora do cluster:
   sem ela, as sessões salvas não se abrem e cada conta precisa ser conectada de novo.
3. **Zitadel.** No projeto "Chronicle", as roles `microbot:control` (o Cockpit e os workers na web),
   dada ao dono, e `microbot:agent`, dada só à conta de máquina do agent do zaros (nenhuma pessoa a
   tem; doc 08 do planner). Os workers não usam o Zitadel: o agent deles entra pelo token projetado.
4. **Imagens.** A primeira `microbot-worker-base` publicada pelo CI do `microbot-plugins` e fixada no
   planner (`just worker-base-bump <tag>`); o CI do planner passa então a publicar
   `ghcr.io/felipemalacarne/chronicle-worker:<sha>` e grava `WORKER_IMAGE` no overlay. Os dois pacotes
   em Public no GHCR (Package settings → Change visibility), como o `chronicle`: o k3s baixa sem login.
5. **Ligar.** No planner, `WORKERS=on` no overlay (`deploy/k8s/overlays/saradomin`), depois do
   `CHRONICLE_VAULT_KEY` no `chronicle-secrets`: o servidor recusa subir com `WORKERS=on` sem a chave.
6. **Conferir.** Na web, conectar uma conta e iniciar o worker: `kubectl --context=saradomin -n
   chronicle get deploy,pods -l app.kubernetes.io/component=worker` mostra o `worker-<conta>`. Um
   worker além da quota não vira pod: o ReplicaSet registra `FailedCreate` ("exceeded quota").
