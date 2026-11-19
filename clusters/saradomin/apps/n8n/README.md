# n8n no saradomin

O [n8n](https://n8n.io) roda em `https://n8n.ftm.dev.br`, no namespace `automation`. O endereço é
público pelo túnel da Cloudflare do saradomin (`terraform/cloudflare/main.tf`), sem Access na
frente, porque os webhooks precisam chegar de fora. O editor fica protegido pelo login do próprio
n8n.

O banco é o `n8n` do `postgres-main` (`../postgres`). O role, o `Database` e a senha ficam em
`../postgres/n8n-db-secrets.yaml`. A mesma senha está em `DB_POSTGRESDB_PASSWORD` de `n8n-secrets`
(`secrets.yaml`). Não troque uma sem a outra.

`N8N_ENCRYPTION_KEY`, também em `n8n-secrets`, cifra as credenciais guardadas no banco. Ela não
depende do PVC: com o banco e a chave, uma instância nova abre as mesmas credenciais. Sem a chave, as
credenciais se perdem.

A versão está fixada no `deployment.yaml`, e o [Renovate](https://docs.renovatebot.com/) a
atualiza (`renovate.json` na raiz do repositório). Ele lê a versão dos
[releases do GitHub](https://github.com/n8n-io/n8n/releases), não do Docker Hub, porque o Docker
Hub publica as betas com tags iguais às das versões estáveis. Minor e patch entram com automerge, e
o Argo sobe a versão nova. Major vira um PR esperando revisão: leia as notas de breaking changes
antes do merge. As migrations do n8n não têm volta, e o caminho de volta é o backup do
`postgres-main` no R2.

## Ativar (uma vez)

1. **Túnel.** `make tf-plan` deve mostrar o `n8n.ftm.dev.br` saindo do túnel do zamorak e entrando
   no do saradomin: as duas configurações de túnel mudam, e o CNAME `n8n_dns` é atualizado no
   lugar. Depois, rode `make tf-apply`.
2. **Cluster.** Com o merge na `main`, o `saradomin-root` cria o role, o banco e o app. Na primeira
   subida, o n8n roda as migrations no banco vazio. O `startupProbe` dá até 5 minutos para isso.
3. **Dono.** Abra `https://n8n.ftm.dev.br` e crie a conta de dono. Até essa conta existir, quem
   abrir o endereço primeiro cria o dono, então faça isso logo depois do deploy.

## n8n Assistant

O sandbox onde o Assistant roda código é o `../n8n-sandbox`. O n8n chega nele por
`N8N_SANDBOX_SERVICE_URL`, com a chave `N8N_SANDBOX_SERVICE_API_KEY` de `n8n-secrets`, que é a
mesma do `api-keys` em `../n8n-sandbox/secrets.yaml`. A chave do modelo foi posta pela interface
(Settings › Assistant) e fica no banco, cifrada pela `N8N_ENCRYPTION_KEY`.

## Notas da 2.x

- O Code node roda no sidecar `task-runners` (imagem `n8nio/runners`, na mesma versão do n8n),
  que se liga ao broker em `localhost:5679` com o `N8N_RUNNERS_AUTH_TOKEN` de `n8n-secrets`. O
  sidecar roda JavaScript e Python, cada um com uma allowlist própria de módulos
  (`/etc/n8n-task-runners.json` da imagem). Por padrão, o JavaScript libera só `crypto` e
  `moment`, e o Python não libera nenhum.
- Os nodes Execute Command e Local File Trigger vêm desligados (`NODES_EXCLUDE`). O Read/Write
  Files só alcança `~/.n8n-files`. O Code node não lê variáveis de ambiente
  (`N8N_BLOCK_ENV_ACCESS_IN_NODE`).
- Community nodes: só os verificados pelo n8n (`N8N_UNVERIFIED_PACKAGES_ENABLED=false`).
