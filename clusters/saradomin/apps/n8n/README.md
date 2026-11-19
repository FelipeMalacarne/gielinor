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

## Notas da 2.x

- O Code node roda num task runner interno, no mesmo pod. Python precisa do runner externo
  (imagem `n8nio/runners`), que não está configurado aqui.
- Os nodes Execute Command e Local File Trigger vêm desligados (`NODES_EXCLUDE`). O Read/Write
  Files só alcança `~/.n8n-files`. O Code node não lê variáveis de ambiente
  (`N8N_BLOCK_ENV_ACCESS_IN_NODE`).
