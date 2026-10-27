# Backup do postgres-main

O `postgres-main` arquiva o WAL continuamente e faz um backup base por dia, às 03:17 de São Paulo, no bucket `gielinor-postgres-backups` do R2. A janela de recuperação é de 30 dias: dá para voltar o banco a qualquer ponto desse período. Quem faz isso é o plugin Barman Cloud do CNPG (`../../../infrastructure/cnpg/plugin-barman-cloud.yaml`), que substitui o `barmanObjectStore` nativo, obsoleto desde o CNPG 1.26.

Este diretório é um componente do Kustomize, ligado e desligado inteiro em `../kustomization.yaml`:

- `objectstore.yaml`: o bucket, o endpoint da conta e a retenção;
- `cluster-plugin.yaml`: o patch que liga o plugin no `Cluster` como arquivador do WAL;
- `scheduledbackup.yaml`: o backup base diário (e um logo ao ligar);
- `secrets.yaml`: as credenciais do R2, criptografadas com SOPS.

## Ligar (uma vez)

1. **Bucket.** No painel da Cloudflare, em R2, crie o bucket `gielinor-postgres-backups` (localização automática). Ele fica fora do Terraform, como o `gielinor-tfstate` e o `mapa-do-acerto`.
2. **Token.** Em R2 › Manage API tokens › Create API token: permissão **Object Read & Write**, aplicada só ao bucket `gielinor-postgres-backups`, sem expiração. Guarde o *Access Key ID* e o *Secret Access Key* que aparecem no fim (o segredo só aparece uma vez).
3. **Segredos.** `sops clusters/saradomin/apps/postgres/backup/secrets.yaml` e troque os dois `CHANGE_ME` pelo par do passo 2.
4. **Ligar.** Descomente `components: [backup]` em `../kustomization.yaml` e faça o merge. O Argo aplica o `ObjectStore`, o `ScheduledBackup` e o patch no `Cluster`; o operador reinicia a instância com o sidecar do plugin (alguns segundos fora do ar) e o primeiro backup base começa em seguida.
5. **Conferir.**

   ```sh
   kubectl --context=saradomin -n databases get cluster postgres-main -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
   kubectl --context=saradomin -n databases get backups
   ```

   `ContinuousArchiving` deve estar `True` e o backup `postgres-main-daily-…` em `completed`. No bucket aparece `postgres-main/wals/` e `postgres-main/base/`.

O plugin precisa estar rodando antes do passo 4: `kubectl --context=saradomin -n databases rollout status deploy/barman-cloud`. Ele sobe sozinho com `infrastructure/cnpg`.

## Se o arquivamento falhar

Com `ContinuousArchiving` em `False`, o Postgres guarda no disco todo WAL que não conseguiu enviar, e o volume de 20 Gi enche. Veja o motivo em `kubectl --context=saradomin -n databases logs postgres-main-1 -c plugin-barman-cloud`. Credencial errada se corrige no passo 3 (o Secret tem `cnpg.io/reload`). Se for preciso parar, comente o componente de novo: o operador tira o plugin e o Postgres volta a reciclar o WAL.

## Restaurar

Um banco restaurado é um `Cluster` novo, criado a partir do backup; o `postgres-main` não é sobrescrito. Para um ponto no tempo (antes de um erro, por exemplo), num arquivo à parte no namespace `databases`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restore
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17
  storage:
    size: 20Gi
    storageClass: local-path
  bootstrap:
    recovery:
      source: postgres-main
      recoveryTarget:
        targetTime: "2026-11-02 21:00:00-03"   # omita para restaurar até o último WAL
  externalClusters:
    - name: postgres-main
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: r2-backups
          serverName: postgres-main
```

Ele sobe sem arquivar o próprio WAL. Confira os dados nele (`kubectl cnpg psql postgres-restore -n databases`) e então aponte os apps para `postgres-restore-rw.databases.svc`, ou copie o que faltou de volta para o `postgres-main` com `pg_dump`. Os roles gerenciados e os `Database` declarados aqui não vêm junto: o restore traz o conteúdo do banco, as senhas dos apps continuam nos Secrets deles.

Teste um restore assim de vez em quando: backup que nunca foi restaurado é só uma esperança.
